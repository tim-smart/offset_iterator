import 'dart:io';

import 'package:benchmarking/benchmarking.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator_io/offset_iterator_io.dart';

void main(List<String> args) async {
  final file = File(args[0]);
  final destination = File('test/tmp/file_copy_benchmark');

  final megabytes = (file.statSync().size / 1024 / 1024).round();

  const settings = BenchmarkSettings(
    warmupTime: Duration(seconds: 2),
    minimumRunTime: Duration(seconds: 10),
  );

  (await asyncBenchmark('OffsetIterator.writeToFile', () async {
    await fileIterator(file).writeToFile(destination).run();
    await destination.delete();
  }, settings: settings))
      .report(units: megabytes);

  (await asyncBenchmark('File.openWrite', () async {
    await file.openRead().pipe(destination.openWrite());
    await destination.delete();
  }, settings: settings))
      .report(units: megabytes);
}
