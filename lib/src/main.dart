library states;

import 'package:meta/meta.dart';

part 'states/meta.dart';
part 'states/transition.dart';


typedef StatesTransitionFunction = void Function(StatesTransition transition);

class States extends IStates {
  static const String DISPOSE = 'states_reserved_action_dispose';

  static int _INDEX = 0;

  String id;

  String _lockKey;
  bool get locked => _lockKey != null;
  List<StatesTransition> get all => _transitions.map((e) => e);
  /// What is the current state?
  ///
  /// @return The current state.
  String get current => _currentStateMeta != null ? _currentStateMeta.name : null;

  /// Create a state machine and populate with states
  States({ this.id = null }) {
    ++_INDEX;
    id = id ?? 'states_$_INDEX';
  }

  final List<StatesTransition> _transitions = List<StatesTransition>();
  final List<StatesMeta> _metas = List<StatesMeta>();
  final Map<String, StatesTransitionFunction> _subscribers = Map<String, StatesTransitionFunction>();

  StatesMeta _currentStateMeta;
  void _changeCurrentStateWithTransition(StatesTransition transition, {bool run = true}) {
    if (run && transition.callback != null) transition.callback(transition);
    _currentStateMeta = transition.to;
    _subscribers.values.forEach((s) => s(transition));
  }

  /// Does an action exist in the state machine?
  ///
  /// @param action The action in question.
  /// @return True if the action exists, false if it does not.
  bool has({
    String action,
    String state,
    bool conform = true
  }) {
    var result = false;
    bool stateActionExists = false;
    bool stateNameExists = false;

    if ( action != null ) {
      stateActionExists = _findStateTransitionByAction( action ) != null;
    }
    else stateActionExists = state != null;

    if ( state != null ) {
      stateNameExists = _findStateMetaByState( state ) != null;
    }
    else stateNameExists = stateActionExists;

    result = conform ?
      (stateActionExists && stateNameExists) :
      (stateActionExists || stateNameExists);

    return result;
  }

  /// Add a valid link between two states. The state machine can then move between
  ///
  /// @param fromState State you want to move from.
  /// @param toState State you want to move to.
  /// @param action Action that when performed will move from the from state to the to state.
  /// @param handler Optional method that gets called when moving between these two states.
  /// @return true if link was added, false if it was not.
  StatesTransition when({
    @required String from,
    @required String to,
    @required String on,
    StatesTransitionFunction run
  }) {
    if (locked) return null;

    StatesMeta fromStateMeta;
    StatesMeta toStateMeta;
    /// can't have duplicate actions
    for ( StatesTransition stateAction in _transitions ) {
      final actionAlreadyRegistered =
        stateAction.from.name == from &&
        stateAction.to.name == to &&
        stateAction.callback == run &&
        stateAction.action == on;

      if (actionAlreadyRegistered) return null;
    }

    fromStateMeta = _findStateMetaByState( from );
    if ( fromStateMeta == null ) {
      fromStateMeta = add( from );
    }

    toStateMeta = _findStateMetaByState( to );
    if ( toStateMeta == null ) {
      toStateMeta = add( to );
    }

    final st = StatesTransition(
      fromStateMeta,
      toStateMeta,
      on,
      run
    );
    _transitions.add( st );

    return st;
  }

  String subscribe( StatesTransitionFunction func, { bool single = false }) {
    if (single && _subscribers.values.any((s) => s == func)) return null;
    final subscriptionKey = '_ssk${_subscribers.length}${DateTime.now().toString()}';
    _subscribers[subscriptionKey] = func;
    return subscriptionKey;
  }

  bool unsubscribe( String subscriptionKey ) {
    final result = _subscribers.keys.contains(subscriptionKey);
    if (result) _subscribers.remove(subscriptionKey);
    return result;
  }

