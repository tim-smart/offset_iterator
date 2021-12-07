import 'dart:async';
import 'dart:collection';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

extension StartFromExtension<T> on OffsetIterator<T> {
  /// Pull from the [OffsetIterator] from the specified offset.
  OffsetIterator<T> startFrom(
    int? offset, {
    String name = 'startFrom',
    bool bubbleCancellation = true,
  }) {
    final parent = this;

    return OffsetIterator(
      name: toStringWithChild(name),
      init: () => offset ?? parent.offset,
      process: (offset) {
        final earliest = parent.earliestAvailableOffset - 1;
        if (offset < earliest) offset = earliest;

        final futureOr = parent.pull(offset);

        if (futureOr is! Future) {
          return OffsetIteratorState(
            acc: offset + 1,
            chunk: futureOr is Some ? [(futureOr as Some).value] : const [],
            hasMore: parent.hasMore(offset + 1),
          );
        }

        return (futureOr as Future<Option<T>>)
            .then((item) => OffsetIteratorState(
                  acc: offset + 1,
                  chunk: item is Some ? [(item as Some).value] : const [],
                  hasMore: parent.hasMore(offset + 1),
                ));
      },
      cleanup: parent.generateCleanup(bubbleCancellation: bubbleCancellation),
      seed: parent.generateSeed(startOffset: offset),
    );
  }

  /// Don't always pull the latest item from the [OffsetIterator], but instead
  /// book-keep the last processed offset to ensure items aren't missed.
  OffsetIterator<T> withTracking() => startFrom(null);
}

FutureOr<OffsetIteratorState<R>> Function<R>(
  Option<T> item,
  FutureOr<List<R>?> chunkFuture,
) _handleItem<T>(OffsetIterator<T> parent) {
  final handleNextChunk = _handleNextChunk(parent);

  return <R>(item, chunkFuture) => chunkFuture is Future
      ? (chunkFuture as Future).then((chunk) => handleNextChunk(item, chunk))
      : handleNextChunk(item, chunkFuture);
}

FutureOr<OffsetIteratorState<R>> Function<R>(
  Option<T> item,
  List<R>? chunk,
) _handleNextChunk<T>(OffsetIterator<T> parent) => <R>(item, chunk) {
      final hasMore = item.isSome() && chunk != null;

      return OffsetIteratorState(
        chunk: chunk ?? [],
        hasMore: hasMore && parent.hasMore(),
      );
    };

extension TransformExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transform<R>(
    FutureOr<List<R>?> Function(T) pred, {
    String name = 'transform',
    SeedCallback<R>? seed,
    int retention = 0,
    int concurrency = 1,
    bool bubbleCancellation = true,
  }) {
    if (concurrency > 1) {
      return transformConcurrent(
        pred,
        concurrency: concurrency,
        seed: seed,
        retention: retention,
      );
    }

    final parent = this;
    final handleItem = _handleItem(parent);

    return OffsetIterator(
      name: toStringWithChild(name),
      process: (_) {
        final itemFuture = parent.pull();
        return itemFuture is Future
            ? (itemFuture as Future)
                .then((item) => handleItem(item, item.map(pred).toNullable()))
            : handleItem(itemFuture, itemFuture.map(pred).toNullable());
      },
      cleanup: parent.generateCleanup(bubbleCancellation: bubbleCancellation),
      seed: seed,
      retention: retention,
    );
  }

  OffsetIterator<T> transformIdentical(
    FutureOr<List<T>?> Function(T) pred, {
    String name = 'transformIdentical',
    SeedCallback<T>? seed,
    int retention = 0,
    int concurrency = 1,
    bool bubbleCancellation = true,
  }) =>
      transform(
        pred,
        name: name,
        seed: generateSeed(override: seed),
        retention: retention,
        concurrency: concurrency,
        bubbleCancellation: bubbleCancellation,
      );
}

