library offset_iterator_builder;

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:fpdt/either.dart' as E;
import 'package:fpdt/function.dart';
import 'package:fpdt/option.dart' as O;
import 'package:fpdt/tuple.dart';
import 'package:offset_iterator/offset_iterator.dart';

typedef OffsetIteratorValue<T> = E.Either<dynamic, Tuple2<Option<T>, bool>>;

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
        value.p(E.fold(
          error,
          (s) => s.first.p(O.fold(
            loading,
            (v) => data(v, s.second),
          )),
        ));

class _OffsetIteratorBuilderState<T> extends State<OffsetIteratorBuilder<T>> {
  OffsetIterator<T> get iterator => widget.iterator;
  OffsetIteratorValue<T> state = E.right(tuple2(none(), true));
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
    iterator.value.p(O.map((v) => _handleData(some(v))));
    _initialDemand(widget.initialDemand);
  }

  void _initialDemand(int remaining) {
    if (remaining <= 0) return;
    _demand().then((_) => _initialDemand(remaining - 1));
  }

  Future<void> _demand() async {
    if (iterator.drained) return;

    try {
      _handleData(await iterator.pull());
    } catch (err) {
      _handleError(err);
    }
  }

  Future<void> _handleData(Option<T> item) async {
    if (_disposed) return;

    final hasMore = iterator.hasMore();
    final newState = item.p(O.fold(
      () => state.p(E.map((s) => s.copyWith(second: hasMore))),
      (item) => E.right(tuple2(some(item), hasMore)),
    ));

    if (newState != state) {
      setState(() {
        state = newState;
      });
    }

    if (hasMore && O.isNone(item)) {
      await _demand();
    }
  }

  void _handleError(dynamic err) {
    if (_disposed) return;
    setState(() {
      state = E.left(err);
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