  /// Adds a new state to the state machine.
  ///
  /// @param newState The new state to add.
  /// @return True is teh state was added, false if it was not.
  StatesMeta add( String state ) {
    if (locked) return null;
    /// can't have duplicate states
    if ( has( state: state )) return null;
    final stateMeta = StatesMeta( state );
    _metas.add( stateMeta );
    /// if no states exist set current state to first state
    if ( _metas.length == 1 ) _currentStateMeta = stateMeta;
    return stateMeta;
  }

  /// Move from the current state to another state.
  ///
  /// @param toState New state to try and move to.
  /// @param performAction Should execute action function or not, default true.
  /// @return True if the state machine has moved to this new state, false if it was unable to do so.
  bool change( { @required String to, bool run = true } ) {
    if ( !has( state: to )) return false;

    for ( var transition in _transitions ) {
      if ( transition.from == _currentStateMeta && transition.to.name == to ) {
        _changeCurrentStateWithTransition(transition, run: run);
        return true;
      }
    }

    return false;
  }

  /// Change the current state by performing an action.
  ///
  /// @param action The action to perform.
  /// @return True if the action was able to be performed and the state machine moved to a new state, false if the action was unable to be performed.
  bool run( String action ) {
    for ( var transition in _transitions ) {
      if ( transition.from == _currentStateMeta
        && action == transition.action ) {
        _changeCurrentStateWithTransition(transition);
        return true;
      }
    }
    return false;
  }

  StatesTransition get( String action ) {
    for ( var stateAction in _transitions ) {
      if ( action == stateAction.action ) {
        return stateAction;
      }
    }
    return null;
  }

  void lock({ @required String key }) {
    _lockKey = key;
  }

  void unlock({ @required String key }) {
    if (_lockKey == key) _lockKey = null;
  }

  /// Go back to the initial starting state
  void reset() {
    _currentStateMeta = _metas.isNotEmpty ? _metas[0] : null;
  }

  void dispose() {
    _currentStateMeta = null;
    for ( var action in _transitions ) {
      action.dispose();
    }
    final disposeTransition = StatesTransition(_currentStateMeta, null, DISPOSE);
    for ( var key in _subscribers.keys ) {
      var sub = _subscribers[key];
      sub(disposeTransition);
    }
    _subscribers.clear();
    _transitions.clear();
    _metas.clear();
    _INDEX = 0;
  }

  /// What are the valid actions you can perform from the current state?
  ///
  /// @return An array of actions.
  List<StatesTransition> actions({ String from }) {
    StatesMeta base = from == null ? current : _findStateMetaByState(from);
    List<StatesTransition> actions = [];
    for ( var action in _transitions ) {
      if ( action.from == base ) {
        actions.add(action);
      }
    }
    return actions;
  }

  /// What are the valid states you can get to from the current state?
  ///
  /// @return An array of states.
  List<StatesMeta> metas({ String from }) {
    StatesMeta base = from == null ? current : _findStateMetaByState(from);
    List<StatesMeta> metas = [];
    for ( var action in _transitions ) {
      if ( action.from == base ) {
        metas.add(action.to);
      }
    }
    return metas;
  }

  StatesMeta _findStateMetaByState(String state) {
    for ( var stateMeta in _metas ) {
      if ( stateMeta.name == state ) {
        return stateMeta;
      }
    }
    return null;
  }

  StatesTransition _findStateTransitionByAction( String action ) {
    for ( var transition in _transitions ) {
      if ( transition.action == action ) {
        return transition;
      }
    }
    return null;
  }
}

abstract class IStates {
  String get current;
  bool get locked;
  List<StatesTransition> get all;

  List<StatesTransition> actions({String from});
  List<StatesMeta> metas({String from});

  StatesMeta add( String state );
  StatesTransition when({
    String from,
    String to,
    String on,
    StatesTransitionFunction run
  });

  String subscribe(StatesTransitionFunction listener);
  bool unsubscribe(String subscriptionKey);

  bool change({ String to, bool run = true });
  bool has({
    String action,
    String state,
    bool conform = true
  });
  StatesTransition get( String action );
  bool run( String action );

  void reset();
  void dispose();

  void lock({@required String key});
  void unlock({@required String key});
}