extension MapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> map<R>(
    R Function(T) pred, {
    String name = 'map',
    int retention = 0,
    bool bubbleCancellation = true,
  }) {
    final seed = generateSeed();

    return transform(
      (item) => [pred(item)],
      seed: () => (seed?.call() ?? const None()).map(pred),
      name: name,
      retention: retention,
      bubbleCancellation: bubbleCancellation,
    );
  }
}

extension AsyncMapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> asyncMap<R>(
    Future<R> Function(T) pred, {
    String name = 'asyncMap',
    SeedCallback<R>? seed,
    int retention = 0,
    int concurrency = 1,
    bool bubbleCancellation = true,
  }) =>
      transform(
        (item) => pred(item).then((v) => [v]),
        name: name,
        seed: seed,
        retention: retention,
        concurrency: concurrency,
        bubbleCancellation: bubbleCancellation,
      );
}

extension ScanExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> scan<R>(
    R initialValue,
    R Function(R, T) reducer, {
    String name = 'scan',
    SeedCallback<R>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) {
    R acc = initialValue;

    return transform(
      (item) {
        acc = reducer(acc, item);
        return [acc];
      },
      name: name,
      seed: seed,
      retention: retention,
      bubbleCancellation: bubbleCancellation,
    );
  }
}

extension BufferExtension<T> on OffsetIterator<T> {
  /// Converts the parent items into [List]'s of the given size.
  OffsetIterator<List<T>> bufferCount(
    int count, {
    String name = 'bufferCount',
    SeedCallback<T>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) {
    final parent = this;

    return OffsetIterator(
      name: toStringWithChild(name),
      process: (_) async {
        var buffer = <T>[];
        var remaining = count;

        while (remaining > 0) {
          final futureOr = parent.pull();
          final item = futureOr is Future ? await futureOr : futureOr;

          item.map((item) {
            buffer.add(item);
            remaining--;
          });

          if (parent.drained) break;
        }

        return OffsetIteratorState(
          chunk: [buffer],
          hasMore: parent.hasMore(),
        );
      },
      cleanup: parent.generateCleanup(bubbleCancellation: bubbleCancellation),
    );
  }
}

extension TapExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> tap(
    void Function(T) effect, {
    String name = 'tap',
    SeedCallback<T>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) =>
      transformIdentical(
        (item) {
          effect(item);
          return [item];
        },
        name: name,
        seed: seed,
        retention: retention,
        bubbleCancellation: bubbleCancellation,
      );
}

extension DistinctExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> distinct({
    bool Function(T prev, T next)? equals,
    String name = 'distinct',
    SeedCallback<T>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) {
    bool Function(T, T) eq = equals ?? (prev, next) => prev == next;
    Option<T> prev = const None();
    seed = generateSeed(override: seed);

    return transform(
      (item) {
        if (prev.isNone()) {
          prev = Some(item);
          return [item];
        }

        final duplicate = eq((prev as Some).value, item);
        prev = Some(item);
        return duplicate ? [] : [item];
      },
      seed: () {
        if (seed != null) prev = seed();
        return prev;
      },
      name: name,
      retention: retention,
      bubbleCancellation: bubbleCancellation,
    );
  }
}

extension TakeWhileExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> takeWhile(
    bool Function(T item, Option<T> prev) predicate, {
    String name = 'takeWhile',
    SeedCallback<T>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) {
    Option<T> prev = const None();
    seed = generateSeed(override: seed);

    return transform(
      (item) {
        final more = predicate(item, prev);
        prev = Some(item);
        return more ? [item] : null;
      },
      seed: () {
        if (seed != null) prev = seed();
        return prev;
      },
      name: name,
      retention: retention,
      bubbleCancellation: bubbleCancellation,
    );
  }
}

extension TakeUntilExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> takeUntil(
    bool Function(T item, Option<T> prev) predicate, {
    String name = 'takeUntil',
    SeedCallback<T>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) =>
      takeWhile(
        (item, prev) => !predicate(item, prev),
        name: name,
        seed: seed,
        retention: retention,
        bubbleCancellation: bubbleCancellation,
      );
}

extension AccumulateExtension<T> on OffsetIterator<List<T>> {
  /// Concats a stream of [List]'s together, and emits a new list each time.
  OffsetIterator<List<T>> accumulate({
    String name = 'accumulate',
    SeedCallback<List<T>>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) =>
      scan(
        [],
        (acc, chunk) => [...acc, ...chunk],
        name: name,
        seed: seed,
        retention: retention,
        bubbleCancellation: bubbleCancellation,
      );
}

extension AccumulateIListExtension<T> on OffsetIterator<IList<T>> {
  OffsetIterator<IList<T>> accumulateIList({
    String name = 'accumulateIList',
    SeedCallback<IList<T>>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) =>
      scan(
        IList(),
        (acc, chunk) => acc.addAll(chunk),
        name: name,
        seed: seed,
        retention: retention,
        bubbleCancellation: bubbleCancellation,
      );
}

extension HandleErrorExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> handleError(
    FutureOr<bool?> Function(dynamic error, StackTrace stack) onError, {
    String name = 'handleError',
    int? retention,
    int maxRetries = 5,
    bool bubbleCancellation = true,
  }) {
    final parent = this;

    return OffsetIterator(
      name: toStringWithChild(name),
      seed: parent.generateSeed(),
      retention: retention ?? parent.retention,
      init: () => maxRetries,
      process: (remainingRetries) async {
        List<T>? chunk;

        try {
          final item = await parent.pull();
          remainingRetries = maxRetries;
          chunk = item.match((v) => [v], () => []);
        } catch (err, stack) {
          final retry = (await onError(err, stack)) ?? false;
          remainingRetries = retry ? remainingRetries - 1 : 0;
        }

        return OffsetIteratorState(
          acc: remainingRetries,
          chunk: chunk ?? [],
          hasMore: remainingRetries == 0 ? false : !parent.drained,
        );
      },
      cleanup: parent.generateCleanup(bubbleCancellation: bubbleCancellation),
    );
  }
}

extension PrefetchExtension<T> on OffsetIterator<T> {
  /// Eagerly load the next item in the [OffsetIterator].
  ///
  /// This ensures the the parent [OffsetIterator] is processing the next item
  /// before the child needs it.
  OffsetIterator<T> prefetch({
    String name = 'prefetch',
    bool bubbleCancellation = true,
  }) {
    final parent = this;

    return OffsetIterator(
      name: toStringWithChild(name),
      seed: parent.generateSeed(),
      init: () => parent.offset,
      process: (offset) async {
        final futureOr = parent.pull(offset);
        final item = futureOr is Future ? await futureOr : futureOr;

        final newOffset = offset + 1;
        final hasMore = parent.hasMore(newOffset);
        if (hasMore) parent.pull(newOffset);

        return OffsetIteratorState(
          acc: newOffset,
          chunk: item is Some ? [(item as Some).value] : [],
          hasMore: hasMore,
        );
      },
      cleanup: parent.generateCleanup(bubbleCancellation: bubbleCancellation),
    );
  }
}

extension FlatMapExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> flatMap<R>(
    OffsetIterator<R> Function(T item) pred, {
    String name = 'flatMap',
    int retention = 0,
    SeedCallback<R>? seed,
    bool bubbleCancellation = true,
  }) {
    final parent = this;

    return OffsetIterator(
      name: toStringWithChild(name),
      process: (acc) async {
        var child = acc as OffsetIterator<R>?;

        if (child == null) {
          final itemFuture = parent.pull();
          final item = itemFuture is Future ? await itemFuture : itemFuture;
          child = item.map(pred).toNullable();
        }

        if (child != null) {
          final itemFuture = child.pull();
          final item = itemFuture is Future ? await itemFuture : itemFuture;
          final childHasMore = child.hasMore();

          return OffsetIteratorState(
            acc: childHasMore ? child : null,
            chunk: item.match((v) => [v], () => []),
            hasMore: childHasMore || parent.hasMore(),
          );
        }

        return OffsetIteratorState(
          acc: offset,
          hasMore: parent.hasMore(),
        );
      },
      cleanup: parent.generateCleanup(bubbleCancellation: bubbleCancellation),
      seed: seed,
      retention: retention,
    );
  }
}

extension TransformConcurrentExtension<T> on OffsetIterator<T> {
  OffsetIterator<R> transformConcurrent<R>(
    FutureOr<List<R>?> Function(T item) predicate, {
    String name = 'transformConcurrent',
    required int concurrency,
    SeedCallback<R>? seed,
    int retention = 0,
    bool bubbleCancellation = true,
  }) {
    final parent = this;
    final queue = Queue<FutureOr<List<R>?>>();

    Future<void> fillQueue() async {
      while (queue.length < concurrency && parent.hasMore()) {
        final itemFuture = parent.pull();
        final item = itemFuture is Future ? await itemFuture : itemFuture;
        item.map((item) => queue.add(predicate(item)));
      }
    }

    return OffsetIterator(
      name: toStringWithChild(name),
      process: (_) async {
        if (queue.isEmpty) {
          await fillQueue();
        }

        final chunk = await queue.removeFirst();
        await fillQueue();

        return OffsetIteratorState(
          chunk: chunk ?? [],
          hasMore: chunk != null && queue.isNotEmpty,
        );
      },
      cleanup: parent.generateCleanup(bubbleCancellation: bubbleCancellation),
      seed: seed,
      retention: retention,
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

extension ListenExtension<T> on OffsetIterator<T> {
  /// Continually pull data, and get notified on every value change.
  /// Returns a [void Function()] that when called, cancel's the subscription.
  void Function() listen(
    void Function(T item) onData, {
    void Function(dynamic, StackTrace? stack)? onError,
    void Function()? onDone,
  }) {
    var cancelled = false;

    void handleData(Option<T> item) {
      if (item is Some) {
        onData((item as Some).value);
      }
    }

    FutureOr<void> doPull() {
      while (!cancelled && !drained) {
        try {
          final futureOr = pull();

          if (futureOr is Future) {
            return (futureOr as Future<Option<T>>).then((item) {
              handleData(item);
              return doPull();
            }, onError: (err, stack) {
              onError?.call(err, stack);
              return doPull();
            });
          }

          handleData(futureOr);
        } catch (err, stack) {
          onError?.call(err, stack);
        }
      }

      if (!cancelled) onDone?.call();
    }

    Future.microtask(doPull);

    return () => cancelled = true;
  }
}

extension FoldExtension<T> on OffsetIterator<T> {
  Future<R> fold<R>(R initialValue, R Function(R acc, T item) reducer) async {
    var acc = initialValue;

    while (!drained) {
      final resultFuture = pull();
      final result = resultFuture is Future ? await resultFuture : resultFuture;
      acc = result.map((v) => reducer(acc, v)).getOrElse(() => acc);
    }

    return acc;
  }
}

extension ToIListExtension<T> on OffsetIterator<T> {
  Future<IList<T>> toIList() => fold(
        IList(),
        (acc, item) => acc.add(item),
      );
}

extension ToListExtension<T> on OffsetIterator<T> {
  Future<List<T>> toList() => fold([], (acc, item) {
        acc.add(item);
        return acc;
      });
}

extension IntExtension on OffsetIterator<int> {
  /// Calculates the sum of all the emitted numbers.
  Future<int> sum() => fold(0, (acc, item) => acc + item);
}

extension DoubleExtension on OffsetIterator<double> {
  /// Calculates the sum of all the emitted numbers.
  Future<double> sum() => fold(0, (acc, item) => acc + item);
}
