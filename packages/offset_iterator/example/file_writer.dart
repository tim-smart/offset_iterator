import 'dart:convert';
import 'dart:io';

import 'package:offset_iterator/offset_iterator.dart';

OffsetIteratorSink<List<int>> writeFile(String path) {
  final c = OffsetIteratorController<List<int>>(
    transform: (parent) => OffsetIterator(
      init: () => File(path).open(mode: FileMode.write),
      process: (acc) async {
        final file = acc as RandomAccessFile;
        final chunk = await parent.pull();
        await chunk.match(file.writeFrom, () {});

        return OffsetIteratorState(
          acc: file,
          chunk: [],
          hasMore: !parent.drained,
        );
      },
      cleanup: (file) => file.close(),
    ),
  );

  return c.sink;
}

void main() async {
  final file = writeFile('/tmp/offset-iterator.txt');

  try {
    // Pipe hello world to the file
    await file.drain(OffsetIterator.fromIterable(
      ['Hello', ' ', 'World!'].map(utf8.encode),
    ).pipe);
  } catch (err) {
    print("error: $err");
  }
}
