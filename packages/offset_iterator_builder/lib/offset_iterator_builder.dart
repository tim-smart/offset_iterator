library offset_iterator_builder;

import 'dart:async';
import 'package:elemental/elemental.dart';
import 'package:flutter/widgets.dart';
import 'package:offset_iterator/offset_iterator.dart';

typedef OffsetIteratorValue<T> = Either<dynamic, (Option<T>, bool)>;

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
          (s) => s.$1.match(
            loading,
            (v) => data(v, s.$2),
          ),
        );

class _OffsetIteratorBuilderState<T> extends State<OffsetIteratorBuilder<T>> {
  OffsetIterator<T> get iterator => widget.iterator;
  OffsetIteratorValue<T> state = Either.right((const Option.none(), true));
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
    iterator.value.map((v) => _handleData(Option.of(v)));
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
    final newState = item.match(
      () => state.map((s) => (s.$1, hasMore)),
      (item) => Either.right((Option.of(item), hasMore)),
    );

    if (newState != state) {
      setState(() {
        state = newState;
      });
    }

    if (hasMore && item is None) {
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
