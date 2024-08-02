// ignore_for_file: depend_on_referenced_packages, library_prefixes

library offset_iterator_nucleus;

import 'package:elemental/elemental.dart';
import 'package:offset_iterator/offset_iterator.dart';

export 'package:offset_iterator/offset_iterator.dart';

ReadOnlyAtom<OffsetIterator<T>> iteratorOnlyAtom<T>(
  AtomReader<OffsetIterator<T>> create,
) =>
    atom((get) {
      final iterator = create(get);
      get.onDispose(iterator.cancel);
      return iterator;
    });

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
  int get hashCode => Object.hash(runtimeType, value, hasMore, pulling);
}

class OffsetIteratorFutureValue<T> extends OffsetIteratorValue<FutureValue<T>> {
  const OffsetIteratorFutureValue(
    FutureValue<T> value,
    bool hasMore,
    bool pulling,
    this.pull,
  ) : super(value, hasMore, pulling);

  factory OffsetIteratorFutureValue.loading() => OffsetIteratorFutureValue(
        const FutureValue.loading(),
        false,
        false,
        () => Future.value(),
      );

  final Future<void> Function() pull;

  OffsetIteratorFutureValue<B> map<B>(B Function(T a) f) =>
      OffsetIteratorFutureValue(
        value.map(f),
        hasMore,
        pulling,
        pull,
      );

  bool get isLoading => pulling || value.isLoading;

  Option<T> get data => Option.fromNullable(value.dataOrNull);
}

OffsetIteratorFutureValue<T> iteratorFutureValue<T>(
  AtomContext<OffsetIteratorFutureValue<T>> get,
  OffsetIterator<T> iterator, {
  int initialDemand = 1,
}) {
  var disposed = false;
  get.onDispose(() => disposed = true);

  bool shouldPullMore(int remaining) =>
      !disposed && remaining > 0 && !iterator.drained;

  late Future<void> Function() maybePull;

  Future<void> doPull(int remaining) =>
      Future.value(iterator.pull()).then((value) {
        if (disposed) return null;

        final pullMore = shouldPullMore(remaining - 1);

        get.setSelf(OffsetIteratorFutureValue(
          value
              .map(FutureValue.data)
              .alt(() => Option.fromNullable(get.self()?.value))
              .getOrElse(FutureValue.loading),
          iterator.hasMore(),
          pullMore,
          maybePull,
        ));

        return pullMore ? doPull(remaining - 1) : Future.value();
      }).catchError((err, stack) {
        if (disposed) return null;

        get.setSelf(OffsetIteratorFutureValue(
          FutureValue.error(err, stack),
          iterator.hasMore(),
          false,
          maybePull,
        ));

        return null;
      });

  maybePull = () {
    if (!shouldPullMore(1)) return Future.value();
    return doPull(1);
  };

  if (shouldPullMore(initialDemand)) {
    doPull(initialDemand);
  }

  return OffsetIteratorFutureValue(
    iterator.value.match(
      () => const FutureValue.loading(),
      (v) => FutureValue.data(v),
    ),
    iterator.hasMore(),
    initialDemand > 0,
    maybePull,
  );
}

typedef IteratorAtom<T>
    = AtomWithParent<OffsetIteratorFutureValue<T>, Atom<OffsetIterator<T>>>;

/// Pulls an [OffsetIterator] on demand, and exposes the most recently pulled
/// [OffsetIteratorFutureValue].
IteratorAtom<T> iteratorAtom<T>(
  AtomReader<OffsetIterator<T>> create, {
  int initialDemand = 1,
}) =>
    atomWithParent(
      iteratorOnlyAtom(create),
      (get, parent) => iteratorFutureValue(
        get,
        get(parent),
        initialDemand: initialDemand,
      ),
    );

/// Listens to an [OffsetIterator], and updates the exposed
/// [OffsetIteratorValue] whenever it changes.
AtomWithParent<OffsetIteratorValue<Option<T>>, Atom<OffsetIterator<T>>>
    iteratorLatestAtom<T>(AtomReader<OffsetIterator<T>> create) =>
        atomWithParent(iteratorOnlyAtom(create), (get, parent) {
          final iterator = get(parent);
          var value = iterator.value;

          get.onDispose(iterator.listen((item) {
            value = Option.of(item);
            get.setSelf(OffsetIteratorValue(
              value,
              iterator.hasMore(),
              false,
            ));
          }, onDone: () {
            get.setSelf(OffsetIteratorValue(
              value,
              false,
              false,
            ));
            value = const None();
          }));

          return OffsetIteratorValue(
            value,
            iterator.hasMore(),
            true,
          );
        });
