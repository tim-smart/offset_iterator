import 'dart:io';

import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator_io/offset_iterator_io.dart';
import 'package:test/test.dart';

void main() {
  group('fileIterator', () {
    test('can read this file', () async {
      final file = File('test/file_test.dart');
      final output = File('test/tmp/fileIterator.txt');

      await fileIterator(file).writeToFile(output).run();

      expect(await file.readAsString(), await output.readAsString());
    });
  });

  group('writeToFile', () {
    test('emits the number bytes written', () async {
      final file = File('test/tmp/writeToFile.txt');
      final i = OffsetIterator.fromValue('hello').encode().writeToFile(file);

      final bytesWritten = await i.sum();
      expect(bytesWritten, equals(5));
      expect(await file.readAsString(), 'hello');
    });

    test('cleanup is called if parent fails', () async {
      final i = OffsetIterator<String>(
        init: () {},
        process: (_) => throw 'fail',
      ).encode().writeToFile(File("test/tmp/WriteToFileExtensions.txt"));

      await expectLater(i.pull, throwsA('fail'));
      expect(i.state.acc.closed, true);
    });

    test('bubbleCancellation works', () async {
      final file = File('test/file_test.dart');
      final output = File('test/tmp/writeToFile_cancel.txt');

      final reader = fileIterator(file, blockSize: 5);
      final i = reader.writeToFile(output);

      await i.pull();
      expect(i.drained, false);
      expect(reader.state.acc.closed, false);

      await i.cancel();
      expect(i.drained, true);
      expect(reader.state.acc.closed, true);
    });
  });
}
