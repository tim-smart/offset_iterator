library offset_iterator_riverpod;

import 'package:offset_iterator/offset_iterator.dart';
import 'package:riverpod/riverpod.dart';

OffsetIterator<T> Function(OffsetIterator<T> iterator) iteratorProvider<T>(
  ProviderRef<OffsetIterator<T>> ref,
) =>
    (iterator) {
      ref.onDispose(iterator.cancel);
      return iterator;
    };

class OffsetIteratorValue<T> {
  const OffsetIteratorValue._(this.value, this.hasMore, this._pull);

  final AsyncValue<T> value;
  final Future<void> Function(int) _pull;
  final bool hasMore;

  Future<void> pull() => _pull(1);

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType &&
        other is OffsetIteratorValue<T> &&
        other.value == value &&
        other.hasMore == hasMore;
  }

  @override
  int get hashCode => Object.hash(runtimeType, value, hasMore);
}

OffsetIteratorValue<T> Function(
  OffsetIterator<T> iterator,
) iteratorValueProvider<T>(
  ProviderRef<OffsetIteratorValue<T>> ref, {
  int? startOffset,
  int initialDemand = 1,
}) =>
    (iterator) {
      // Handle initialDemand
      var offset = startOffset ?? iterator.offset;
      var disposed = false;
      ref.onDispose(() => disposed = true);

      Future<void> doPull(int remaining) {
        if (disposed || remaining == 0 || iterator.isLastOffset(offset)) {
          return Future.sync(() {});
        }

        final earliest = iterator.earliestAvailableOffset - 1;
        if (earliest > offset) offset = earliest;

        return Future.value(iterator.pull(offset)).then((value) {
          offset++;
          value.map((v) => ref.state = OffsetIteratorValue._(
                AsyncValue.data(v),
                iterator.hasMore(offset),
                doPull,
              ));
          return doPull(remaining - 1);
        }).catchError((err, stack) {
          ref.state = OffsetIteratorValue._(
            AsyncValue.error(err, stackTrace: stack),
            iterator.hasMore(offset),
            doPull,
          );
        });
      }

      doPull(initialDemand);

      return OffsetIteratorValue._(
        iterator.valueAt(offset).match(
          (v) => AsyncValue.data(v),
          () => const AsyncValue.loading(),
        ),
        iterator.hasMore(offset),
        doPull,
      );
    };
