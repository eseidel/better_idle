import 'consume_ticks.dart';
import 'services/toast_service.dart';
import 'state.dart';

export 'package:async_redux/async_redux.dart';

class StartActionAction extends ReduxAction<GlobalState> {
  StartActionAction({required this.action});
  final Action action;
  @override
  GlobalState reduce() {
    // We need to stop the current activity or wait for it to finish?
    return store.state.startAction(action);
  }
}

class UpdateActivityProgressAction extends ReduxAction<GlobalState> {
  UpdateActivityProgressAction({required this.now});
  final DateTime now;

  @override
  GlobalState reduce() {
    final activity = state.activeAction;
    if (activity == null) {
      throw Exception('No activity to update progress for');
    }
    final ticks = ticksSince(state.updatedAt);
    final builder = StateUpdateBuilder(state);
    consumeTicks(builder, ticks);
    final changes = builder.changes;
    if (!changes.isEmpty) {
      toastService.showToast(changes);
    }
    return builder.build();
  }
}

class StopActionAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    // This might need to either wait for the activity to finish, or cancel it?
    return state.clearAction();
  }
}

/// Advances the game by a specified number of ticks and returns the changes.
/// Unlike UpdateActionProgressAction, this does not show toasts.
class AdvanceTicksAction extends ReduxAction<GlobalState> {
  AdvanceTicksAction({required this.ticks});
  final Tick ticks;

  /// The time away that occurred during this advancement.
  late TimeAway timeAway;

  @override
  GlobalState reduce() {
    final action = state.activeAction;
    if (action == null) {
      // No activity active, return empty changes
      timeAway = TimeAway.empty();
      return state;
    }
    final builder = StateUpdateBuilder(state);
    consumeTicks(builder, ticks);
    timeAway = TimeAway(
      duration: Duration(milliseconds: ticks * tickDuration.inMilliseconds),
      activeSkill: state.activeSkill,
      changes: builder.changes,
    );
    return builder.build();
  }
}
