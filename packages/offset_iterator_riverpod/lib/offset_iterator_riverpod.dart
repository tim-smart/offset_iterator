// ignore_for_file: library_prefixes

library offset_iterator_riverpod;

import 'package:fpdt/function.dart';
import 'package:fpdt/option.dart' as O;
import 'package:offset_iterator/offset_iterator.dart';
import 'package:riverpod/riverpod.dart';

export 'package:offset_iterator/offset_iterator.dart';

OffsetIterator<T> Function(OffsetIterator<T> iterator) iteratorProvider<T>(
  ProviderRef<OffsetIterator<T>> ref,
) =>
    (iterator) {
      ref.onDispose(iterator.cancel);
      return iterator;
    };

class OffsetIteratorValue<T> {
  const OffsetIteratorValue._(this.value, this.hasMore);

  final T value;
  final bool hasMore;

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

class OffsetIteratorAsyncValue<T> extends OffsetIteratorValue<AsyncValue<T>> {
  const OffsetIteratorAsyncValue._(
    AsyncValue<T> value,
    bool hasMore,
    this._pull,
  ) : super._(value, hasMore);

  final Future<void> Function(int) _pull;

  Future<void> pull() => _pull(1);
}

/// Pulls an [OffsetIterator] on demand, and exposes the most recently pulled
/// [OffsetIteratorAsyncValue].
OffsetIteratorAsyncValue<T> Function(
  OffsetIterator<T> iterator,
) iteratorValueProvider<T>(
  ProviderRef<OffsetIteratorAsyncValue<T>> ref, {
  int initialDemand = 1,
}) =>
    (iterator) {
      // Handle initialDemand
      var disposed = false;
      ref.onDispose(() => disposed = true);

      Future<void> doPull(int remaining) {
        if (disposed || remaining == 0 || iterator.drained) {
          return Future.sync(() {});
        }

        return Future.value(iterator.pull()).then((value) {
          value.p(O.map((v) => ref.state = OffsetIteratorAsyncValue._(
                AsyncValue.data(v),
                iterator.hasMore(),
                doPull,
              )));

          return doPull(remaining - 1);
        }).catchError((err, stack) {
          ref.state = OffsetIteratorAsyncValue._(
            AsyncValue.error(err, stackTrace: stack),
            iterator.hasMore(),
            doPull,
          );
        });
      }

      doPull(initialDemand);

      return OffsetIteratorAsyncValue._(
        iterator.value.p(O.fold(
          () => const AsyncValue.loading(),
          (v) => AsyncValue.data(v),
        )),
        iterator.hasMore(),
        doPull,
      );
    };

/// Listens to an [OffsetIterator], and updates the exposed
/// [OffsetIteratorValue] whenever it changes.
OffsetIteratorValue<Option<T>> Function(
  OffsetIterator<T> iterator,
) iteratorLatestValueProvider<T>(
  ProviderRef<OffsetIteratorValue<Option<T>>> ref,
) =>
    (iterator) {
      final cancel = iterator.listen((item) {
        ref.state = OffsetIteratorValue._(Some(item), iterator.hasMore());
      }, onDone: () {
        ref.state = OffsetIteratorValue._(ref.state.value, false);
      });

      ref.onDispose(cancel);

      return OffsetIteratorValue._(iterator.value, iterator.hasMore());
    };
