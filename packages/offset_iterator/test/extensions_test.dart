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

    test('hasMore allows transform to exit early', () async {
      final i =
          OffsetIterator.fromIterable([1, 2, 3, 4, 5]).transform((i) async {
        await Future.delayed(const Duration(microseconds: 10));
        return [
          i,
          i + 100,
          i + 1000,
        ];
      }, hasMore: (i) => i < 3);

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
      }, seed: 0);

      expect(i.value, some(0));
      expect(i.offset, 1);
      expect(await i.toList(startOffset: 0),
          equals([0, 1, 101, 1001, 2, 102, 1002]));
    });
  });

  group('map', () {
    test('transforms the items including the seed', () async {
      final i = OffsetIterator.fromIterable([2, 3], seed: 1).map((i) => i * 2);

      expect(i.value, some(2));
      expect(i.offset, 1);
      expect(await i.toList(), equals([4, 6]));
    });
  });

  group('asyncMap', () {
    test('transforms the items', () async {
      final i = OffsetIterator.fromIterable([2, 3])
          .asyncMap((i) async => i * 2, seed: 2);

      expect(i.value, some(2));
      expect(i.offset, 1);
      expect(await i.toList(), equals([4, 6]));
    });
  });

  group('scan', () {
    test('reduces and emits each accumulator', () async {
      final i = OffsetIterator.fromIterable([1, 2, 3])
          .scan<int>(0, (acc, i) => acc + i);

      expect(i.value, some(0));
      expect(i.offset, 1);
      expect(await i.toList(), equals([1, 3, 6]));
    });

    test('allows the seed to be manually set', () async {
      final i = OffsetIterator.fromIterable([1, 2, 3])
          .scan<int>(0, (acc, i) => acc + i, seed: -1);

      expect(i.value, some(-1));
      expect(i.offset, 1);
      expect(await i.toList(), equals([1, 3, 6]));
    });
  });

  group('tap', () {
    test('runs the effect function for each item', () async {
      final processed = <int>[];
      final i = OffsetIterator.fromIterable([1, 2, 3], seed: 0).tap((i) {
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
      final i = OffsetIterator.fromIterable([1, 2, 3], seed: 0).tap((i) {
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
          OffsetIterator.fromIterable([1, 1, 2, 2, 3, 3], seed: 1).distinct();

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
      final i = OffsetIterator.fromIterable([1, 2, 3, 4, 5], seed: 0)
          .takeWhile((i, prev) => i < 3);

      expect(i.value, some(0));
      expect(await i.toList(), equals([1, 2]));
    });
  });

  group('takeUntil', () {
    test('emits items until predicate returns true', () async {
      final i = OffsetIterator.fromIterable([1, 2, 3, 4, 5], seed: 0)
          .takeUntil((i, prev) => i >= 3);

      expect(i.value, some(0));
      expect(await i.toList(), equals([1, 2]));
    });
  });

  group('accumulate', () {
    test('concats each IList of items together', () async {
      final i = OffsetIterator.fromIterable<IList<int>>([
        IList(const [1, 2, 3]),
        IList(const [4, 5, 6]),
        IList(const [7, 8, 9]),
      ]).accumulate();

      expect(i.value, some(IList()));
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
      final i = OffsetIterator(
        init: () => 0,
        process: (acc) {
          if (acc > 2) throw 'fail';

          return OffsetIteratorState(
            acc: acc + 1,
            chunk: [acc],
            hasMore: true,
          );
        },
        seed: -1,
      ).handleError((err, stack) {
        handled = true;
      });

      expect(i.value, some(-1));
      expect(await i.toList(), equals([0, 1, 2]));
      expect(handled, equals(true));
    });

    test('runs the handler on error and retries if true is returned', () async {
      var retries = 0;
      final i = OffsetIterator(
        init: () => 0,
        process: (acc) {
          if (acc == 2) throw 'fail';

          return OffsetIteratorState(
            acc: acc + 1,
            chunk: [acc],
            hasMore: true,
          );
        },
        seed: -1,
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

  group('flatMap', () {
    test('flattens the inner OffsetIterators', () async {
      final i = OffsetIterator.fromIterable([1, 2]).flatMap(
          (i) => OffsetIterator.fromIterable([
                i,
                i + 100,
                i + 1000,
              ]),
          seed: 0);

      expect(i.value, some(0));
      expect(i.offset, 1);
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
}
