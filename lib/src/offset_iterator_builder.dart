import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:offset_iterator/src/offset_iterator.dart';

typedef OffsetIteratorValue<T> = Either<dynamic, Tuple2<Option<T>, bool>>;

typedef OffsetWidgetBuilder<T> = Widget Function(
  BuildContext,
  OffsetIteratorValue<T>,
  void Function(),
);

class OffsetIteratorBuilder<T> extends StatefulWidget {
  const OffsetIteratorBuilder({
    Key? key,
    required this.iterator,
    required this.builder,
    this.initialDemand = 1,
  }) : super(key: key);

  final OffsetIterator<T> iterator;
  final OffsetWidgetBuilder<T> builder;
  final int initialDemand;

  @override
  _OffsetIteratorBuilderState<T> createState() =>
      _OffsetIteratorBuilderState<T>();
}

R Function<R>({
  required R Function(dynamic) error,
  required R Function(T, bool) data,
  required R Function() loading,
}) withValue<T>(OffsetIteratorValue<T> value) => <R>({
      required error,
      required data,
      required loading,
    }) =>
        value.match(
          error,
          (s) => s.first.match((v) => data(v, s.second), loading),
        );

class _OffsetIteratorBuilderState<T> extends State<OffsetIteratorBuilder<T>> {
  OffsetIterator<T> get iterator => widget.iterator;
  OffsetIteratorValue<T> state = Either.right(tuple2(none(), true));
  late int _offset;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant OffsetIteratorBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.iterator != widget.iterator) {
      oldWidget.iterator.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _offset = iterator.offset;
    iterator.value
        .map((v) => some(tuple2(v, iterator.offset)))
        .map(_handleData);
    _initialDemand(widget.initialDemand);
  }

  void _initialDemand(int remaining) {
    if (remaining <= 0) return;
    _demand().then((_) => _initialDemand(remaining - 1));
  }

  Future<void> _demand() => iterator.pull(_offset).then((item) {
        _handleData(item);
      }).catchError((err) {
        _handleError(err);
      });

  void _handleData(Option<OffsetIteratorItem<T>> item) {
    final newState = item.match<OffsetIteratorValue<T>>(
      (item) {
        _offset = item.second;
        return Either.right(tuple2(
          some(item.first),
          !iterator.isLastOffset(_offset),
        ));
      },
      () =>
          state.map((s) => s.copyWith(value2: !iterator.isLastOffset(_offset))),
    );

    if (newState == state) return;

    setState(() {
      state = newState;
    });
  }

  void _handleError(dynamic err) {
    setState(() {
      state = Either.left(err);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, state, () => Future.microtask(_demand));

  @override
  void dispose() {
    iterator.cancel();
    super.dispose();
  }
}
