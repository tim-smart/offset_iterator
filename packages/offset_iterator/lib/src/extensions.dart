import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

extension TransformExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transform<R>(
    FutureOr<List<R>> Function(T) pred, {
    bool Function(T)? hasMore,
    R? seed,
    int retention = 0,
  }) {
    final parent = this;

    return OffsetIterator(
      init: () => offset,
      process: (offset) async {
        final item = await parent.pull(offset);

        return item.match(
          (item) async {
            final newOffset = offset + 1;
            final more = hasMore != null ? hasMore(item.first) : true;

            var chunk = <R>[];
            if (more) {
              final result = pred(item.first);
              if (result is Future) {
                chunk = await result;
              } else {
                chunk = result;
              }
            }

            return OffsetIteratorState(
              acc: newOffset,
              chunk: chunk,
              hasMore: more && parent.hasMore(newOffset),
            );
          },
          () => OffsetIteratorState(
            acc: offset,
            chunk: [],
            hasMore: parent.hasMore(offset),
          ),
        );
      },
      seed: seed,
      retention: retention,
    );
  }
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

extension AsyncMapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> asyncMap<R>(
    Future<R> Function(T) pred, {
    int retention = 0,
    R? seed,
  }) =>
      transform(
        (item) => pred(item).then((v) => [v]),
        retention: retention,
        seed: seed,
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
      }, seed: seed ?? valueOrNull);
}

extension DistinctExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> distinct({
    bool Function(T prev, T next)? equals,
    T? seed,
    int retention = 0,
  }) {
    bool Function(T, T) eq = equals ?? (prev, next) => prev == next;
    T? prev = seed ?? valueOrNull;

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
    T? prev = seed ?? valueOrNull;

    return transform(
      (item) => [item],
      hasMore: (item) {
        final more = predicate(item, prev);
        prev = item;
        return more;
      },
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
  }) =>
      takeWhile(
        (item, prev) => !predicate(item, prev),
        seed: seed,
        retention: retention,
      );
}

extension AccumulateExtension<T> on OffsetIterator<IList<T>> {
  OffsetIterator<IList<T>> accumulate({
    IList<T>? seed,
    int retention = 0,
  }) =>
      scan(
        IList(),
        (acc, chunk) => acc.addAll(chunk),
        seed: seed ?? valueOrNull,
        retention: retention,
      );
}

extension HandleErrorExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> handleError(
    List<T> Function(dynamic, StackTrace) onError,
  ) {
    final parent = this;

    return OffsetIterator(
      init: () => parent.offset,
      process: (offset) async {
        List<T> chunk;
        int newOffset = offset;

        try {
          final item = await parent.pull(offset);
          newOffset = item.map((v) => v.second).getOrElse(() => offset);
          chunk = item.match((v) => [v.first], () => []);
        } catch (err, stack) {
          chunk = onError(err, stack);
        }

        return OffsetIteratorState(
          acc: newOffset,
          chunk: chunk,
          hasMore: parent.hasMore(newOffset),
        );
      },
    );
  }
}

extension FoldExtension<T> on OffsetIterator<T> {
  Future<R> fold<R>(
    R initialValue,
    R Function(R acc, T item) reducer, {
    int? startOffset,
  }) async {
    var acc = initialValue;
    var offset = startOffset ?? this.offset;

    while (true) {
      final result = await pull(offset);
      if (result.isNone()) break;

      final resultSome = result as Some<OffsetIteratorItem<T>>;
      acc = reducer(acc, resultSome.value.first);
      offset = resultSome.value.second;
    }

    return acc;
  }
}

extension ToIListExtension<T> on OffsetIterator<T> {
  Future<IList<T>> toIList({
    int? startOffset,
  }) =>
      fold(IList(), (acc, item) => acc.add(item), startOffset: startOffset);
}

extension ToListExtension<T> on OffsetIterator<T> {
  Future<List<T>> toList({
    int? startOffset,
  }) =>
      fold([], (acc, item) {
        acc.add(item);
        return acc;
      }, startOffset: startOffset);
}
