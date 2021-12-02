library offset_iterator_builder;

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:offset_iterator/offset_iterator.dart';

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
    this.startOffset,
  }) : super(key: key);

  final OffsetIterator<T> iterator;
  final OffsetWidgetBuilder<T> builder;
  final int initialDemand;
  final int? startOffset;

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
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant OffsetIteratorBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.iterator != widget.iterator) {
      _subscribe();
    }
  }

  void _subscribe() {
    _offset = widget.startOffset ?? iterator.offset;
    if (_offset < iterator.earliestAvailableOffset) {
      _offset = iterator.earliestAvailableOffset;
    }

    iterator.valueAt(_offset).map((v) => _handleData(some(v)));
    _initialDemand(widget.initialDemand);
  }

  void _initialDemand(int remaining) {
    if (remaining <= 0) return;
    _demand().then((_) => _initialDemand(remaining - 1));
  }

  Future<void> _demand() async {
    if (iterator.isLastOffset(_offset)) return;

    if (_offset < iterator.earliestAvailableOffset) {
      _offset = iterator.earliestAvailableOffset;
    }

    try {
      final item = await iterator.pull(_offset);
      _offset++;
      _handleData(item);
    } catch (err) {
      _handleError(err);
    }
  }

  Future<void> _handleData(Option<T> item) async {
    if (_disposed) return;

    final hasMore = iterator.hasMore(_offset);
    final newState = item.match<OffsetIteratorValue<T>>(
      (item) => Either.right(tuple2(some(item), hasMore)),
      () => state.map((s) => s.copyWith(value2: hasMore)),
    );

    if (newState != state) {
      setState(() {
        state = newState;
      });
    }

    if (hasMore && item.isNone()) {
      await _demand();
    }
  }

  void _handleError(dynamic err) {
    if (_disposed) return;
    setState(() {
      state = Either.left(err);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, state, () => Future.microtask(_demand));

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
