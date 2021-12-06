library state_iterator;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';

export 'package:offset_iterator/offset_iterator.dart';

/// Represents the `add` function passed to a [StateIteratorAction].
typedef StateIteratorAdd<T> = FutureOr<void> Function(T newState);

/// Represents an action passed to a [StateIterator]. It receives the current
/// state and an [StateIteratorAdd] function, and optionally emits new state's.
typedef StateIteratorAction<T> = FutureOr<void> Function(
  T state,
  StateIteratorAdd<T> add,
);

typedef StateIteratorTransform<T> = OffsetIterator<T> Function(
    OffsetIterator<T> parent);

/// A [StateIterator] is a special kind of [OffsetIterator] that consumes
/// [StateIteratorAction]'s, and exposes an iterator that emits the transformed
/// [State]'s.
class StateIterator<State> {
  StateIterator({
    required State initialState,
    StateIteratorTransform<State>? transform,
    bool closeOnError = false,
    String? name,
  }) {
    name ??= 'StateIterator<$State>';

    _actionController = OffsetIteratorController(
      name: '$name._actionController',
      transform: _transformActions,
    );

    _stateController = OffsetIteratorController(
      name: '$name.iterator',
      transform: transform,
      closeOnError: closeOnError,
      seed: () => Some(initialState),
    );
    _state = _stateController.iterator.valueOrNull;

    _actionController.iterator.run();
  }

  late final OffsetIteratorController<StateIteratorAction<State>>
      _actionController;

  late final OffsetIteratorController<State> _stateController;
  late State _state;

  // ==== Public API

  /// The [OffsetIterator<State>] controlled by the [StateIterator].
  /// This is the [OffsetIterator] you use in your application to watch for
  /// state changes.
  OffsetIterator<State> get iterator =>
      _stateController.iterator as OffsetIterator<State>;

  /// Add an [StateIteratorAction] to be processed.
  /// The action will add new [State] to the controlled [iterator].
  FutureOr<void> add(StateIteratorAction<State> action) =>
      _actionController.add(action);

  /// Closes the [StateIterator], so it no longer accepts new actions.
  /// When all the remaining actions have been processed, the exposed [iterator]
  /// will also complete.
  FutureOr<void> close() => _actionController.close();

  // ==== Public API end

  FutureOr<void> _addState(State value) {
    _state = value;
    return _stateController.add(value);
  }

  OffsetIterator<void> _transformActions(
    OffsetIterator<StateIteratorAction<State>> parent,
  ) =>
      OffsetIterator(
        name: parent.toStringWithChild('_transformActions'),
        process: _process(parent),
        cleanup: (_) => _stateController.close(),
      );

  FutureOr<OffsetIteratorState<void>> Function(dynamic) _process(
    OffsetIterator<StateIteratorAction<State>> parent,
  ) =>
      (acc) {
        final futureOr = parent.pull();

        return futureOr is Future
            ? (futureOr as Future<Option<StateIteratorAction<State>>>)
                .then((a) => _handleAction(a, parent.hasMore()))
            : _handleAction(futureOr, parent.hasMore());
      };

  FutureOr<OffsetIteratorState<void>> _handleAction(
    Option<StateIteratorAction<State>> actionOption,
    bool hasMore,
  ) {
    if (actionOption.isNone()) {
      return OffsetIteratorState(hasMore: hasMore);
    }

    final action = (actionOption as Some<StateIteratorAction<State>>).value;

    try {
      final futureOr = action(_state, _addState);

      if (futureOr is Future) {
        return futureOr.catchError((err) {
          // ignore: avoid_print
          print("StateIterator error: $err");
          return null;
        }).then((_) => OffsetIteratorState(hasMore: hasMore));
      }
    } catch (err) {
      // ignore: avoid_print
      print("StateIterator error: $err");
    }

    return OffsetIteratorState(hasMore: hasMore);
  }
}
