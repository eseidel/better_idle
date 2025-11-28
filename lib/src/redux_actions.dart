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
    final newState = builder.build();

    // If dialog is open, accumulate changes into timeAway
    if (state.timeAway != null && !changes.isEmpty) {
      final mergedChanges = state.timeAway!.changes.merge(changes);
      final updatedTimeAway = TimeAway(
        duration: state.timeAway!.duration,
        activeSkill: state.timeAway!.activeSkill,
        changes: mergedChanges,
      );
      // Don't show toast - dialog shows changes
      return newState.copyWith(timeAway: updatedTimeAway);
    } else {
      // No dialog open - show toast as before
      if (!changes.isEmpty) {
        toastService.showToast(changes);
      }
      return newState;
    }
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

/// Calculates time away from pause and processes it, merging with existing timeAway if present.
class ResumeFromPauseAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    // IMPORTANT: Calculate duration at the very start, before any state changes
    final duration = DateTime.timestamp().difference(state.updatedAt);
    final ticks = ticksFromDuration(duration);

    // Process the ticks (inline AdvanceTicksAction logic)
    final action = state.activeAction;
    TimeAway newTimeAway;
    GlobalState newState;

    if (action == null) {
      // No activity active, return empty changes
      newTimeAway = TimeAway.empty();
      newState = state;
    } else {
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, ticks);
      newTimeAway = TimeAway(
        duration: Duration(milliseconds: ticks * tickDuration.inMilliseconds),
        activeSkill: state.activeSkill,
        changes: builder.changes,
      );
      newState = builder.build();
    }

    // Merge with existing timeAway if present
    if (state.timeAway == null) {
      // First resume - store new TimeAway
      return newState.copyWith(timeAway: newTimeAway);
    } else {
      // Dialog still open - merge changes, keep original duration and activeSkill
      final mergedChanges = state.timeAway!.changes.merge(newTimeAway.changes);
      final mergedTimeAway = TimeAway(
        duration: state.timeAway!.duration, // Keep original duration
        activeSkill: state.timeAway!.activeSkill, // Keep original activeSkill
        changes: mergedChanges,
      );
      return newState.copyWith(timeAway: mergedTimeAway);
    }
  }
}

/// Clears the welcome back dialog by removing timeAway from state.
class DismissWelcomeBackDialogAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    return state.copyWith(timeAway: null);
  }
}
