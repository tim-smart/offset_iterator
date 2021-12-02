import 'dart:math' as math;

import 'package:offset_iterator/src/offset_iterator.dart';

extension ConsumerGroupExtension<T> on OffsetIterator<T> {
  ConsumerGroup<T> consumerGroup() => ConsumerGroup(this);
}

class ConsumerGroup<T> {
  ConsumerGroup(this.iterator);

  final OffsetIterator<T> iterator;
  final _offsets = <OffsetIterator<T>, int>{};
  Future<void>? _sweepFuture;

  Set<OffsetIterator<T>> get children => _offsets.keys.toSet();

  OffsetIterator<T> consumer({
    int? startOffset,
    int retention = 0,
  }) {
    startOffset ??= iterator.offset;
    late final OffsetIterator<T> i;

    i = OffsetIterator(
      init: () => startOffset!,
      process: (offset) async {
        final item = await iterator.pull(offset);
        _childPulledOffset(i, offset);
        return OffsetIteratorState(
          acc: offset + 1,
          chunk: item.match((v) => [v], () => []),
          hasMore: iterator.hasMore(offset + 1),
        );
      },
      seed: iterator.generateSeed(startOffset: startOffset),
      retention: retention,
    );

    _register(i, startOffset);

    return i;
  }

  void _register(OffsetIterator<T> child, int offset) {
    _offsets[child] = offset + 1;
  }

  void _childPulledOffset(OffsetIterator<T> child, int offset) {
    _offsets[child] = offset + 2;
    _maybeSetEarliestOffset();
  }

  void deregister(OffsetIterator<T> child) {
    _offsets.remove(child);
    _maybeSetEarliestOffset();
  }

  void _maybeSetEarliestOffset() {
    if (_offsets.isEmpty || _sweepFuture != null) return;

    _sweepFuture = Future.microtask(() {
      iterator.earliestAvailableOffset = _offsets.values.reduce(math.min);
      _sweepFuture = null;
    });
  }
}
