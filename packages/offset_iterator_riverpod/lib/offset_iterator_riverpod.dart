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
  const OffsetIteratorValue._(this.value, this._pull);

  final AsyncValue<T> value;
  final Future<void> Function(int) _pull;

  Future<void> pull() => _pull(1);
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
        if (disposed || remaining == 0) return Future.sync(() {});

        return Future.value(iterator.pull(offset)).then((_) {
          offset++;
          return doPull(remaining - 1);
        }).catchError((err, stack) {
          ref.state = OffsetIteratorValue._(
            AsyncValue.error(err, stackTrace: stack),
            doPull,
          );
        });
      }

      doPull(initialDemand);

      // Handle value changes
      void onChange() {
        iterator.value.map((v) => ref.state = OffsetIteratorValue._(
              AsyncValue.data(v),
              doPull,
            ));
      }

      iterator.addListener(onChange);
      ref.onDispose(() => iterator.removeListener(onChange));

      return OffsetIteratorValue._(
        iterator.value.match(
          (v) => AsyncValue.data(v),
          () => const AsyncValue.loading(),
        ),
        doPull,
      );
    };

bool Function(
  OffsetIterator<T> iterator,
) iteratorHasMoreProvider<T>(ProviderRef<bool> ref) => (iterator) {
      if (iterator.drained) return false;

      void onChange() {
        if (!iterator.drained) return;
        ref.state = false;
      }

      iterator.addListener(onChange);
      ref.onDispose(() => iterator.removeListener(onChange));

      return true;
    };
