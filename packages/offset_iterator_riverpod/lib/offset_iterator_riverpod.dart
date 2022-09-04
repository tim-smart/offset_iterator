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
  const OffsetIteratorValue(this.value, this.hasMore, this.pulling);

  final T value;
  final bool hasMore;
  final bool pulling;

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType &&
        other is OffsetIteratorValue<T> &&
        other.value == value &&
        other.hasMore == hasMore &&
        other.pulling == pulling;
  }

  @override
  int get hashCode => Object.hash(runtimeType, value, hasMore);
}

class OffsetIteratorAsyncValue<T> extends OffsetIteratorValue<AsyncValue<T>> {
  const OffsetIteratorAsyncValue(
    AsyncValue<T> value,
    bool hasMore,
    bool pulling,
    this._pull,
  ) : super(value, hasMore, pulling);

  factory OffsetIteratorAsyncValue.loading() => OffsetIteratorAsyncValue(
        const AsyncValue.loading(),
        false,
        false,
        (_) => Future.value(),
      );

  final Future<void> Function(int) _pull;

  Future<void> pull() => _pull(1);

  OffsetIteratorAsyncValue<B> map<B>(B Function(T a) f) =>
      OffsetIteratorAsyncValue(
        value.whenData(f),
        hasMore,
        pulling,
        _pull,
      );

  bool get isLoading => pulling || value is AsyncLoading;

  Option<T> get data => value.maybeWhen(data: O.some, orElse: O.none);
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
      var canSetState = false;
      var disposed = false;
      ref.onDispose(() => disposed = true);

      Future<void> doPull(int remaining) {
        if (disposed || remaining == 0 || iterator.drained) {
          return Future.sync(() {});
        }

        if (canSetState) {
          ref.state = OffsetIteratorAsyncValue(
            ref.state.value,
            ref.state.hasMore,
            true,
            doPull,
          );
        }

        return Future.value(iterator.pull()).then((value) {
          value.p(O.map((v) => ref.state = OffsetIteratorAsyncValue(
                AsyncValue.data(v),
                iterator.hasMore(),
                false,
                doPull,
              )));

          return doPull(remaining - 1);
        }).catchError((err, stack) {
          ref.state = OffsetIteratorAsyncValue(
            AsyncValue.error(err, stackTrace: stack),
            iterator.hasMore(),
            false,
            doPull,
          );
        });
      }

      doPull(initialDemand);
      canSetState = true;

      return OffsetIteratorAsyncValue(
        iterator.value.p(O.fold(
          () => const AsyncValue.loading(),
          (v) => AsyncValue.data(v),
        )),
        iterator.hasMore(),
        initialDemand > 0,
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
        ref.state =
            OffsetIteratorValue(O.Some(item), iterator.hasMore(), false);
      }, onDone: () {
        ref.state = OffsetIteratorValue(ref.state.value, false, false);
      });

      ref.onDispose(cancel);

      return OffsetIteratorValue(iterator.value, iterator.hasMore(), true);
    };
