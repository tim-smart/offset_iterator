import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
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

  group('.pull', () {
    test('responds with the next item with its offset', () async {
      final i = OffsetIterator.fromIterable([
        'the',
        'quick',
        'brown',
        'fox',
      ]);
      expect(await i.pull(), some(tuple2('the', 1)));
      expect(await i.pull(), some(tuple2('quick', 2)));
      expect(await i.pull(), some(tuple2('brown', 3)));
      expect(await i.pull(), some(tuple2('fox', 4)));
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
      expect(await i.pull(), some(tuple2('the', 1)));
      expect(await i.pull(), some(tuple2('quick', 2)));
      expect(await i.pull(), some(tuple2('brown', 3)));
      expect(await i.pull(), some(tuple2('fox', 4)));
      expect(await i.pull(), none());

      expect(await i.pull(3), some(tuple2('fox', 4)));
      expect(await i.pull(0), some(tuple2('the', 1)));

      // If offset is out of range, it returns none
      expect(await i.pull(-1), none());
      expect(await i.pull(5), none());
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
      expect(await i.toList(startOffset: 3), equals([]));
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
}
