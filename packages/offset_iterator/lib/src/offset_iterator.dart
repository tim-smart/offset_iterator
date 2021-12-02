import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';

class OffsetIteratorState<T> {
  const OffsetIteratorState({
    required this.acc,
    required this.chunk,
    required this.hasMore,
  });

  final dynamic acc;
  final List<T> chunk;
  final bool hasMore;
}

typedef InitCallback = FutureOr<dynamic> Function();
typedef ProcessCallback<T> = FutureOr<OffsetIteratorState<T>> Function(dynamic);
typedef CleanupCallback = void Function(dynamic);
typedef SeedCallback<T> = T? Function();

enum OffsetIteratorStatus {
  unseeded,
  seeded,
  active,
  completed,
}

class OffsetIterator<T> {
  OffsetIterator({
    required InitCallback init,
    required ProcessCallback<T> process,
    CleanupCallback? cleanup,
    SeedCallback? seed,
    this.retention = 0,
  })  : _init = init,
        _process = process,
        _cleanup = cleanup,
        _seed = seed;

  final InitCallback _init;
  final ProcessCallback<T> _process;
  final CleanupCallback? _cleanup;
  final SeedCallback? _seed;

  /// The latest state from the `process` function.
  OffsetIteratorState<T>? state;

  /// The internal status
  OffsetIteratorStatus get status => _status;
  var _status = OffsetIteratorStatus.unseeded;
  FutureOr<OffsetIteratorState<T>>? _processFuture;

  T? _value;

  /// Get the current head value, or `null`.
  T? get valueOrNull {
    _maybeSeedValue();
    return _value;
  }

  /// Get the current head value as an option.
  Option<T> get value => optionOf(valueOrNull);

  /// How many items to retain in the log.
  /// If set to a negative number (e.g. -1), it will retain everything.
  /// Defaults to 0 (retains nothing).
  final int retention;

  /// The current head offset.
  int get offset {
    _maybeSeedValue();
    return _offset;
  }

  /// The earliest offset that still has a value
  int get earliestAvailableOffset => offset - log.length;

  var _offset = 0;

  /// The buffer contains items that have yet to be pulled.
  /// The `process` function can return a chunk of multiple items, but because
  /// `pull` only returns one item at a time, the extra items are buffered.
  final buffer = Queue<T>();

  /// The log contains previously pulled items. Retention is controlled by the
  /// `rentention` property.
  final log = Queue<T>();

  final _listeners = <void Function()>[];

  /// Check if there is more items after the specified offset.
  /// If no offset it specified, it uses the head offset.
  bool hasMore([int? offset]) {
    offset ??= _offset;
    return offset < _offset ||
        offset < (_offset + buffer.length) ||
        (state?.hasMore ?? true);
  }

  /// Checks if the specified offset is the last item.
  bool isLastOffset(int offset) => !hasMore(offset);

  void _maybeSeedValue() {
    if (_status != OffsetIteratorStatus.unseeded) return;
    _value = _seed?.call();
    _status = OffsetIteratorStatus.seeded;
  }

  /// Pull the next item. If `currentOffset` is not provided, it will use the
  /// latest head offset.
  Future<Option<T>> pull([int? currentOffset]) async {
    final offset = currentOffset ?? _offset;
    if (offset < 0 || offset > _offset) {
      throw RangeError.range(offset, 0, _offset, 'currentOffset');
    }

    if (state == null) {
      _maybeSeedValue();
      final initResult = _init();
      final acc = initResult is Future ? await initResult : initResult;

      state = OffsetIteratorState(
        acc: acc,
        chunk: [],
        hasMore: true,
      );

      _status = OffsetIteratorStatus.active;
    }

    // Handle offset requests for previous items
    if (offset < _offset) return valueAt(offset + 1);

    // Maybe fetch next chunk and re-fill buffer
    if (buffer.isEmpty) {
      if (state!.hasMore == false) return const None();

      if (_processFuture != null) {
        await _processFuture;
        return pull(offset);
      }

      try {
        _processFuture = _process(state!.acc);

        if (_processFuture is Future) {
          final nextState = await _processFuture;
          if (!state!.hasMore) return const None();
          state = nextState;
        } else {
          state = _processFuture as OffsetIteratorState<T>;
        }
      } finally {
        _processFuture = null;
      }

      if (state!.hasMore == false) {
        cancel();
      }

      final chunkLength = state!.chunk.length;
      if (chunkLength == 0) {
        if (state!.hasMore == false) {
          _notifyListeners();
        }

        return pull(offset);
      } else if (chunkLength == 1) {
        return _nextItem(state!.chunk.first);
      }

      buffer.addAll(state!.chunk);
    }

    return _nextItem(buffer.removeFirst());
  }

