import 'dart:async';
import 'dart:collection';

import 'package:fast_immutable_collections/fast_immutable_collections.dart'
    hide Tuple2;
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

class OffsetIterator<T> {
  OffsetIterator({
    required FutureOr<dynamic> Function() init,
    required Future<OffsetIteratorState<T>> Function(dynamic) process,
    void Function(dynamic)? cleanup,
    T? seed,
    this.retention = 0,
  })  : _init = init,
        _process = process,
        _cleanup = cleanup,
        _value = seed {
    _offset = value.match((_) => 1, () => 0);
    value.filter((_) => retention > 0).map(log.add);
  }

  final FutureOr<dynamic> Function() _init;
  final Future<OffsetIteratorState<T>> Function(dynamic) _process;
  final void Function(dynamic)? _cleanup;

  OffsetIteratorState<T>? state;
  Future<OffsetIteratorState<T>>? _processFuture;

  T? _value;
  Option<T> get value => optionOf(_value);

  final int retention;

  var _offset = 0;
  int get offset => _offset;

  var buffer = Queue<T>();
  final log = Queue<T>();

  bool get hasMore => (state?.hasMore ?? true) || buffer.isNotEmpty;
  bool isLastOffset(int offset) => !hasMore && offset >= _offset;

  Future<Option<OffsetIteratorItem<T>>> pull([int? currentOffset]) async {
    state ??= OffsetIteratorState(
      acc: await _init(),
      chunk: [],
      hasMore: true,
    );

    final offset = currentOffset ?? _offset;

    // Handle offset requests for previous items
    if (offset < _offset) {
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

      if (_processFuture != null) {
        await _processFuture;
        return pull(offset);
      }
      try {
        _processFuture = _process(state!.acc);
        state = await _processFuture;
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
        process: (acc) async => OffsetIteratorState(
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

extension TransformExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transform<R>(
    List<R> Function(T) pred, {
    bool Function(T)? hasMore,
    R? seed,
    int retention = 0,
  }) =>
      OffsetIterator(
        init: () => offset,
        process: (offset) async {
          final item = await pull(offset);

          return item.match(
            (item) {
              final more = hasMore != null ? hasMore(item.first) : true;

              return OffsetIteratorState(
                acc: more ? offset + 1 : offset,
                chunk: more ? pred(item.first) : [],
                hasMore: more || !isLastOffset(offset),
              );
            },
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

extension MapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> map<R>(
    R Function(T) pred, {
    int retention = 0,
  }) =>
      transform(
        (item) => [pred(item)],
        seed: value.map(pred).toNullable(),
        retention: retention,
      );
}

extension ScanExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> scan<R>(
    R initialValue,
    R Function(R, T) reducer, {
    R? seed,
    int retention = 0,
  }) {
    R acc = initialValue;

    return transform(
      (item) {
        acc = reducer(acc, item);
        return [acc];
      },
      seed: seed,
      retention: retention,
    );
  }
}

extension TapExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> tap(
    void Function(T) effect, {
    T? seed,
  }) =>
      transform((item) {
        effect(item);
        return [item];
      }, seed: seed ?? _value);
}

extension DistinctExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> distinct({
    bool Function(T prev, T next)? equals,
    T? seed,
    int retention = 0,
  }) {
    bool Function(T, T) eq = equals ?? (prev, next) => prev == next;
    T? prev = seed ?? _value;

    return transform((item) {
      if (prev == null) {
        prev = item;
        return [item];
      }

      return eq(prev!, item) ? [] : [item];
    }, seed: prev, retention: retention);
  }
}

extension TakeWhileExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> takeWhile(
    bool Function(T item, T? prev) predicate, {
    T? seed,
    int retention = 0,
  }) {
    T? prev = seed ?? _value;

    return transform(
      (item) => [item],
      hasMore: (item) => predicate(item, prev),
      seed: prev,
      retention: retention,
    );
  }
}

extension TakeUntilExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> takeUntil(
    bool Function(T item, T? prev) predicate, {
    T? seed,
    int retention = 0,
  }) {
    T? prev = seed ?? _value;

    return transform(
      (item) => [item],
      hasMore: (item) => !predicate(item, prev),
      seed: prev,
      retention: retention,
    );
  }
}

extension AccumulateExtension<T> on OffsetIterator<IList<T>> {
  OffsetIterator<IList<T>> accumulate({
    IList<T>? seed,
    int retention = 0,
  }) =>
      scan(
        IList(),
        (acc, chunk) => acc.addAll(chunk),
        seed: seed ?? _value,
        retention: retention,
      );
}

extension HandleErrorExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> handleError(
    List<T> Function(dynamic, StackTrace) onError,
  ) =>
      OffsetIterator(
        init: () => offset,
        process: (offset) async {
          List<T> chunk;
          int newOffset = offset;

          try {
            final item = await pull(offset);
            newOffset = item.map((v) => v.second).getOrElse(() => offset);
            chunk = item.match((v) => [v.first], () => []);
          } catch (err, stack) {
            chunk = onError(err, stack);
          }

          return OffsetIteratorState(
            acc: newOffset,
            chunk: chunk,
            hasMore: !isLastOffset(newOffset),
          );
        },
      );
}
