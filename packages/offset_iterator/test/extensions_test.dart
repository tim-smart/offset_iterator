import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:test/test.dart';

void main() {
  group('transform', () {
    test('returns a new iterator that emits transformed items', () async {
      final i = OffsetIterator.fromIterable([1, 2]).transform((i) => [
            i,
            i + 100,
            i + 1000,
          ]);

      expect(i.value, none());
      expect(i.offset, 0);
      expect(await i.toList(), equals([1, 101, 1001, 2, 102, 1002]));
    });

    test('works with futures', () async {
      final i = OffsetIterator.fromIterable([1, 2]).transform((i) async {
        await Future.delayed(const Duration(microseconds: 10));
        return [
          i,
          i + 100,
          i + 1000,
        ];
      });

      expect(await i.toList(), equals([1, 101, 1001, 2, 102, 1002]));
    });

    test('returning null allows transform to exit early', () async {
      final i =
          OffsetIterator.fromIterable([1, 2, 3, 4, 5]).transform((i) async {
        if (i >= 3) return null;

        await Future.delayed(const Duration(microseconds: 10));
        return [
          i,
          i + 100,
          i + 1000,
        ];
      });

      expect(await i.toList(), equals([1, 101, 1001, 2, 102, 1002]));
    });

    test('seed sets the initial value', () async {
      final i = OffsetIterator.fromIterable([1, 2]).transform((i) async {
        await Future.delayed(const Duration(microseconds: 10));
        return [
          i,
          i + 100,
          i + 1000,
        ];
      }, seed: () => some(0));

      expect(i.value, some(0));
      expect(i.offset, 0);
      expect(
          await i.startFrom(0).toList(), equals([1, 101, 1001, 2, 102, 1002]));
    });
  });

  group('map', () {
    test('transforms the items including the seed', () async {
      final i = OffsetIterator.fromIterable([2, 3], seed: () => some(1))
          .map((i) => i * 2);

      expect(i.value, some(2));
      expect(i.offset, 0);
      expect(await i.toList(), equals([4, 6]));
    });

    test('startOffset allows replay', () async {
      final i = OffsetIterator.fromIterable(
        [2, 3],
        seed: () => some(1),
        retention: -1,
      );
      await i.run();
      expect(i.log.toList(), [1, 2]);

      final mapped = i.startFrom(0).map((i) => i * 2);

      expect(mapped.value, some(2));
      expect(mapped.offset, 0);
      expect(await mapped.toList(), equals([4, 6]));
    });

    test('unseeded startOffset from 0', () async {
      final i = OffsetIterator.fromIterable(
        [1, 2, 3],
        retention: -1,
      );
      await i.run();
      expect(i.log.toList(), [1, 2]);

      final mapped = i.startFrom(0).map((i) => i * 2);

      expect(mapped.value, none());
      expect(mapped.offset, 0);
      expect(await mapped.toList(), equals([2, 4, 6]));
    });
  });

  group('asyncMap', () {
    test('transforms the items', () async {
      final i = OffsetIterator.fromIterable([2, 3])
          .asyncMap((i) async => i * 2, seed: () => some(2));

      expect(i.value, some(2));
      expect(i.offset, 0);
      expect(await i.toList(), equals([4, 6]));
    });
  });

  group('scan', () {
    test('reduces and emits each accumulator', () async {
      final i = OffsetIterator.fromIterable([1, 2, 3])
          .scan<int>(0, (acc, i) => acc + i);

      expect(i.value, none());
      expect(i.offset, 0);
      expect(await i.toList(), equals([1, 3, 6]));
    });

    test('allows the seed to be set', () async {
      final i = OffsetIterator.fromIterable([1, 2, 3])
          .scan<int>(0, (acc, i) => acc + i, seed: () => some(-1));

      expect(i.value, some(-1));
      expect(i.offset, 0);
      expect(await i.toList(), equals([1, 3, 6]));
    });
  });

  group('tap', () {
    test('runs the effect function for each item', () async {
      final processed = <int>[];
      final i =
          OffsetIterator.fromIterable([1, 2, 3], seed: () => some(0)).tap((i) {
        processed.add(i);
      });

      expect(i.value, some(0));

      expect(await i.toList(), equals([1, 2, 3]));
      expect(processed, equals([1, 2, 3]));
    });
  });

  group('tap', () {
    test('runs the effect function for each item', () async {
      final processed = <int>[];
      final i =
          OffsetIterator.fromIterable([1, 2, 3], seed: () => some(0)).tap((i) {
        processed.add(i);
      });

      expect(i.value, some(0));

      expect(await i.toList(), equals([1, 2, 3]));
      expect(processed, equals([1, 2, 3]));
    });
  });

  group('distinct', () {
    test('removes sequential duplicates', () async {
      final i =
          OffsetIterator.fromIterable([1, 1, 2, 2, 3, 3], seed: () => some(1))
              .distinct();

      expect(i.value, some(1));

      expect(await i.toList(), equals([2, 3]));
    });

    test('removes sequential duplicates without seed', () async {
      final i = OffsetIterator.fromIterable([1, 1, 2, 2, 3, 3]).distinct();

      expect(i.value, none());
      expect(await i.toList(), equals([1, 2, 3]));
    });
  });

  group('takeWhile', () {
    test('emits items until predicate returns false', () async {
      final i =
          OffsetIterator.fromIterable([1, 2, 3, 4, 5], seed: () => some(0))
              .takeWhile((i, prev) => i < 3);

      expect(i.value, some(0));
      expect(await i.toList(), equals([1, 2]));
    });
  });

  group('takeUntil', () {
    test('emits items until predicate returns true', () async {
      final i =
          OffsetIterator.fromIterable([1, 2, 3, 4, 5], seed: () => some(0))
              .takeUntil((i, prev) => i >= 3);

      expect(i.value, some(0));
      expect(await i.toList(), equals([1, 2]));
    });
  });

  group('accumulate', () {
    test('concats each list of items together', () async {
      final i = OffsetIterator.fromIterable<List<int>>([
        const [1, 2, 3],
        const [4, 5, 6],
        const [7, 8, 9],
      ]).accumulate();

      expect(i.value, none());
      expect(
        await i.toList(),
        equals([
          const [1, 2, 3],
          const [1, 2, 3, 4, 5, 6],
          const [1, 2, 3, 4, 5, 6, 7, 8, 9],
        ]),
      );
    });
  });

  group('accumulateIList', () {
    test('concats each IList of items together', () async {
      final i = OffsetIterator.fromIterable<IList<int>>([
        IList(const [1, 2, 3]),
        IList(const [4, 5, 6]),
        IList(const [7, 8, 9]),
      ]).accumulateIList();

      expect(i.value, none());
      expect(
        await i.toList(),
        equals([
          IList(const [1, 2, 3]),
          IList(const [1, 2, 3, 4, 5, 6]),
          IList(const [1, 2, 3, 4, 5, 6, 7, 8, 9]),
        ]),
      );
    });
  });

  group('handleError', () {
    test(
        'runs the handler on error and stops the iterator if it returns nothing',
        () async {
      var handled = false;
      final i = OffsetIterator<int>(
        init: () => 0,
        process: (acc) {
          if (acc > 2) throw 'fail';

          return OffsetIteratorState(
            acc: acc + 1,
            chunk: [acc],
            hasMore: true,
          );
        },
        seed: () => some(-1),
      ).handleError((err, stack) {
        handled = true;
      });

      expect(i.value, some(-1));
      expect(await i.toList(), equals([0, 1, 2]));
      expect(handled, equals(true));
    });

    test('runs the handler on error and retries if true is returned', () async {
      var retries = 0;
      final i = OffsetIterator<int>(
        init: () => 0,
        process: (acc) {
          if (acc == 2) throw 'fail';

          return OffsetIteratorState(
            acc: acc + 1,
            chunk: [acc],
            hasMore: true,
          );
        },
        seed: () => some(-1),
      ).handleError((err, stack) {
        retries++;
        return true;
      });

      expect(i.value, some(-1));
      expect(await i.toList(), equals([0, 1]));
      expect(retries, equals(5));
    });
  });

  group('fold', () {
    test('reduces the iterator to a single value', () async {
      final result = await OffsetIterator.fromIterable([1, 2, 3, 4, 5])
          .fold<int>(0, (acc, i) => acc + i);
      expect(result, equals(15));
    });
  });

  group('sum', () {
    test('works for int', () async {
      final result = await OffsetIterator.fromIterable([1, 2, 3, 4, 5]).sum();
      expect(result, equals(15));
    });

    test('works for double', () async {
      final result =
          await OffsetIterator.fromIterable(<double>[1.0, 2, 3, 4, 5]).sum();
      expect(result, equals(15));
    });
  });

  group('flatMap', () {
    test('flattens the inner OffsetIterators', () async {
      final i = OffsetIterator.fromIterable([1, 2]).flatMap(
        (i) => OffsetIterator.fromIterable([
          i,
          i + 100,
          i + 1000,
        ]),
        seed: () => some(0),
      );

      expect(i.value, some(0));
      expect(i.offset, 0);
      expect(await i.toList(), equals([1, 101, 1001, 2, 102, 1002]));
    });
  });

  group('transformConcurrent', () {
    test('runs the predicate concurrently', () async {
      var running = 0;
      final i = OffsetIterator.fromIterable([1, 2, 3, 4]).transformConcurrent(
        (i) async {
          running++;
          await Future.delayed(const Duration(milliseconds: 100));
          running--;
          return [i, i + 100];
        },
        concurrency: 3,
      );

      expect(await i.pull(), some(1));
      expect(running, equals(3));
      expect(await i.pull(), some(101));
      expect(running, equals(3));

      expect(await i.pull(), some(2));
      expect(running, equals(2));
      expect(await i.pull(), some(102));
      expect(running, equals(2));

      expect(await i.pull(), some(3));
      expect(running, equals(1));
      expect(await i.pull(), some(103));
      expect(running, equals(1));

      expect(await i.pull(), some(4));
      expect(running, equals(0));
      expect(await i.pull(), some(104));
      expect(running, equals(0));

      expect(await i.pull(), none());
    });
  });

  group('prefetch', () {
    test('eagerly pulls the next item from the parent', () async {
      final i = OffsetIterator.range(1, end: 5);
      final prefetched = i.prefetch();

      expect(await prefetched.pull(), some(1));
      expect(i.offset, equals(2));
      expect(i.value, equals(some(2)));

      expect(await prefetched.toList(), [2, 3, 4, 5]);
    });
  });

  group('bufferCount', () {
    test('adds the parent items into lists', () async {
      final i = OffsetIterator.range(1, end: 10).bufferCount(3);

      expect(await i.toList(), [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
        [10],
      ]);
    });
  });

  group('listen', () {
    test('callbacks receive latest items', () async {
      final results = <int>[];
      final complete = Completer.sync();
      final i = OffsetIterator.range(1, end: 5);

      i.listen(results.add, onDone: complete.complete);

      await complete.future;

      expect(results, [1, 2, 3, 4, 5]);
    });

    test('cancel works', () async {
      final results = <int>[];
      final i = OffsetIterator.fromStream(Stream.fromIterable([1, 2, 3, 4, 5]));
      late final void Function() cancel;
      cancel = i.listen((i) {
        results.add(i);
        if (results.length == 2) cancel();
      });

      await i.run();

      expect(results, [1, 2]);
    });
  });
}
