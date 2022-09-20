library offset_iterator_nucleus;

import 'package:fpdt/fpdt.dart';
import 'package:fpdt/option.dart' as O;
import 'package:nucleus/nucleus.dart';
import 'package:offset_iterator/offset_iterator.dart';

export 'package:offset_iterator/offset_iterator.dart';

Atom<OffsetIterator<T>> iteratorOnlyAtom<T>(
        AtomReader<OffsetIterator<T>> create) =>
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
  int get hashCode => Object.hash(runtimeType, value, hasMore);
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

  Option<T> get data => O.fromNullable(value.dataOrNull);
}

OffsetIteratorFutureValue<T> iteratorFutureValue<T>(
  AtomContext<OffsetIteratorFutureValue<T>> get,
  Atom<OffsetIterator<T>> parent, {
  int initialDemand = 1,
}) {
  final iterator = get(parent);

  var disposed = false;
  get.onDispose(() => disposed = true);

  bool shouldPullMore(int remaining) =>
      !disposed && remaining > 0 && !iterator.drained;

  late Future<void> Function() maybePull;

  Future<void> doPull(int remaining) =>
      Future.value(iterator.pull()).then((value) {
        final pullMore = shouldPullMore(remaining - 1);

        get.setSelf(OffsetIteratorFutureValue(
          value
              .p(O.map(FutureValue.data))
              .p(O.alt(() => O.fromNullable(get.previousValue?.value)))
              .p(O.getOrElse(FutureValue.loading)),
          iterator.hasMore(),
          pullMore,
          maybePull,
        ));

        return pullMore ? doPull(remaining - 1) : Future.value();
      }).catchError((err, stack) {
        get.setSelf(OffsetIteratorFutureValue(
          FutureValue.error(err, stack),
          iterator.hasMore(),
          false,
          maybePull,
        ));
      });

  maybePull = () {
    if (!shouldPullMore(1)) return Future.value();
    return doPull(1);
  };

  if (shouldPullMore(initialDemand)) {
    doPull(initialDemand);
  }

  return OffsetIteratorFutureValue(
    iterator.value.p(O.fold(
      () => const FutureValue.loading(),
      (v) => FutureValue.data(v),
    )),
    iterator.hasMore(),
    initialDemand > 0,
    maybePull,
  );
}

/// Pulls an [OffsetIterator] on demand, and exposes the most recently pulled
/// [OffsetIteratorFutureValue].
AtomWithParent<OffsetIteratorFutureValue<T>, Atom<OffsetIterator<T>>>
    iteratorAtom<T>(
  AtomReader<OffsetIterator<T>> create, {
  int initialDemand = 1,
}) =>
        atomWithParent(
          iteratorOnlyAtom(create),
          (get, parent) => iteratorFutureValue(
            get,
            parent,
            initialDemand: initialDemand,
          ),
        );

/// Listens to an [OffsetIterator], and updates the exposed
/// [OffsetIteratorValue] whenever it changes.
AtomWithParent<OffsetIteratorValue<Option<T>>, Atom<OffsetIterator<T>>>
    iteratorLatestAtom<T>(AtomReader<OffsetIterator<T>> create) =>
        atomWithParent(iteratorOnlyAtom(create), (get, parent) {
          final iterator = get(parent);

          get.onDispose(iterator.listen((item) {
            get.setSelf(
                OffsetIteratorValue(O.Some(item), iterator.hasMore(), false));
          }, onDone: () {
            get.setSelf(
                OffsetIteratorValue(get.previousValue!.value, false, false));
          }));

          return OffsetIteratorValue(iterator.value, iterator.hasMore(), true);
        });
