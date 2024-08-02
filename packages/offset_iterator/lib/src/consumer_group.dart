import 'dart:async';
import 'dart:math' as math;

import 'package:offset_iterator/src/offset_iterator.dart';

extension ConsumerGroupExtension<T> on OffsetIterator<T> {
  /// Creates a [ConsumerGroup] that automatically trims the `log` when all
  /// consumers have pulled the earliest offset.
  ConsumerGroup<T> consumerGroup() {
    if (retention > -1) {
      throw StateError('retention should be -1 for ConsumerGroup usage');
    }

    return ConsumerGroup(this);
  }
}

class ConsumerGroup<T> {
  ConsumerGroup(this.iterator);

  /// The wrapped [OffsetIterator] that consumers will pull from.
  final OffsetIterator<T> iterator;

  final _offsets = <OffsetIterator<T>, int>{};
  Future<void>? _sweepFuture;

  /// The current [OffsetIterator]'s that are pulling from [iterator].
  Set<OffsetIterator<T>> get children => _offsets.keys.toSet();

  /// Create a new [OffsetIterator] that will pull from the [iterator].
  /// It is garanteed not to miss an item, and the parent will have it's `log`
  /// trimmed to contain the least amount of items as possible.
  OffsetIterator<T> consumer({
    int? startOffset,
    int retention = 0,
  }) {
    startOffset ??= iterator.offset;
    late final OffsetIterator<T> i;

    i = OffsetIterator(
      name: iterator.toStringWithChild('ConsumerGroup'),
      init: () => startOffset!,
      process: (offset) async {
        final item = await iterator.pull(offset);
        _childPulledOffset(i, offset);
        return OffsetIteratorState(
          acc: offset + 1,
          chunk: item.match(() => null, (v) => [v]),
          hasMore: iterator.hasMore(offset + 1),
        );
      },
      seed: iterator.generateSeed(startOffset: startOffset),
      retention: retention,
      cancelOnError: iterator.cancelOnError,
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

  /// Remove a child [OffsetIterator] from the [ConsumerGroup].
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

  /// Calls `cancel` on the wrapper [iterator].
  FutureOr<void> cancel() => iterator.cancel();
}
