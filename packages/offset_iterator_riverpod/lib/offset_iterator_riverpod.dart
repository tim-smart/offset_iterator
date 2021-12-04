library offset_iterator_riverpod;

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:riverpod/riverpod.dart';

OffsetIterator<T> Function(OffsetIterator<T> iterator) iteratorProvider<T>(
  ProviderRef<OffsetIterator<T>> ref,
) =>
    (iterator) {
      ref.onDispose(iterator.cancel);
      return iterator;
    };

Tuple2<AsyncValue<T>, Future<void> Function()> Function(
  OffsetIterator<T> iterator,
) iteratorValueProvider<T>(
  ProviderRef<Tuple2<AsyncValue<T>, Future<void> Function()>> ref, {
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
          ref.state = tuple2(
            AsyncValue.error(err, stackTrace: stack),
            () => doPull(1),
          );
        });
      }

      Future<void> pull() => doPull(1);

      doPull(initialDemand);

      // Handle value changes
      void onChange() {
        iterator.value.map((v) => ref.state = tuple2(AsyncValue.data(v), pull));
      }

      iterator.addListener(onChange);
      ref.onDispose(() => iterator.removeListener(onChange));

      return tuple2(
        iterator.value.match(
          (v) => AsyncValue.data(v),
          () => const AsyncValue.loading(),
        ),
        pull,
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
