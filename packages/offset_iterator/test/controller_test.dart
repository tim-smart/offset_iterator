import 'dart:async';

import 'package:offset_iterator/offset_iterator.dart';
import 'package:test/test.dart';

OffsetIteratorController<int> multiplierController() =>
    OffsetIteratorController<int>(
      transform: (i) => i.asyncMap((number) async {
        // Simulate expensive operation
        await Future.delayed(const Duration(milliseconds: 5));
        return number * 2;
      }, retention: -1),
    );

void main() {
  group('multiplierSink', () {
    test('multiplies the numbers', () async {
      final sink = multiplierController();
      sink.iterator.run();

      await Future.microtask(() {});

      sink.add(1);
      sink.add(2);
      sink.add(3);
      sink.close(const Option.of(4));

      expect(await sink.iterator.startFrom(0).toList(), [2, 4, 6, 8]);
    });

    test('cancels on error', () async {
      final sink = multiplierController();
      expectLater(sink.iterator.run, throwsA('fail'));

      sink.add(1);
      sink.add(2);
      sink.addError('fail');
      expect(() => sink.close(), throwsStateError);
    });
  });

  group('PipeExtension', () {
    test('sends everything to the sink', () async {
      final i = OffsetIterator.range(1, end: 4);
      final sink = multiplierController();

      await sink.drain(i.pipe);
      expect(await sink.iterator.startFrom(0).toList(), [2, 4, 6, 8]);
    });
  });
}
