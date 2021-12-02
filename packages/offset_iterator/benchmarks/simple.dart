import 'package:benchmarking/benchmarking.dart';
import 'package:offset_iterator/offset_iterator.dart';

void main() async {
  final numbers = Iterable.generate(1000000);

  (await asyncBenchmark('OffsetIterator.range[k]', () async {
    await OffsetIterator.range(0, end: 1000000).run();
  }))
      .report(units: 1000000);

  (await asyncBenchmark('OffsetIterator.fromIterable[k]', () async {
    await OffsetIterator.fromIterable(numbers).run();
  }))
      .report(units: numbers.length);

  (await asyncBenchmark('Stream.fromIterable[k]', () async {
    await Stream.fromIterable(numbers).asBroadcastStream().forEach((_) {});
  }))
      .report(units: numbers.length);
}
