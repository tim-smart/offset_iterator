import 'dart:convert';

import 'package:offset_iterator/offset_iterator.dart';

extension EncodeExtension on OffsetIterator<String> {
  /// Encodes strings into binary, using the given [Encoding] codec.
  /// Defaults to [utf8].
  OffsetIterator<List<int>> encode({
    Encoding encoding = utf8,
    String name = 'encode',
    bool bubbleCancellation = true,
    bool? cancelOnError,
  }) =>
      map(
        encoding.encode,
        name: name,
        bubbleCancellation: bubbleCancellation,
        cancelOnError: cancelOnError,
      );
}

extension DecodeExtension on OffsetIterator<List<int>> {
  /// Decodes binary into [String]'s, using the given [Encoding] codec.
  /// Defaults to [utf8].
  OffsetIterator<String> decode({
    Encoding encoding = utf8,
    String name = 'decode',
    bool bubbleCancellation = true,
    bool? cancelOnError,
  }) =>
      map(
        encoding.decode,
        name: name,
        bubbleCancellation: bubbleCancellation,
        cancelOnError: cancelOnError,
      );
}
