import 'dart:io';

import 'package:benchmarking/benchmarking.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator_io/offset_iterator_io.dart';

void main(List<String> args) async {
  final file = File(args[0]);
  final destination = File('test/tmp/file_copy_benchmark');

  final totalBytes = file.statSync().size;

  const settings = BenchmarkSettings(
    minimumRunTime: Duration(seconds: 10),
  );

  (await asyncBenchmark('OffsetIterator writeToFile', () async {
    await fileIterator(file).writeToFile(destination).run();
    await destination.delete();
  }, settings: settings))
      .report(units: totalBytes);

  (await asyncBenchmark('File.openWrite', () async {
    final sink = destination.openWrite();
    await file.openRead().pipe(sink);
    await destination.delete();
  }, settings: settings))
      .report(units: totalBytes);
}
