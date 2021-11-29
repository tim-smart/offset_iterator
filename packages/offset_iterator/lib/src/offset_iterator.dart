import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:rxdart/rxdart.dart';

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

typedef OffsetIteratorItem<T> = Tuple2<T, int>;

typedef InitCallback = FutureOr<dynamic> Function();
typedef ProcessCallback<T> = FutureOr<OffsetIteratorState<T>> Function(dynamic);
typedef CleanupCallback = void Function(dynamic);

class OffsetIterator<T> {
  OffsetIterator({
    required InitCallback init,
    required ProcessCallback<T> process,
    CleanupCallback? cleanup,
    T? seed,
    this.retention = 0,
  })  : _init = init,
        _process = process,
        _cleanup = cleanup,
        _value = seed {
    _offset = value.match((_) => 1, () => 0);
    value.filter((_) => retention > 0).map(log.add);
  }

  final InitCallback _init;
  final ProcessCallback<T> _process;
  final CleanupCallback? _cleanup;

  OffsetIteratorState<T>? state;
  FutureOr<OffsetIteratorState<T>>? _processFuture;

  T? _value;
  T? get valueOrNull => _value;
  Option<T> get value => optionOf(_value);

  final int retention;

  var _offset = 0;
  int get offset => _offset;

  var buffer = Queue<T>();
  final log = Queue<T>();

  bool hasMore([int? offset]) {
    offset ??= _offset;
    return offset < _offset ||
        offset < (_offset + buffer.length) ||
        (state?.hasMore ?? true);
  }

  bool isLastOffset(int offset) => !hasMore(offset);

  Future<Option<OffsetIteratorItem<T>>> pull([int? currentOffset]) async {
    if (state == null) {
      final initResult = _init();
      dynamic acc;

      if (initResult is Future) {
        acc = await initResult;
      } else {
        acc = initResult;
      }

      state = OffsetIteratorState(
        acc: acc,
        chunk: [],
        hasMore: true,
      );
    }

    final offset = currentOffset ?? _offset;

    // Handle offset requests for previous items
    if (offset < _offset) {
      if (retention == 0 || offset == _offset - 1 || log.isEmpty) {
        return value.map((v) => tuple2(v, _offset));
      }

      final reverseIndex = _offset - offset - 1;
      final logLength = log.length;

      if (reverseIndex > logLength) {
        return some(tuple2(log.first, _offset - logLength));
      }

      final index = logLength - reverseIndex;
      return some(tuple2(log.elementAt(index), offset + 1));
    }

    // Maybe fetch next chunk and re-fill buffer
    if (buffer.isEmpty) {
      if (!state!.hasMore) {
        return const None();
      }

      if (_processFuture != null) {
        await _processFuture;
        return pull(offset);
      }

      try {
        _processFuture = _process(state!.acc);

        if (_processFuture is Future) {
          final nextItem = await _processFuture;
          if (!state!.hasMore) return const None();
          state = nextItem;
        } else {
          state = _processFuture as OffsetIteratorState<T>;
        }
      } finally {
        _processFuture = null;
      }

      buffer = Queue.from(state!.chunk);

      if (!state!.hasMore && _cleanup != null) {
        _cleanup!(state!.acc);
      }
    }

    // Emit next item
    if (buffer.isNotEmpty) {
      final item = buffer.removeFirst();

      if (retention > 0 && _value != null) {
        log.add(_value!);

        while (log.length > retention) {
          log.removeFirst();
        }
      }

      _value = item;
      _offset = _offset + 1;

      return Some(tuple2(item, _offset));
    }

    return const None();
  }

  void cancel() {
    if (state == null) return;

    if (_cleanup != null) {
      _cleanup!(state!.acc);
    }

    state = OffsetIteratorState(
      acc: state!.acc,
      chunk: [],
      hasMore: false,
    );
  }

  static OffsetIterator<T> fromStream<T>(
    Stream<T> stream, {
    int retention = 0,
    T? seed,
  }) =>
      OffsetIterator(
        init: () => StreamIterator(stream),
        process: (i) async {
          final available = await i.moveNext();

          return OffsetIteratorState(
            acc: i,
            chunk: available ? [i.current] : [],
            hasMore: available,
          );
        },
        cleanup: (i) => i.cancel(),
        seed: seed ?? (stream is ValueStream<T> ? stream.valueOrNull : null),
        retention: retention,
      );

  static OffsetIterator<T> fromIterable<T>(
    Iterable<T> iterable, {
    int retention = 0,
    T? seed,
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

  static OffsetIterator<T> fromValue<T>(T value, {T? seed}) =>
      fromIterable([value], seed: seed);
}
