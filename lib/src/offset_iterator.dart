import 'dart:async';
import 'dart:collection';

import 'package:fast_immutable_collections/fast_immutable_collections.dart'
    hide Tuple2;
import 'package:fpdart/fpdart.dart';
import 'package:rxdart/rxdart.dart';

class OffsetIteratorState<T, Acc> {
  const OffsetIteratorState({
    required this.acc,
    required this.chunk,
    required this.hasMore,
  });

  final Acc acc;
  final List<T> chunk;
  final bool hasMore;
}

typedef OffsetIteratorItem<T> = Tuple2<T, int>;

class OffsetIterator<T, Acc> {
  OffsetIterator({
    required FutureOr<Acc> Function() init,
    required Future<OffsetIteratorState<T, Acc>> Function(Acc) process,
    void Function(Acc)? cleanup,
    T? seed,
    this.retention = 0,
  })  : _init = init,
        _process = process,
        _cleanup = cleanup,
        _value = seed {
    _offset = value.match((_) => 1, () => 0);
    value.filter((_) => retention > 0).map(log.add);
  }

  final FutureOr<Acc> Function() _init;
  final Future<OffsetIteratorState<T, Acc>> Function(Acc) _process;
  final void Function(Acc)? _cleanup;

  OffsetIteratorState<T, Acc>? state;
  var _processing = false;

  T? _value;
  Option<T> get value => optionOf(_value);

  final int retention;

  var _offset = 0;
  int get offset => _offset;

  var buffer = Queue<T>();
  final log = Queue<T>();

  bool get hasMore => (state?.hasMore ?? true) || buffer.isNotEmpty;
  bool isLastOffset(int offset) => !hasMore && offset >= _offset;

  Future<Option<OffsetIteratorItem<T>>> pull([int? offset]) async {
    state ??= OffsetIteratorState(
      acc: await _init(),
      chunk: [],
      hasMore: true,
    );

    // Handle offset requests for previous items
    if (offset != null && offset < _offset) {
      if (retention == 0 || offset == _offset - 1 || log.isEmpty) {
        return value.map((v) => tuple2(v, _offset));
      }

      final reverseIndex = _offset - offset;
      final logLength = log.length;

      if (reverseIndex > logLength) {
        return some(tuple2(log.first, _offset - logLength + 1));
      }

      final index = logLength - reverseIndex;
      return some(tuple2(log.elementAt(index), offset + 1));
    }

    // Maybe fetch next chunk and re-fill buffer
    if (buffer.isEmpty) {
      if (!state!.hasMore) {
        return const None();
      }

      if (_processing) return const None();
      _processing = true;
      try {
        state = await _process(state!.acc);
      } finally {
        _processing = false;
      }

      buffer = Queue.from(state!.chunk);

      if (!state!.hasMore && _cleanup != null) {
        _cleanup!(state!.acc);
      }
    }

    // Emit next item
    if (buffer.isNotEmpty) {
      final item = buffer.removeFirst();
      _value = item;
      _offset = _offset + 1;

      if (retention > 0) {
        log.add(item);

        while (log.length > retention) {
          log.removeFirst();
        }
      }

      return Some(tuple2(item, _offset));
    }

    return const None();
  }

  void cancel() {
    if (state == null) return;

    if (_cleanup != null) {
      _cleanup!(state!.acc);
    }

    buffer = Queue();
    state = OffsetIteratorState(
      acc: state!.acc,
      chunk: [],
      hasMore: false,
    );
  }

  static OffsetIterator<T, StreamIterator<T>> fromStream<T>(
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
}

extension TransformExtension<T> on OffsetIterator<T, dynamic> {
  OffsetIterator<R, int> transform<R>(
    List<R> Function(T) pred, {
    R? seed,
    int retention = 0,
  }) {
    return OffsetIterator(
      init: () => offset,
      process: (offset) async {
        final item = await pull(offset);

        return item.match(
          (item) => OffsetIteratorState(
            acc: offset + 1,
            chunk: pred(item.first),
            hasMore: !isLastOffset(offset),
          ),
          () => OffsetIteratorState(
            acc: offset,
            chunk: [],
            hasMore: state!.hasMore,
          ),
        );
      },
      seed: seed,
      retention: retention,
    );
  }
}

extension MapExtension<T> on OffsetIterator<T, dynamic> {
  OffsetIterator<R, int> map<R>(
    R Function(T) pred, {
    int retention = 0,
  }) =>
      transform(
        (item) => [pred(item)],
        seed: value.map(pred).toNullable(),
        retention: retention,
      );
}

extension ScanExtension<T> on OffsetIterator<T, dynamic> {
  OffsetIterator<R, int> scan<R>(
    R initialValue,
    R Function(R, T) reducer, {
    R? seed,
  }) {
    R acc = initialValue;

    return transform(
      (item) {
        acc = reducer(acc, item);
        return [acc];
      },
      seed: seed,
    );
  }
}

extension TapExtension<T> on OffsetIterator<T, dynamic> {
  OffsetIterator<T, int> tap(
    void Function(T) effect, {
    T? seed,
  }) =>
      transform((item) {
        effect(item);
        return [item];
      }, seed: seed ?? _value);
}

extension DistinctExtension<T> on OffsetIterator<T, dynamic> {
  OffsetIterator<T, int> distinct(
    bool Function(T prev, T next)? equals, {
    T? seed,
  }) {
    bool Function(T, T) eq = equals ?? (prev, next) => prev == next;
    T? prev = seed ?? _value;

    return transform((item) {
      if (prev == null) {
        prev = item;
        return [item];
      }

      return eq(prev!, item) ? [] : [item];
    }, seed: prev);
  }
}

extension AccumulateExtension<T> on OffsetIterator<IList<T>, dynamic> {
  OffsetIterator<IList<T>, int> accumulate({IList<T>? seed}) => scan(
        IList(),
        (acc, chunk) => acc.addAll(chunk),
        seed: seed ?? _value,
      );
}
