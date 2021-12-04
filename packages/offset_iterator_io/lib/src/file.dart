import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

/// Perform a streaming read operation on the given [File].
/// `blockSize` changes the amount of bytes to read into each chunk.
OffsetIterator<Uint8List> fileIterator(
  File file, {
  int blockSize = 64 * 1024,
}) =>
    OffsetIterator(
      init: () => file.open(mode: FileMode.read),
      process: (acc) async {
        final file = acc as RandomAccessFile;
        final chunk = await file.read(blockSize);
        final hasMore = chunk.length == blockSize;

        return OffsetIteratorState(
          acc: file,
          chunk: [chunk],
          hasMore: hasMore,
        );
      },
      cleanup: (file) => file.close(),
    );

extension WriteToFile on OffsetIterator<List<int>> {
  /// Performs a streaming write operation into the given [File].
  OffsetIterator<int> writeToFile(
    File file, {
    FileMode mode = FileMode.writeOnly,
    int? startOffset,
  }) {
    final parent = this;

    return OffsetIterator(
      init: () => file
          .open(mode: mode)
          .then((file) => tuple2(file, startOffset ?? parent.offset)),
      process: (acc) async {
        final file = acc.first as RandomAccessFile;
        var offset = acc.second as int;

        final earliest = parent.earliestAvailableOffset - 1;
        if (offset < earliest) offset = earliest;

        final chunk = await parent.pull(offset);

        // Prefetch next chunk
        final newOffset = offset + 1;
        final hasMore = parent.hasMore(newOffset);
        if (hasMore && newOffset == parent.offset) parent.pull(newOffset);

        await chunk.match(file.writeFrom, () {});

        return OffsetIteratorState(
          acc: tuple2(file, newOffset),
          chunk: chunk.match((c) => [c.length], () => []),
          hasMore: hasMore,
        );
      },
      cleanup: (acc) => acc.first.close(),
    );
  }
}
