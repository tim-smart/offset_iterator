library offset_iterator_riverpod;

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:riverpod/riverpod.dart';

OffsetIterator<T> Function(OffsetIterator<T> iterator) iteratorProvider<T>(
  ProviderRef<OffsetIterator<T>> ref, {
  int initialDemand = 1,
}) =>
    (iterator) {
      final sub = Stream.fromIterable(Iterable<int>.generate(initialDemand))
          .asyncMap((_) => iterator.pull())
          .listen((_) {});

      ref.onDispose(iterator.cancel);
      ref.onDispose(sub.cancel);

      return iterator;
    };

Option<T> Function(
  OffsetIterator<T> iterator,
) iteratorValueProvider<T>(ProviderRef<Option<T>> ref) => (iterator) {
      final sub = iterator.valueStream.listen((s) {
        ref.state = Some(s);
      });

      ref.onDispose(sub.cancel);

      return iterator.value;
    };

bool Function(
  OffsetIterator<T> iterator,
) iteratorHasMoreProvider<T>(ProviderRef<bool> ref) => (iterator) {
      final sub = iterator.valueStream.listen((_) {}, onDone: () {
        ref.state = false;
      });

      ref.onDispose(sub.cancel);

      return true;
    };
