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

  // Pipe hello world to the file
  OffsetIterator.fromIterable(
    ['Hello', ' ', 'World!'].map(utf8.encode),
  ).pipe(file);

  // Start the pipeline
  try {
    await file.iterator.run();
  } catch (err) {
    print("error: $err");
  }
}
