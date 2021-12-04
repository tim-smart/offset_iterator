import 'dart:async';
import 'dart:collection';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

FutureOr<OffsetIteratorState<R>> Function<R>(
  int offset,
  Option<T> item,
  FutureOr<List<R>?> chunkFuture,
) _handleItem<T>(OffsetIterator<T> parent) {
  final handleNextChunk = _handleNextChunk(parent);

  return <R>(offset, item, chunkFuture) {
    final newOffset = offset + 1;

    return chunkFuture is Future
        ? (chunkFuture as Future)
            .then((chunk) => handleNextChunk(newOffset, item, chunk))
        : handleNextChunk(newOffset, item, chunkFuture);
  };
}

FutureOr<OffsetIteratorState<R>> Function<R>(
  int newOffset,
  Option<T> item,
  List<R>? chunk,
) _handleNextChunk<T>(OffsetIterator<T> parent) => <R>(newOffset, item, chunk) {
      final hasMore = item.isSome() && chunk != null;

      return OffsetIteratorState(
        acc: newOffset,
        chunk: chunk ?? [],
        hasMore: hasMore && parent.hasMore(newOffset),
      );
    };

extension TransformExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transform<R>(
    FutureOr<List<R>?> Function(T) pred, {
    SeedCallback<R>? seed,
    int? retention,
    int? startOffset,
    int concurrency = 1,
  }) {
    if (concurrency > 1) {
      return transformConcurrent(
        pred,
        concurrency: concurrency,
        seed: seed,
        retention: retention,
        startOffset: startOffset,
      );
    }

    final parent = this;
    final handleItem = _handleItem(parent);

    return OffsetIterator(
      init: () => startOffset ?? parent.offset,
      process: (offset) {
        final earliest = parent.earliestAvailableOffset - 1;
        if (offset < earliest) offset = earliest;

        final itemFuture = parent.pull(offset);
        return itemFuture is Future
            ? (itemFuture as Future).then(
                (item) => handleItem(offset, item, item.map(pred).toNullable()))
            : handleItem(offset, itemFuture, itemFuture.map(pred).toNullable());
      },
      seed: seed,
      retention: retention ?? parent.retention,
    );
  }

  OffsetIterator<T> transformIdentical(
    FutureOr<List<T>?> Function(T) pred, {
    SeedCallback<T>? seed,
    int? retention,
    int? startOffset,
    int concurrency = 1,
  }) =>
      transform(
        pred,
        seed: generateSeed(startOffset: startOffset, override: seed),
        retention: retention,
        startOffset: startOffset,
        concurrency: concurrency,
      );
}

extension MapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> map<R>(
    R Function(T) pred, {
    int? retention,
    int? startOffset,
  }) {
    final seed = generateSeed(startOffset: startOffset);
    return transform(
      (item) => [pred(item)],
      seed: () => optionOf(seed?.call()).map(pred).toNullable(),
      retention: retention,
      startOffset: startOffset,
    );
  }
}

extension AsyncMapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> asyncMap<R>(
    Future<R> Function(T) pred, {
    SeedCallback<R>? seed,
    int? retention,
    int? startOffset,
    int concurrency = 1,
  }) =>
      transform(
        (item) => pred(item).then((v) => [v]),
        seed: seed,
        retention: retention,
        startOffset: startOffset,
        concurrency: concurrency,
      );
}

extension ScanExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> scan<R>(
    R initialValue,
    R Function(R, T) reducer, {
    SeedCallback<R>? seed,
    int? retention,
    int? startOffset,
  }) {
    R acc = initialValue;

    return transform(
      (item) {
        acc = reducer(acc, item);
        return [acc];
      },
      seed: seed,
      retention: retention,
      startOffset: startOffset,
    );
  }
}

extension TapExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> tap(
    void Function(T) effect, {
    SeedCallback<T>? seed,
    int? retention,
    int? startOffset,
  }) =>
      transformIdentical(
        (item) {
          effect(item);
          return [item];
        },
        seed: seed,
        retention: retention,
        startOffset: startOffset,
      );
}

extension DistinctExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> distinct({
    bool Function(T prev, T next)? equals,
    SeedCallback<T>? seed,
    int? retention,
    int? startOffset,
  }) {
    bool Function(T, T) eq = equals ?? (prev, next) => prev == next;
    T? prev;
    seed = generateSeed(override: seed, startOffset: startOffset);

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
      seed: () {
        prev = seed?.call();
        return prev;
      },
      retention: retention,
      startOffset: startOffset,
    );
  }
}

