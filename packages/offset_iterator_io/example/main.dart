import 'dart:io';

import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator_io/src/file.dart';

/// Copies a [File] into the destination [File].
Future<void> copyFile(String src, String dest) =>
    fileIterator(File(src)).writeToFile(File(dest)).run() as Future<void>;

void main(List<String> args) async {
  await copyFile(args[0], args[1]);
}
