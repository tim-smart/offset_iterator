import 'dart:async';
import 'dart:collection';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

extension TransformExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transform<R>(
    FutureOr<List<R>> Function(T) pred, {
    bool Function(T)? hasMore,
    R? seed,
    int? retention,
    int? startOffset,
  }) {
    final parent = this;

    return OffsetIterator(
      init: () => startOffset ?? parent.offset,
      process: (offset) async {
        final item = await parent.pull(offset);
        final newOffset = offset + 1;

        return item.match(
          (item) {
            final more = hasMore != null ? hasMore(item) : true;

            final chunk = more ? pred(item) : <R>[];

            if (chunk is Future) {
              return (chunk as Future<List<R>>)
                  .then((chunk) => OffsetIteratorState(
                        acc: newOffset,
                        chunk: chunk,
                        hasMore: more && parent.hasMore(newOffset),
                      ));
            }

            return OffsetIteratorState(
              acc: newOffset,
              chunk: chunk,
              hasMore: more && parent.hasMore(newOffset),
            );
          },
          () => OffsetIteratorState(
            acc: newOffset,
            chunk: [],
            hasMore: parent.hasMore(newOffset),
          ),
        );
      },
      seed: seed,
      retention: retention ?? parent.retention,
    );
  }
}

extension MapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> map<R>(
    R Function(T) pred, {
    int? retention,
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
    int? retention,
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
    int? retention,
  }) {
    R acc = initialValue;

    return transform(
      (item) {
        acc = reducer(acc, item);
        return [acc];
      },
      seed: seed ?? initialValue,
      retention: retention,
    );
  }
}

extension TapExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> tap(
    void Function(T) effect, {
    T? seed,
    int? retention,
  }) =>
      transform(
        (item) {
          effect(item);
          return [item];
        },
        seed: seed ?? valueOrNull,
        retention: retention,
      );
}

extension DistinctExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> distinct({
    bool Function(T prev, T next)? equals,
    T? seed,
    int? retention,
  }) {
    bool Function(T, T) eq = equals ?? (prev, next) => prev == next;
    T? prev = seed ?? valueOrNull;

    return transform(
      (item) {
        if (prev == null) {
          prev = item;
          return [item];
        }

        final duplicate = eq(prev!, item);
        prev = item;
        return duplicate ? [] : [item];
      },
      seed: prev,
      retention: retention,
    );
  }
}

extension TakeWhileExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> takeWhile(
    bool Function(T item, T? prev) predicate, {
    T? seed,
    int? retention,
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
    int? retention,
  }) =>
      takeWhile(
        (item, prev) => !predicate(item, prev),
        seed: seed ?? valueOrNull,
        retention: retention,
      );
}

extension AccumulateExtension<T> on OffsetIterator<IList<T>> {
  OffsetIterator<IList<T>> accumulate({
    IList<T>? seed,
    int? retention,
  }) =>
      scan(
        IList(),
        (acc, chunk) => acc.addAll(chunk),
        seed: seed,
        retention: retention,
      );
}

extension HandleErrorExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> handleError(
    FutureOr<bool?> Function(dynamic error, StackTrace stack) onError, {
    int? retention,
    int maxRetries = 5,
  }) {
    final parent = this;

    return OffsetIterator(
      seed: parent.valueOrNull,
      retention: retention ?? parent.retention,
      init: () => tuple2(parent.offset, maxRetries),
      process: (acc) async {
        final offset = acc.first as int;
        var remainingRetries = acc.second as int;

        List<T>? chunk;
        int newOffset = offset;

        try {
          final item = await parent.pull(offset);
          newOffset = offset + 1;
          remainingRetries = maxRetries;
          chunk = item.match((v) => [v], () => []);
        } catch (err, stack) {
          final retry = (await onError(err, stack)) ?? false;
          remainingRetries = retry ? remainingRetries - 1 : 0;
        }

        return OffsetIteratorState(
          acc: tuple2(newOffset, remainingRetries),
          chunk: chunk ?? [],
          hasMore: remainingRetries == 0 ? false : parent.hasMore(newOffset),
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

    while (hasMore(offset)) {
      final result = await pull(offset);
      acc = result.map((v) => reducer(acc, v)).getOrElse(() => acc);
      offset = offset + 1;
    }

    return acc;
  }
}

extension ToIListExtension<T> on OffsetIterator<T> {
  Future<IList<T>> toIList({int? startOffset}) =>
      fold(IList(), (acc, item) => acc.add(item), startOffset: startOffset);
}

extension ToListExtension<T> on OffsetIterator<T> {
  Future<List<T>> toList({int? startOffset}) => fold([], (acc, item) {
        acc.add(item);
        return acc;
      }, startOffset: startOffset);
}

extension FlatMapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> flatMap<R>(
    OffsetIterator<R> Function(T item) pred, {
    int? retention,
    R? seed,
    int? startOffset,
  }) {
    final parent = this;

    return OffsetIterator(
      init: () => tuple2(startOffset ?? parent.offset, null),
      process: (acc) async {
        var offset = acc.first as int;
        var child = acc.second as OffsetIterator<R>?;

        if (child == null) {
          final item = await parent.pull(offset);
          child = item.map(pred).toNullable();
          offset = offset + 1;
        }

        if (child != null) {
          final item = await child.pull();
          final childHasMore = child.hasMore();

          return OffsetIteratorState(
            acc: tuple2(offset, childHasMore ? child : null),
            chunk: item.match((v) => [v], () => []),
            hasMore: childHasMore || parent.hasMore(offset),
          );
        }

        return OffsetIteratorState(
          acc: tuple2(offset, null),
          chunk: [],
          hasMore: parent.hasMore(offset),
        );
      },
      seed: seed,
      retention: retention ?? parent.retention,
    );
  }
}

extension TransformConcurrentExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transformConcurrent<R>(
    FutureOr<List<R>> Function(T item) predicate, {
    required int concurrency,
    R? seed,
    int? retention,
    int? startOffset,
  }) {
    final parent = this;
    final queue = Queue<FutureOr<List<R>>>();

    Future<int> fillQueue(int offset) async {
      while (queue.length < concurrency && parent.hasMore(offset)) {
        final item = await parent.pull(offset);

        item.map((item) {
          queue.add(predicate(item));
        });

        offset = offset + 1;
      }

      return offset;
    }

    return OffsetIterator(
      init: () => startOffset ?? parent.offset,
      process: (offset) async {
        if (queue.isEmpty) {
          offset = await fillQueue(offset);
        }

        final chunk = await queue.removeFirst();
        offset = await fillQueue(offset);

        return OffsetIteratorState(
          acc: offset,
          chunk: chunk,
          hasMore: queue.isNotEmpty,
        );
      },
      seed: seed,
      retention: retention ?? parent.retention,
    );
  }
}
