import 'package:benchmarking/benchmarking.dart';
import 'package:offset_iterator/offset_iterator.dart';

void main() async {
  final numbers = Iterable<int>.generate(1000000);

  (await asyncBenchmark('OffsetIterator map scan', () async {
    await OffsetIterator.fromIterable(numbers)
        .map((i) => i * 2)
        // .scan(0, (int acc, i) => acc + i)
        .run();
  }))
      .report(units: numbers.length);

  // (await asyncBenchmark('Stream map scan', () async {
  //   await Stream.fromIterable(numbers)
  //       // .map((i) => i * 2)
  //       // .scan((int acc, i, _) => acc + i, 0)
  //       .forEach((_) {});
  // }))
  //     .report(units: numbers.length);
}
