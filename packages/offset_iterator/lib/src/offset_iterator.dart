import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';

class OffsetIteratorState<T> {
  const OffsetIteratorState({
    this.acc,
    this.chunk = const [],
    this.hasMore = true,
    this.error,
    this.stackTrace,
  });

  final dynamic acc;
  final Iterable<T> chunk;
  final bool hasMore;
  final dynamic error;
  final StackTrace? stackTrace;
}

typedef InitCallback = FutureOr<dynamic> Function();
typedef ProcessCallback<T> = FutureOr<OffsetIteratorState<T>> Function(dynamic);
typedef CleanupCallback = FutureOr<void> Function(dynamic);
typedef SeedCallback<T> = Option<T> Function();

enum OffsetIteratorStatus {
  unseeded,
  seeded,
  active,
  completed,
}

class OffsetIterator<T> {
  OffsetIterator({
    InitCallback? init,
    required ProcessCallback<T> process,
    CleanupCallback? cleanup,
    SeedCallback<T>? seed,
    this.retention = 0,
    bool? cancelOnError,
  })  : _init = init,
        _process = process,
        _seed = seed,
        cancelOnError = cancelOnError ?? cleanup != null {
    _cleanup = cleanup ?? (_) {};
  }

  final InitCallback? _init;
  final ProcessCallback<T> _process;
  late final CleanupCallback _cleanup;
  final SeedCallback<T>? _seed;

  /// If `true`, [cancel] will be called on error.
  final bool cancelOnError;

  /// The latest state from the `process` function.
  var state = OffsetIteratorState<T>(acc: null);

  /// The internal status
  OffsetIteratorStatus get status => _status;
  var _status = OffsetIteratorStatus.unseeded;

  bool _processing = false;
  Completer<void>? _processingCompleter;
  Future<void> get _processingFuture {
    if (_processingCompleter != null) return _processingCompleter!.future;
    _processingCompleter = Completer.sync();
    return _processingCompleter!.future;
  }

  Option<T> _value = none<T>();

  /// Get the current head value as an option.
  Option<T> get value {
    _maybeSeedValue();
    return _value;
  }

  /// Get the current head value, or `null`.
  T? get valueOrNull => value.toNullable();

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
    if (offset == null) {
      return state.hasMore || buffer.isNotEmpty;
    }

