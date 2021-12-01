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

Tuple2<Option<T>, bool> Function(
  OffsetIterator<T> iterator,
) iteratorValueProvider<T>(ProviderRef<Tuple2<Option<T>, bool>> ref) =>
    (iterator) {
      final sub = iterator.valueStream.listen((s) {
        ref.state = tuple2(Some(s), iterator.hasMore());
      }, onDone: () {
        ref.state = tuple2(iterator.value, iterator.hasMore());
      });

      ref.onDispose(sub.cancel);

      return tuple2(iterator.value, true);
    };
