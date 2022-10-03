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
    this.pull,
  ) : super(value, hasMore, pulling);

  factory OffsetIteratorAsyncValue.loading() => OffsetIteratorAsyncValue(
        const AsyncValue.loading(),
        false,
        false,
        () => Future.value(),
      );

  final Future<void> Function() pull;

  OffsetIteratorAsyncValue<B> map<B>(B Function(T a) f) =>
      OffsetIteratorAsyncValue(
        value.whenData(f),
        hasMore,
        pulling,
        pull,
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
      var canSetValue = false;
      var disposed = false;
      ref.onDispose(() => disposed = true);

      bool shouldPullMore(int remaining) =>
          !disposed && remaining > 0 && !iterator.drained;

      late Future<void> Function() maybePull;

      Future<void> doPull(int remaining) =>
          Future.value(iterator.pull()).then((value) {
            if (disposed) return null;

            final pullMore = shouldPullMore(remaining - 1);

            if (canSetValue) {
              ref.state = OffsetIteratorAsyncValue(
                value
                    .p(O.map(AsyncValue.data))
                    .p(O.alt(() => O.fromNullable(ref.state.value)))
                    .p(O.getOrElse(AsyncValue.loading)),
                iterator.hasMore(),
                pullMore,
                maybePull,
              );
            }

            return pullMore ? doPull(remaining - 1) : Future.value();
          }).catchError((err, stack) {
            if (disposed) return null;

            ref.state = OffsetIteratorAsyncValue(
              AsyncValue.error(err, stackTrace: stack),
              iterator.hasMore(),
              false,
              maybePull,
            );
          });

      maybePull = () {
        if (!shouldPullMore(1)) return Future.value();
        return doPull(1);
      };

      if (shouldPullMore(initialDemand)) {
        doPull(initialDemand);
      }

      canSetValue = true;

      return OffsetIteratorAsyncValue(
        iterator.value.p(O.fold(
          () => const AsyncValue.loading(),
          (v) => AsyncValue.data(v),
        )),
        iterator.hasMore(),
        initialDemand > 0,
        maybePull,
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
