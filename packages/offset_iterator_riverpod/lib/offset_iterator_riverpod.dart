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
      ref.onDispose(iterator.valueStream.listen((s) {
        ref.state = Some(s);
      }).cancel);

      return iterator.value;
    };

bool Function(
  OffsetIterator<T> iterator,
) iteratorHasMoreProvider<T>(ProviderRef<bool> ref) => (iterator) {
      if (!iterator.hasMore()) return false;

      ref.onDispose(iterator.valueStream.listen((_) {}, onDone: () {
        ref.state = false;
      }).cancel);

      return true;
    };
