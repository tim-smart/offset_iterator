import 'dart:async';
import 'dart:collection';

import 'package:offset_iterator/offset_iterator.dart';

abstract class OffsetIteratorSink<T> implements EventSink<T> {
  @override
  FutureOr<void> add(T data);

  @override
  FutureOr<void> addError(Object error, [StackTrace? stackTrace]);

  @override
  FutureOr<void> close([T? data]);
}

abstract class _Item<T> {
  _Item();
  final completer = Completer<void>.sync();
}

class _Data<T> extends _Item<T> {
  _Data(this.data);
  final T data;
}

class _Error<T> extends _Item<T> {
  _Error(this.error, [this.stackTrace]);
  final dynamic error;
  final StackTrace? stackTrace;
}

class _Close<T> extends _Item<T> {
  _Close(this.data);
  final T? data;
}

enum OffsetIteratorControllerState {
  initialized,
  closed,
}

class OffsetIteratorController<T> implements OffsetIteratorSink<T> {
  OffsetIteratorController({
    this.cancelOnError = true,
  });

  late final iterator = OffsetIterator<T>(
    init: () {},
    process: _process,
  );

  var _state = OffsetIteratorControllerState.initialized;
  OffsetIteratorControllerState get state => _state;

  final bool cancelOnError;

  _Item<T>? _nextItem;
  final _buffer = Queue<_Item<T>>();
  Completer<void>? _signal;

  OffsetIteratorSink<T> get sink => this;

  @override
  FutureOr<void> add(T data) => _add(_Data(data));

  @override
  FutureOr<void> addError(Object error, [StackTrace? stackTrace]) =>
      _add(_Error(error, stackTrace ?? AsyncError.defaultStackTrace(error)));

  @override
  FutureOr<void> close([T? data]) => _add(_Close(data));

  FutureOr<void> _add(_Item<T> item) {
    if (_state == OffsetIteratorControllerState.closed) {
      throw StateError('sink is closed');
    }

    if (item is _Close || (item is _Error && cancelOnError)) {
      _state = OffsetIteratorControllerState.closed;
    }

    if (_nextItem == null) {
      _nextItem = item;
    } else {
      _buffer.add(item);
    }

    if (_signal != null) {
      _signal!.complete();
    }

    return item.completer.isCompleted ? null : item.completer.future;
  }

  FutureOr<OffsetIteratorState<T>> _process(dynamic acc) {
    if (_nextItem == null) {
      _signal = Completer.sync();
      return _signal!.future.then((_) => _handleNext());
    }

    return _handleNext();
  }

  FutureOr<OffsetIteratorState<T>> _handleNext() {
    if (_nextItem is _Error) {
      final error = _assignNextItem() as _Error<T>;

      return OffsetIteratorState(
        acc: null,
        chunk: [],
        hasMore: !cancelOnError,
        error: error.error,
        stackTrace: error.stackTrace,
      );
    }

    final chunk = <T>[];
    while (_nextItem is _Data) {
      final item = _assignNextItem() as _Data<T>;
      chunk.add(item.data);
      item.completer.complete();
    }

    var hasMore = true;
    if (_nextItem is _Close) {
      final item = _assignNextItem() as _Close<T>;
      if (item.data != null) chunk.add(item.data!);
      hasMore = false;
    }

    return OffsetIteratorState(
      acc: null,
      chunk: chunk,
      hasMore: hasMore,
    );
  }

  _Item<T> _assignNextItem() {
    final item = _nextItem!;

    if (_buffer.isEmpty) {
      _nextItem = null;
    } else {
      _nextItem = _buffer.removeFirst();
    }

    return item;
  }
}
