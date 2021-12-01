import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
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
        cleanup: (acc) => (acc as RandomAccessFile).close(),
      );

      final result = await i.toList();
      expect(result, isNotEmpty);
      expect(result.first, 'import');
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
      expect(i.value, some(0));
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
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
      expect(await i.pull(), some('the'));
      expect(await i.pull(), some('quick'));
      expect(await i.pull(), some('brown'));
      expect(await i.pull(), some('fox'));
      expect(await i.pull(), none());
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
      expect(await i.pull(), some('the'));
      expect(await i.pull(), some('quick'));
      expect(await i.pull(), some('brown'));
      expect(await i.pull(), some('fox'));
      expect(await i.pull(), none());

      expect(await i.pull(3), some('fox'));
      expect(await i.pull(0), some('the'));

      // If offset is out of range, it throws a RangeError
      await expectLater(i.pull(-1), throwsRangeError);
      await expectLater(i.pull(5), throwsRangeError);
    });
  });

  group('retention', () {
    test('basic', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]),
        retention: 3,
      );
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
      expect(i.value, equals(some(5)));
      expect(i.log.toList(), equals([2, 3, 4]));
      expect(i.earliestAvailableOffset, equals(2));

      expect(await i.toList(startOffset: 0), equals([2, 3, 4, 5]));
    });

    test('replaying', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]),
        retention: -1,
      );
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
      expect(await i.toList(), equals([]));
      expect(await i.toList(startOffset: 0), equals([1, 2, 3, 4, 5]));
      expect(await i.toList(startOffset: 2), equals([3, 4, 5]));
    });

    test('you can not request un-pulled items', () async {
      final i = OffsetIterator.fromStream(
        Stream.fromIterable([1, 2, 3, 4, 5]),
        retention: -1,
      );
      await expectLater(i.toList(startOffset: 3), throwsRangeError);
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

      expect(await i.pull(), none());
      expect(await i.toList(startOffset: 0), equals([1, 2]));
    });
  });

  group('.valueStream', () {
    test('it emits the latest values', () async {
      final i = OffsetIterator.fromIterable([1, 2, 3, 4, 5]);
      expect(i.valueStream, emitsInOrder([1, 2, 3, 4, 5]));
      expect(await i.toList(), equals([1, 2, 3, 4, 5]));
    });
  });

  group('.generateSeed', () {
    test('by default returns a seed that returns the latest value', () async {
      final i = OffsetIterator.range(0, end: 5, seed: () => -1);

      expect(i.status, OffsetIteratorStatus.unseeded);
      final seed = i.generateSeed();
      expect(i.status, OffsetIteratorStatus.seeded);
      expect(seed!(), -1);
    });

    test('accepts an override', () async {
      final i = OffsetIterator.range(0, end: 5, seed: () => -1);

      expect(i.status, OffsetIteratorStatus.unseeded);
      final seed = i.generateSeed(override: () => -2);
      expect(i.status, OffsetIteratorStatus.unseeded);
      expect(seed!(), -2);
    });

    test('accepts a fallback', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      final seed = i.generateSeed(fallback: () => -2);
      expect(i.status, OffsetIteratorStatus.seeded);
      expect(seed!(), -2);
    });
  });

  group('.status', () {
    test('starts unseeded until value is accessed', () async {
      final i = OffsetIterator.range(0, end: 5);

      expect(i.status, OffsetIteratorStatus.unseeded);
      expect(i.value, none());
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

      expect(i.earliestAvailableOffset, 1);
      i.earliestAvailableOffset = 3;
      expect(i.earliestAvailableOffset, 3);
    });

    test('does nothing if out of bounds', () async {
      final i = OffsetIterator.range(0, end: 5, retention: -1);
      await i.toList();

      expect(i.earliestAvailableOffset, 1);

      i.earliestAvailableOffset = 1;
      expect(i.earliestAvailableOffset, 1);

      i.earliestAvailableOffset = 0;
      expect(i.earliestAvailableOffset, 1);

      i.earliestAvailableOffset = 7;
      expect(i.earliestAvailableOffset, 1);
      expect(i.log.toList(), [0, 1, 2, 3, 4]);

      i.earliestAvailableOffset = 6;
      expect(i.earliestAvailableOffset, 6);
      expect(i.log.isEmpty, true);
    });
  });
}