extension TakeWhileExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> takeWhile(
    bool Function(T item, T? prev) predicate, {
    SeedCallback<T>? seed,
    int? retention,
    int? startOffset,
  }) {
    T? prev;
    seed = generateSeed(override: seed, startOffset: startOffset);

    return transform(
      (item) {
        final more = predicate(item, prev);
        prev = item;
        return more ? [item] : null;
      },
      seed: () {
        prev = seed?.call();
        return prev;
      },
      retention: retention,
      startOffset: startOffset,
    );
  }
}

extension TakeUntilExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> takeUntil(
    bool Function(T item, T? prev) predicate, {
    SeedCallback<T>? seed,
    int? retention,
    int? startOffset,
  }) =>
      takeWhile(
        (item, prev) => !predicate(item, prev),
        seed: seed,
        retention: retention,
        startOffset: startOffset,
      );
}

extension AccumulateExtension<T> on OffsetIterator<List<T>> {
  /// Concats a stream of [List]'s together, and emits a new list each time.
  OffsetIterator<List<T>> accumulate({
    SeedCallback<List<T>>? seed,
    int? retention,
  }) =>
      scan(
        [],
        (acc, chunk) => [...acc, ...chunk],
        seed: seed,
        retention: retention,
      );
}

extension AccumulateIListExtension<T> on OffsetIterator<IList<T>> {
  OffsetIterator<IList<T>> accumulateIList({
    SeedCallback<IList<T>>? seed,
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
      seed: parent.generateSeed(),
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

    final earliest = earliestAvailableOffset - 1;
    if (offset < earliest) offset = earliest;

    while (hasMore(offset)) {
      final resultFuture = pull(offset);
      final result = resultFuture is Future ? await resultFuture : resultFuture;
      acc = result.map((v) => reducer(acc, v)).getOrElse(() => acc);
      offset = offset + 1;
    }

    return acc;
  }
}

extension ToIListExtension<T> on OffsetIterator<T> {
  Future<IList<T>> toIList({int? startOffset}) => fold(
        IList(),
        (acc, item) => acc.add(item),
        startOffset: startOffset,
      );
}

extension ToListExtension<T> on OffsetIterator<T> {
  Future<List<T>> toList({int? startOffset}) => fold([], (acc, item) {
        acc.add(item);
        return acc;
      }, startOffset: startOffset);
}

extension IntExtension on OffsetIterator<int> {
  /// Calulates the sum of all the emitted numbers.
  Future<int> sum({int? startOffset}) => fold(
        0,
        (acc, item) => acc + item,
        startOffset: startOffset,
      );
}

extension DoubleExtension on OffsetIterator<double> {
  /// Calulates the sum of all the emitted numbers.
  Future<double> sum({int? startOffset}) => fold(
        0,
        (acc, item) => acc + item,
        startOffset: startOffset,
      );
}

extension FlatMapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> flatMap<R>(
    OffsetIterator<R> Function(T item) pred, {
    int? retention,
    SeedCallback<R>? seed,
    int? startOffset,
  }) {
    final parent = this;

    return OffsetIterator(
      init: () => tuple2(startOffset ?? parent.offset, null),
      process: (acc) async {
        var offset = acc.first as int;
        var child = acc.second as OffsetIterator<R>?;

        if (child == null) {
          final earliest = parent.earliestAvailableOffset - 1;
          if (offset < earliest) offset = earliest;

          final itemFuture = parent.pull(offset);
          final item = itemFuture is Future ? await itemFuture : itemFuture;
          child = item.map(pred).toNullable();
          offset = offset + 1;
        }

        if (child != null) {
          final itemFuture = child.pull();
          final item = itemFuture is Future ? await itemFuture : itemFuture;
          final childHasMore = !child.drained;

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
    FutureOr<List<R>?> Function(T item) predicate, {
    required int concurrency,
    SeedCallback<R>? seed,
    int? retention,
    int? startOffset,
  }) {
    final parent = this;
    final queue = Queue<FutureOr<List<R>?>>();

    Future<int> fillQueue(int offset) async {
      while (queue.length < concurrency && parent.hasMore(offset)) {
        final earliest = parent.earliestAvailableOffset - 1;
        if (offset < earliest) offset = earliest;

        final itemFuture = parent.pull(offset);
        final item = itemFuture is Future ? await itemFuture : itemFuture;

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
          chunk: chunk ?? [],
          hasMore: chunk != null && queue.isNotEmpty,
        );
      },
      seed: seed,
      retention: retention ?? parent.retention,
    );
  }
}

extension RunExtension on OffsetIterator {
  FutureOr<void> run() {
    while (!drained) {
      final futureOr = pull();
      if (futureOr is Future) {
        return (futureOr as Future).then((_) => run());
      }
    }
  }
}
