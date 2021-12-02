import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/src/controller.dart';
import 'package:test/test.dart';

Tuple2<OffsetIteratorSink<int>, Future<List<int>>> multiplierSink() {
  final c = OffsetIteratorController<int>();
  final i = c.iterator;
  final completer = Completer<List<int>>.sync();
  final results = <int>[];

  Future<void> next() => Future.value(i.pull())
      .then((number) => number.match(
            (i) {
              results.add(i * 2);
              return next();
            },
            () => completer.complete(results),
          ))
      .catchError((err) => completer.completeError(err));

  Future.microtask(next);

  return tuple2(c.sink, completer.future);
}

void main() {
  group('multiplierSink', () {
    test('multiplies the numbers', () async {
      final m = multiplierSink();
      final sink = m.first;

      sink.add(1);
      sink.add(2);
      sink.add(3);
      sink.close(4);

      expect(await m.second, [2, 4, 6, 8]);
    });

    test('cancels on error', () async {
      final m = multiplierSink();
      final sink = m.first;

      sink.add(1);
      sink.add(2);
      sink.addError('fail');
      expect(() => sink.close(4), throwsStateError);

      await expectLater(m.second, throwsA('fail'));
    });
  });
}
