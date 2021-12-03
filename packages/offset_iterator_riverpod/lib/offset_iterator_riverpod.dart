library offset_iterator_riverpod;

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:riverpod/riverpod.dart';

OffsetIterator<T> Function(OffsetIterator<T> iterator) iteratorProvider<T>(
  ProviderRef<OffsetIterator<T>> ref, {
  int initialDemand = 1,
}) =>
    (iterator) {
      final initial =
          OffsetIterator.range(1, end: initialDemand).asyncMap((_) async {
        await iterator.pull();
      });

      ref.onDispose(iterator.cancel);
      ref.onDispose(initial.cancel);

      initial.run();

      return iterator;
    };

Option<T> Function(
  OffsetIterator<T> iterator,
) iteratorValueProvider<T>(ProviderRef<Option<T>> ref) => (iterator) {
      void onChange() {
        ref.state = iterator.value;
      }

      iterator.addListener(onChange);
      ref.onDispose(() => iterator.removeListener(onChange));

      return iterator.value;
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
