import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:test/test.dart';

Tuple2<OffsetIteratorSink<int>, Future<List<int>>> multiplierSink() {
  final c = OffsetIteratorController<int>();
  final completer = Completer<List<int>>.sync();

  c.iterator
      .asyncMap((number) async {
        // Simulate expensive operation
        await Future.delayed(const Duration(milliseconds: 5));
        return number * 2;
      })
      .toList()
      .then(completer.complete, onError: completer.completeError);

  return tuple2(c.sink, completer.future);
}

void main() {
  group('multiplierSink', () {
    test('multiplies the numbers', () async {
      final m = multiplierSink();
      final sink = m.first;

      await Future.microtask(() {});

      sink.add(1);
      sink.add(2);
      sink.add(3);
      await sink.close(some(4));

      expect(await m.second, [2, 4, 6, 8]);
    });

    test('cancels on error', () async {
      final m = multiplierSink();
      final sink = m.first;

      sink.add(1);
      sink.add(2);
      sink.addError('fail');
      expect(() => sink.close(), throwsStateError);

      await expectLater(m.second, throwsA('fail'));
    });
  });
}
