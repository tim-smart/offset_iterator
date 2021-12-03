import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

/// [OffsetIteratorSink] is an [EventSink] that allows you to wait for the data
/// to be consumed.
abstract class OffsetIteratorSink<T> implements EventSink<T> {
  @override
  FutureOr<void> add(T data);

  @override
  FutureOr<void> addError(Object error, [StackTrace? stackTrace]);

  @override
  FutureOr<void> close([Option<T> data]);

  Future<void> flush();
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
  final Option<T> data;
}

enum OffsetIteratorControllerState {
  initialized,
  closed,
}

/// Optional transformation to apply to the wrapper [OffsetIterator]
typedef OffsetIteratorControllerTransform<T> = OffsetIterator<dynamic> Function(
  OffsetIterator<T>,
);

/// [OffsetIteratorController] implements sink behaviour and wraps an
/// [OffsetIterator].
class OffsetIteratorController<T> implements OffsetIteratorSink<T> {
  OffsetIteratorController({
    this.closeOnError = true,
    OffsetIteratorControllerTransform<T>? transform,
  }) {
    final iter = OffsetIterator<T>(init: () {}, process: _process);
    iterator = transform != null ? transform(iter) : iter;
  }

  /// The [OffsetIterator] that is being controlled.
  late final OffsetIterator<dynamic> iterator;

  /// The internal state of the controller.
  OffsetIteratorControllerState get state => _state;
  var _state = OffsetIteratorControllerState.initialized;

  /// If `true`, when `addError` is called, the controller will be closed.
  final bool closeOnError;

  _Item<T>? _nextItem;
  final _buffer = Queue<_Item<T>>();
  Completer<void>? _signal;

  /// Expose the [OffsetIteratorSink] behaviour, which provides a smaller API
  /// surface.
  OffsetIteratorSink<T> get sink => this;

  /// Add data to the sink.
  ///
  /// Will return immediately if the data is ready for consumption.
  /// Otherwise it will return a [Future] that will resolve when the data has
  /// been consumed.
  @override
  FutureOr<void> add(T data) => _add(_Data(data));

  /// Add an error to the sink.
  ///
  /// Like [add], it will return immediately if the error is handled straight
  /// away. Otherwise will return a [Future] that will resolve when the error
  /// has been handled.
  @override
  FutureOr<void> addError(Object error, [StackTrace? stackTrace]) =>
      _add(_Error(error, stackTrace ?? AsyncError.defaultStackTrace(error)));

  /// Close the sink
  ///
  /// Has an optional `data` parameter if you want to close the [OffsetIterator]
  /// with a final item.
  ///
  /// Works the same as [add], except the controller will be closed and no longer
  /// accept new data.
  @override
  FutureOr<void> close([Option<T> data = const None()]) => _add(_Close(data));

  FutureOr<void> _add(_Item<T> item) {
    if (_state == OffsetIteratorControllerState.closed) {
      throw StateError('sink is closed');
    }

    if (item is _Close || (item is _Error && closeOnError)) {
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

  /// Returns a future that waits for the internal [OffsetIterator] to drain.
  @override
  Future<void> flush() => iterator.drain();

  // ==== Below is the internal [OffsetIterator] implementation

  FutureOr<OffsetIteratorState<T>> _process(dynamic acc) {
    if (_nextItem == null) {
      _signal = Completer.sync();
      return _signal!.future.then((_) {
        _signal = null;
        return _handleNext();
      });
    }

    return _handleNext();
  }

  FutureOr<OffsetIteratorState<T>> _handleNext() {
    if (_nextItem is _Error) {
      final error = _assignNextItem() as _Error<T>;

      return OffsetIteratorState(
        acc: null,
        chunk: [],
        hasMore: !closeOnError,
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
      item.data.map(chunk.add);
      item.completer.complete();
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

extension PipeExtension<T> on OffsetIterator<T> {
  Future<void> pipe(
    OffsetIteratorSink<T> sink, {
    int? startOffset,
  }) async {
    var offset = startOffset ?? this.offset;
    if (offset < earliestAvailableOffset) {
      offset = earliestAvailableOffset - 1;
    }

    while (hasMore(offset)) {
      try {
        final itemFuture = pull(offset);
        final item = itemFuture is Future ? await itemFuture : itemFuture;

        if (item is Some) {
          final addFuture = sink.add((item as Some).value);
          if (addFuture is Future) await addFuture;
        }
      } catch (err) {
        sink.addError(err);
        return await sink.flush();
      }

      offset++;
    }

    sink.close();
    await sink.flush();
  }
}