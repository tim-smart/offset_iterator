library offset_iterator_riverpod;

import 'package:offset_iterator/offset_iterator.dart';
import 'package:riverpod/riverpod.dart';
import 'package:state_iterator/state_iterator.dart';

export 'package:offset_iterator/offset_iterator.dart';
export 'package:state_iterator/state_iterator.dart';

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
          value.map((v) => ref.state = OffsetIteratorAsyncValue._(
                AsyncValue.data(v),
                iterator.hasMore(),
                doPull,
              ));

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
        iterator.value.match(
          (v) => AsyncValue.data(v),
          () => const AsyncValue.loading(),
        ),
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

/// Helper for creating a [StateIterator] provider.
/// Calls `close` on dispose.
StateIterator<T> Function(StateIterator<T> iterator) stateIteratorProvider<T>(
  ProviderRef<StateIterator<T>> ref,
) =>
    (iterator) {
      ref.onDispose(iterator.close);
      return iterator;
    };

/// Listens to an [StateIterator], and updates the exposed state whenever it
/// changes.
T Function(StateIterator<T> stateIterator) stateIteratorValueProvider<T>(
  ProviderRef<T> ref,
) =>
    (si) {
      final cancel = si.iterator.listen((item) => ref.state = item);
      ref.onDispose(cancel);
      return si.state;
    };