  Option<T> _nextItem(T item) {
    if (retention != 0 && _value != null) {
      log.add(_value!);

      while (retention > -1 && log.length > retention) {
        log.removeFirst();
      }
    }

    _value = item;
    _offset = _offset + 1;

    _notifyListeners();

    return Some(item);
  }

  Option<T> valueAt(int offset) {
    if (offset == _offset) {
      return value;
    }

    final reverseIndex = _offset - offset;
    final logLength = log.length;

    if (reverseIndex > logLength) return const None();

    final index = logLength - reverseIndex;
    return Some(log.elementAt(index));
  }

  /// Prevents any new items from being added to the buffer, and
  void cancel() {
    if (_status == OffsetIteratorStatus.completed) return;

    if (_status == OffsetIteratorStatus.active) {
      if (_cleanup != null) {
        _cleanup!(state!.acc);
      }

      state = OffsetIteratorState(
        acc: state!.acc,
        chunk: state!.chunk,
        hasMore: false,
      );
    }

    _status = OffsetIteratorStatus.completed;
  }

  SeedCallback<T>? generateSeed({
    int? startOffset,
    SeedCallback<T>? override,
    SeedCallback<T>? fallback,
  }) {
    if (override != null) return override;

    _maybeSeedValue();

    if (startOffset != null) {
      final value = valueAt(startOffset).toNullable();
      return value != null ? (() => value) : fallback;
    }

    return () => valueOrNull ?? fallback?.call();
  }

  set earliestAvailableOffset(int offset) {
    if (offset > this.offset || offset < 2) return;

    final targetLogLength = _offset - offset;
    while (targetLogLength < log.length) {
      log.removeFirst();
    }
  }

  void _notifyListeners() {
    if (_listeners.isEmpty) return;

    for (final listener in _listeners) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.removeWhere((element) => element == listener);
  }

  void removeAllListeners() => _listeners.clear();

  /// Create an `OffsetIterator` from the provided `Stream`.
  /// If a `ValueStream` with a seed is given, it will populate the iterator's
  /// seed value.
  static OffsetIterator<T> fromStream<T>(
    Stream<T> stream, {
    int retention = 0,
    SeedCallback<T>? seed,
  }) {
    final valueStreamSeed =
        Option.tryCatch(() => (stream as dynamic).valueOrNull as T?);

    stream = valueStreamSeed.match(
      (_) => stream.skip(1),
      () => stream,
    );

    return OffsetIterator(
      init: () => StreamIterator(stream),
      process: (i) async {
        final iter = i as StreamIterator<T>;
        final available = await iter.moveNext();

        return OffsetIteratorState(
          acc: iter,
          chunk: available ? [iter.current] : [],
          hasMore: available,
        );
      },
      cleanup: (i) => (i as StreamIterator<T>).cancel(),
      seed: seed ?? () => valueStreamSeed.toNullable(),
      retention: retention,
    );
  }

  /// Create an `OffsetIterator` from the provided `Iterable`.
  static OffsetIterator<T> fromIterable<T>(
    Iterable<T> iterable, {
    int retention = 0,
    SeedCallback<T>? seed,
  }) =>
      OffsetIterator(
        init: () {},
        process: (acc) => OffsetIteratorState(
          acc: null,
          chunk: iterable.toList(),
          hasMore: false,
        ),
        seed: seed,
        retention: retention,
      );

  static OffsetIterator<T> fromValue<T>(T value, {SeedCallback<T>? seed}) =>
      fromIterable([value], seed: seed);

  static OffsetIterator<T> fromFuture<T>(
    Future<T> Function() future, {
    SeedCallback<T>? seed,
  }) =>
      OffsetIterator(
        init: () {},
        process: (_) async => OffsetIteratorState(
          acc: null,
          chunk: [await future()],
          hasMore: false,
        ),
        seed: seed,
      );

  static OffsetIterator<int> range(
    int start, {
    int? end,
    int retention = 0,
    SeedCallback<int>? seed,
  }) =>
      OffsetIterator(
        init: () => start,
        process: (current) => OffsetIteratorState(
          acc: current + 1,
          chunk: current > end ? [] : [current],
          hasMore: end != null ? current < end : true,
        ),
        seed: seed,
        retention: retention,
      );
}
