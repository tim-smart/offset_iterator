import 'dart:convert';
import 'dart:io';

import 'package:elemental/elemental.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

void main() {
  group('OffsetIterator', () {
    test('pagination example', () async {
      Future<String> fetchPage(int page) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return 'page $page';
      }

      final i = OffsetIterator(
        init: () => 1, // Start from page 1
        process: (nextPage) async {
          final pageContent = await fetchPage(nextPage);
          return OffsetIteratorState(
            acc: nextPage + 1, // Set the next accumulator / cursor
            chunk: [pageContent], // Add the page content
            hasMore: nextPage < 5, // We only want 5 pages
          );
        },
      );

      expect(
        await i.toList(),
        equals([
          'page 1',
          'page 2',
          'page 3',
          'page 4',
          'page 5',
        ]),
      );
    });

    test('cleanup', () async {
      var closed = false;
      final i = OffsetIterator(
        init: () => File('test/offset_iterator_test.dart').open(),
        process: (acc) async {
          final file = acc as RandomAccessFile;
          final chunk = await file.read(6);

          return OffsetIteratorState(
            acc: acc,
            chunk: [utf8.decode(chunk)],
            hasMore: chunk.isNotEmpty,
          );
        },
        cleanup: (file) async {
          await file.close();
          closed = true;
        },
      );

      final result = await i.toList();
      expect(result, isNotEmpty);
      expect(result.first, 'import');
      expect(closed, true);
    });
  });

  group('OffsetIterator.fromStream', () {
    test('it correctly drains the stream', () async {
      final i = OffsetIterator.fromStream(Stream.fromIterable([1, 2, 3, 4, 5]));
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
    });

    test('sets the seed if a ValueStream is provided', () async {
      final i = OffsetIterator.fromStream(
          Stream.fromIterable([1, 2, 3, 4, 5]).shareValueSeeded(0));
      expect(i.value, const Option.of(0));
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
    });

    test('cancelOnError works', () async {
      final i = OffsetIterator.fromStream(Stream.fromIterable([1, 2, 3, 4, 5])
          .asyncExpand((i) => i == 2 ? Stream.error('fail') : Stream.value(i)));

      expect(await i.pull(), equals(const Option.of(1)));
      await expectLater(i.pull, throwsA('fail'));
      expect(i.drained, true);
    });

    test('cancelOnError false works', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]).asyncExpand(
            (i) => i == 2 ? Stream.error('fail') : Stream.value(i)),
        cancelOnError: false,
      ).wrapWithEither();

      expect(
        await i.toList(),
        [
          right(1),
          left('fail'),
          right(3),
          right(4),
          right(5),
        ],
      );
    });
  });

  group('OffsetIterator.fromStreamEither', () {
    test('emits items and errors as Either', () async {
      final i = OffsetIterator.fromStreamEither(
        Stream.fromIterable([1, 2, 3, 4, 5]).asyncExpand(
            (i) => i == 2 ? Stream.error('fail') : Stream.value(i)),
      );

      expect(
        await i.toList(),
        [
          Either.right(1),
          Either.left('fail'),
          Either.right(3),
          Either.right(4),
          Either.right(5),
        ],
      );
    });
  });

  group('OffsetIterator.fromIterable', () {
    test('it correctly drains the iterable', () async {
      final i = OffsetIterator.fromIterable([1, 2, 3, 4, 5]);
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
    });
  });

  group('OffsetIterator.fromValue', () {
    test('it returns the value', () async {
      final i = OffsetIterator.fromValue('hello');
      expect(await i.toList(), equals(['hello']));
    });
  });

  group('OffsetIterator.fromFuture', () {
    test('it resolves the future', () async {
      final i = OffsetIterator.fromFuture(() async => 'hello');
      expect(await i.toList(), equals(['hello']));
    });
  });

  group('OffsetIterator.range', () {
    test('it resolves the future', () async {
      final i = OffsetIterator.range(0, end: 5);
      expect(await i.toList(), equals([0, 1, 2, 3, 4, 5]));
    });

    test('it emits nothing if end if smaller than start', () async {
      final i = OffsetIterator.range(1, end: 0);
      expect(await i.toList(), equals([]));
    });
  });

  group('.pull', () {
    test('responds with the next item', () async {
      final i = OffsetIterator.fromIterable([
        'the',
        'quick',
        'brown',
        'fox',
      ]);
      expect(await i.pull(), const Option.of('the'));
      expect(await i.pull(), const Option.of('quick'));
      expect(await i.pull(), const Option.of('brown'));
      expect(await i.pull(), const Option.of('fox'));
      expect(await i.pull(), const Option.none());
    });

    test(
        'accepts an offset parameter for requesting past items (with retention enabled)',
        () async {
      final i = OffsetIterator.fromIterable([
        'the',
        'quick',
        'brown',
        'fox',
      ], retention: -1);
      expect(await i.pull(), const Option.of('the'));
      expect(await i.pull(), const Option.of('quick'));
      expect(await i.pull(), const Option.of('brown'));
      expect(await i.pull(), const Option.of('fox'));
      expect(await i.pull(), const Option.none());

      expect(await i.pull(3), const Option.of('fox'));
      expect(await i.pull(0), const Option.of('the'));

      // If offset is out of range, it throws a RangeError
      await expectLater(() => i.pull(-1), throwsRangeError);
      await expectLater(() => i.pull(5), throwsRangeError);
    });
  });

  group('retention', () {
    test('basic', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]),
        retention: 3,
      );
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
      expect(i.value, equals(const Option.of(5)));
      expect(i.log.toList(),
          equals([const Option.of(2), const Option.of(3), const Option.of(4)]));
      expect(i.earliestAvailableOffset, equals(2));

      expect(await i.startFrom(0).toList(), equals([2, 3, 4, 5]));
    });

    test('replaying', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]),
        retention: -1,
      );
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
      expect(await i.toList(), equals([]));
      expect(await i.startFrom(0).toList(), equals([1, 2, 3, 4, 5]));
      expect(await i.startFrom(2).toList(), equals([3, 4, 5]));
    });

    test('you can not request un-pulled items', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]),
        retention: -1,
      );
      await expectLater(() => i.startFrom(3).toList(), throwsRangeError);
    });
  });

  group('.cancel', () {
    test('it stops new data being pulled', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]),
        retention: -1,
      );
      await i.pull();
      await i.pull();
      i.cancel();

      expect(await i.pull(), const Option.none());
      expect(await i.startFrom(0).toList(), equals([1, 2]));
    });
  });

  group('.generateSeed', () {
    test('by default returns a seed that returns the latest value', () async {
      final i =
          OffsetIterator.range(0, end: 5, seed: () => const Option.of(-1));

      expect(i.status, OffsetIteratorStatus.unseeded);
      final seed = i.generateSeed();
      expect(i.status, OffsetIteratorStatus.seeded);
      expect(seed!(), const Option.of(-1));
    });

    test('accepts an override', () async {
      final i =
          OffsetIterator.range(0, end: 5, seed: () => const Option.of(-1));

      expect(i.status, OffsetIteratorStatus.unseeded);
      final seed = i.generateSeed(override: () => const Option.of(-2));
      expect(i.status, OffsetIteratorStatus.unseeded);
      expect(seed!(), const Option.of(-2));
    });

    test('accepts a fallback', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      final seed = i.generateSeed(fallback: () => const Option.of(-2));
      expect(i.status, OffsetIteratorStatus.seeded);
      expect(seed!(), const Option.of(-2));
    });
  });

  group('.status', () {
    test('starts unseeded until value is accessed', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      expect(i.value, const Option.none());
      expect(i.status, OffsetIteratorStatus.seeded);
    });

    test('starts unseeded until offset is accessed', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      expect(i.offset, 0);
      expect(i.status, OffsetIteratorStatus.seeded);
    });

    test('is active once pull is invoked', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      i.pull();
      expect(i.status, OffsetIteratorStatus.active);
    });

    test('is completed once all processing is complete', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      await i.toList();
      expect(i.status, OffsetIteratorStatus.completed);
    });

    test('is completed when cancelled', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      i.pull();
      expect(i.status, OffsetIteratorStatus.active);
      i.cancel();
      expect(i.status, OffsetIteratorStatus.completed);
    });
  });

  group('set .earliestAvailableOffset', () {
    test('trims the log', () async {
      final i = OffsetIterator.range(0, end: 5, retention: -1);
      await i.toList();

      expect(i.earliestAvailableOffset, 0);
      i.earliestAvailableOffset = 3;
      expect(i.earliestAvailableOffset, 3);
    });

    test('does nothing if out of bounds', () async {
      final i = OffsetIterator.range(0, end: 5, retention: -1);
      await i.toList();

      expect(i.earliestAvailableOffset, 0);

      i.earliestAvailableOffset = 1;
      expect(i.earliestAvailableOffset, 1);

      i.earliestAvailableOffset = 0;
      expect(i.earliestAvailableOffset, 1);

      i.earliestAvailableOffset = 7;
      expect(i.earliestAvailableOffset, 1);
      expect(i.log.toList(), [
        const Option.of(0),
        const Option.of(1),
        const Option.of(2),
        const Option.of(3),
        const Option.of(4)
      ]);

      i.earliestAvailableOffset = 6;
      expect(i.earliestAvailableOffset, 6);
      expect(i.log.isEmpty, true);
    });
  });

  group('state', () {
    test('allows adding of errors', () async {
      final i = OffsetIterator(
        init: () {},
        process: (_) => const OffsetIteratorState(
          acc: null,
          chunk: [],
          hasMore: false,
          error: 'fail',
        ),
      );

      expect(() => i.pull(), throwsA('fail'));
    });
  });

  group('cancelOnError', () {
    test('is true by default', () async {
      final i = OffsetIterator(
        init: () {},
        process: (_) => const OffsetIteratorState(
          acc: null,
          chunk: [],
          hasMore: true,
          error: 'fail',
        ),
      );

      expect(i.cancelOnError, true);

      expect(i.pull, throwsA('fail'));
      expect(i.drained, true);
      expect(i.status, OffsetIteratorStatus.completed);
      expect(i.state.error, 'fail');
    });

    test('when false does not cancel the iterator', () async {
      final i = OffsetIterator(
        init: () {},
        process: (_) => const OffsetIteratorState(
          acc: null,
          chunk: [],
          hasMore: true,
          error: 'fail',
        ),
        cancelOnError: false,
      );

      expect(i.cancelOnError, false);

      expect(i.pull, throwsA('fail'));
      expect(i.drained, false);
      expect(i.status, OffsetIteratorStatus.active);
      expect(i.state.error, 'fail');
    });
  });

  group('OffsetIterator.combine', () {
    test('merges the output from each iterator', () async {
      final i = OffsetIterator.combine([
        OffsetIterator.range(1, end: 3),
        OffsetIterator.range(4, end: 6),
        OffsetIterator.range(7, end: 9),
      ]);

      expect(await i.toList(), [1, 4, 7, 2, 5, 8, 3, 6, 9]);
    });
  });

  group('toString', () {
    test('without name', () async {
      final i = OffsetIterator.range(1, end: 5);
      expect(i.toString(), 'OffsetIterator.range<int>');
    });

    test('name property modifies toString output', () async {
      final i = OffsetIterator.range(1, end: 5, name: 'toStringTest');
      expect(i.toString(), 'toStringTest<int>');
    });
  });

  group('OptionExtension', () {
    test('when can unwrap Option values', () async {
      final i = OffsetIterator.range(1);

      expect(
        (await i.pull()).when(
          some: (i) => i * 2,
          none: () => 0,
        ),
        2,
      );
    });
  });
}
