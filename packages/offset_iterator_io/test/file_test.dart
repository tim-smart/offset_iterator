import 'dart:io';

import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator_io/offset_iterator_io.dart';
import 'package:test/test.dart';

void main() {
  group('writeToFile', () {
    test('emits the number bytes written', () async {
      final i = OffsetIterator.fromValue('hello')
          .encode()
          .writeToFile(File('test/tmp/writeToFile.txt'));

      final bytesWritten = await i.sum();
      expect(bytesWritten, equals(5));
    });

    test('cleanup is called if parent fails', () async {
      final i = OffsetIterator<String>(
        init: () {},
        process: (_) => throw 'fail',
      ).encode().writeToFile(File("test/tmp/WriteToFileExtensions.txt"));

      await expectLater(i.pull, throwsA('fail'));
      expect(i.state.acc.first.closed, true);
    });
  });
}