    return offset < _offset ||
        offset < (_offset + buffer.length) ||
        state.hasMore;
  }

  /// Checks if the specified offset is the last item.
  bool isLastOffset(int offset) => !hasMore(offset);

  /// Returns `true` if all the data has been pulled.
  bool get drained => buffer.isEmpty && !state.hasMore;

  void _maybeSeedValue() {
    if (_status != OffsetIteratorStatus.unseeded) return;
    if (_seed != null) _value = _seed!();
    _status = OffsetIteratorStatus.seeded;
  }

  // ==== Pull chain starts here

  /// Pull the next item. If `currentOffset` is not provided, it will use the
  /// latest head offset.
  FutureOr<Option<T>> pull([int? currentOffset]) {
    final offset = currentOffset ?? _offset;
    if (offset < 0 || offset > _offset) {
      throw RangeError.range(offset, 0, _offset, 'currentOffset');
    }

    if (_status.index < OffsetIteratorStatus.active.index) {
      _maybeSeedValue();

      if (_init == null) return _handleInit(offset, null);

      final initResult = _init!();
      return initResult is Future
          ? initResult.then((r) => _handleInit(offset, r))
          : _handleInit(offset, initResult);
    }

    return _handleOffsetRequest(offset);
  }

  FutureOr<Option<T>> _handleInit(int offset, dynamic acc) {
    state = OffsetIteratorState(acc: acc);
    _status = OffsetIteratorStatus.active;
    return _handleOffsetRequest(offset);
  }

  FutureOr<Option<T>> _handleOffsetRequest(int offset) {
    if (offset < _offset) return valueAt(offset + 1);

    if (buffer.isNotEmpty) return _nextItem(buffer.removeFirst());
    if (state.hasMore == false) return const None();

    if (_processing) {
      return _processingFuture.then((_) => pull(offset));
    }

    _processing = true;
    try {
      final futureOr = _doProcessing(offset);
      if (futureOr is Future) {
        return (futureOr as Future<Option<T>>).whenComplete(_releaseProcessing);
      }
      _releaseProcessing();
      return futureOr;
    } catch (err) {
      _releaseProcessing();
      rethrow;
    }
  }

  FutureOr<Option<T>> _doProcessing(int offset) {
    try {
      final futureOr = _process(state.acc);

      if (futureOr is Future) {
        return (futureOr as Future<OffsetIteratorState<T>>)
            .catchError((err, stack) => OffsetIteratorState<T>(
                  acc: state.acc,
                  hasMore: state.hasMore,
                  error: err,
                  stackTrace: stack,
                ))
            .then(_handleNextState);
      }

      return _handleNextState(futureOr);
    } catch (err, stack) {
      return _handleNextState(OffsetIteratorState(
        acc: state.acc,
        hasMore: state.hasMore,
        error: err,
        stackTrace: stack,
      ));
    }
  }

  void _releaseProcessing() {
    _processing = false;
    if (_processingCompleter != null) {
      final completer = _processingCompleter!;
      _processingCompleter = null;
      completer.complete();
    }
  }

  FutureOr<Option<T>> _handleNextState(OffsetIteratorState<T> nextState) {
    state = nextState;

    if (nextState.hasMore == false || (cancelOnError && state.error != null)) {
      final cancelFuture = _cancel(true);
      if (cancelFuture is Future) {
        return cancelFuture.then((_) => _processNextState());
      }
    }

    return _processNextState();
  }

  FutureOr<Option<T>> _processNextState() {
    if (state.error != null) throw state.error;

    final chunkLength = state.chunk.length;
    if (chunkLength == 0) {
      if (state.hasMore == false) {
        _notifyListeners();
        return const None();
      }

      return _doProcessing(offset);
    } else if (chunkLength == 1) {
      return _nextItem(state.chunk.first);
    }

    buffer.addAll(state.chunk);

    return _nextItem(buffer.removeFirst());
  }

  Option<T> _nextItem(T item) {
    if (retention != 0 && _value.isSome()) {
      log.add((_value as Some).value);

      while (retention > -1 && log.length > retention) {
        log.removeFirst();
      }
    }

    final value = Some(item);
    _value = value;
    _offset++;

    _notifyListeners();

    return value;
  }

  // ==== Pull chain finishes here

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
  FutureOr<void> cancel() => _cancel(false);

  FutureOr<void> _cancel(bool force) {
    if (_status == OffsetIteratorStatus.completed) return null;
    final status = _status;
    _status = OffsetIteratorStatus.completed;

    if (status != OffsetIteratorStatus.active) return _complete();

    if (!force && _processing) {
      // ignore: void_checks
      return _processingFuture.whenComplete(_cleanupAndComplete);
    }

    return _cleanupAndComplete();
  }

  FutureOr<void> _cleanupAndComplete() {
    final futureOr = _cleanup(state.acc);
    return futureOr is Future ? futureOr.whenComplete(_complete) : _complete();
  }

  FutureOr<void> _complete() {
    state = OffsetIteratorState(
      acc: state.acc,
      chunk: state.chunk,
      hasMore: false,
      error: state.error,
      stackTrace: state.stackTrace,
    );
  }

  SeedCallback<T>? generateSeed({
    int? startOffset,
    SeedCallback<T>? override,
    SeedCallback<T>? fallback,
  }) {
    if (override != null) return override;

    _maybeSeedValue();

    if (startOffset != null) {
      return valueAt(startOffset).map(some).match(
            (v) => () => v,
            () => fallback,
          );
    }

    final fallbackOption = optionOf(fallback);
    return () => value.alt(() => fallbackOption.flatMap((f) => f()));
  }

  /// Trim the [log] to the target `offset`.
  set earliestAvailableOffset(int offset) {
    if (offset > this.offset || offset < 2) return;

    final targetLogLength = _offset - offset;
    var toRemove = log.length - targetLogLength;
    while (toRemove > 0) {
      log.removeFirst();
      toRemove--;
    }
  }

  void _notifyListeners() {
    if (_listeners.isEmpty) return;
    for (final listener in _listeners) {
      listener();
    }

    if (drained) removeAllListeners();
  }

  /// Add a `listener` that is triggered when the head [value] is updated.
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Remove a `listener`.
  void removeListener(void Function() listener) {
    _listeners.removeWhere((element) => element == listener);
  }

  /// Remove all the listeners.
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
        Option.tryCatch(() => (stream as dynamic).valueOrNull as T?)
            .flatMap(optionOf);

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
      seed: seed ?? () => valueStreamSeed,
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
          chunk: iterable,
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
