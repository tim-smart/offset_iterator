import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:offset_iterator/offset_iterator.dart';

extension TransformExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transform<R>(
    FutureOr<List<R>> Function(T) pred, {
    bool Function(T)? hasMore,
    R? seed,
    int retention = 0,
  }) =>
      OffsetIterator(
        init: () => offset,
        process: (offset) async {
          final item = await pull(offset);

          return item.match(
            (item) async {
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
                acc: more ? offset + 1 : offset,
                chunk: chunk,
                hasMore: more && this.hasMore(offset),
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
