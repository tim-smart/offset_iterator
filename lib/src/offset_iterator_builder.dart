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

  final OffsetIterator<T, dynamic> iterator;
  final OffsetWidgetBuilder<T> builder;
  final int initialDemand;

  @override
  _OffsetIteratorBuilderState<T> createState() =>
      _OffsetIteratorBuilderState<T>();
}

R withValue<T, R>(
  OffsetIteratorValue<T> value, {
  required R Function(dynamic) error,
  required R Function(T, bool) data,
  required R Function() loading,
}) =>
    value.match(error, (s) => s.first.match((v) => data(v, s.second), loading));

class _OffsetIteratorBuilderState<T> extends State<OffsetIteratorBuilder<T>> {
  OffsetIterator<T, dynamic> get iterator => widget.iterator;
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

  Future<void> _demand() => iterator
      .pull(_offset)
      .then(_handleData)
      .catchError((err) => _handleError(err));

  void _handleData(Option<OffsetIteratorItem<T>> item) {
    _offset = item.map((v) => v.second).getOrElse(() => _offset);

    setState(() {
      state = Either.right(tuple2(
        item.map((v) => v.first),
        item
            .map((v) => iterator.isLastOffset(v.second))
            .getOrElse(() => iterator.hasMore),
      ));
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
