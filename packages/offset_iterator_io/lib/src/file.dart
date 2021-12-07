import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

/// Perform a streaming read operation on the given [File].
/// `blockSize` changes the amount of bytes to read into each chunk.
OffsetIterator<Uint8List> fileIterator(
  File file, {
  int blockSize = 64 * 1024,
  String name = 'fileIterator',
  bool cancelOnError = true,
}) =>
    OffsetIterator(
      name: name,
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
      cancelOnError: cancelOnError,
    );

extension WriteToFile on OffsetIterator<List<int>> {
  /// Performs a streaming write operation into the given [File].
  OffsetIterator<int> writeToFile(
    File file, {
    FileMode mode = FileMode.writeOnly,
    String name = 'writeToFile',
    bool? cancelOnError,
    bool bubbleCancellation = true,
  }) {
    final parent = prefetch(bubbleCancellation: true);

    return OffsetIterator(
      name: toStringWithChild(name),
      init: () => file.open(mode: mode),
      process: (acc) async {
        final file = acc as RandomAccessFile;

        final futureOr = parent.pull();
        final chunk = futureOr is Future ? await futureOr : futureOr;
        await chunk.match(file.writeFrom, () {});

        return OffsetIteratorState(
          acc: file,
          chunk: chunk is Some ? [(chunk as Some).value.length] : const [],
          hasMore: parent.hasMore(),
        );
      },
      cleanup: parent.generateCleanup(
        cleanup: (file) => file.close(),
        bubbleCancellation: bubbleCancellation,
      ),
      cancelOnError: cancelOnError ?? parent.cancelOnError,
    );
  }
}
