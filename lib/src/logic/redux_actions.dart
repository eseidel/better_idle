import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/services/toast_service.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/inventory.dart';

export 'package:async_redux/async_redux.dart';

class UpdateActivityProgressAction extends ReduxAction<GlobalState> {
  UpdateActivityProgressAction({required this.now});
  final DateTime now;

  @override
  GlobalState reduce() {
    final ticks = ticksFromDuration(now.difference(state.updatedAt));
    final builder = StateUpdateBuilder(state);

    consumeTicksForAllSystems(builder, ticks);

    final changes = builder.changes;
    final newState = builder.build();
    if (changes.isEmpty) {
      return newState;
    }

    // If timeAway exists, accumulate changes into it for the dialog to display.
    // The dialog is showing these changes, so don't show toast.
    // If timeAway is null, show toast normally.
    final existingTimeAway = state.timeAway;
    if (existingTimeAway != null) {
      // timeAway should never be empty
      assert(
        !existingTimeAway.changes.isEmpty,
        'timeAway should never be empty',
      );
      // so if it exists, the dialog is showing and we should suppress toasts.
      final timeAway = existingTimeAway.mergeChanges(changes);
      // Don't show toast - dialog shows changes
      return newState.copyWith(timeAway: timeAway);
    } else {
      // No timeAway - show toast normally
      toastService.showToast(changes);
      return newState;
    }
  }
}

class ToggleActionAction extends ReduxAction<GlobalState> {
  ToggleActionAction({required this.action});
  final Action action;
  @override
  GlobalState reduce() {
    // If the action is already running, stop it
    if (state.activeAction?.name == action.name) {
      return state.clearAction();
    }
    // Otherwise, start this action, which will clear any other active action.
    return state.startAction(action);
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
    final (timeAway, newState) = consumeManyTicks(state, ticks);
    this.timeAway = timeAway;
    return newState;
  }
}

/// Calculates time away from pause and processes it,
/// merging with existing timeAway if present.
class ResumeFromPauseAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    final now = DateTime.timestamp();
    final duration = now.difference(state.updatedAt);
    final ticks = ticksFromDuration(duration);
    final (newTimeAway, newState) = consumeManyTicks(
      state,
      ticks,
      endTime: now,
    );
    final timeAway = newTimeAway.maybeMergeInto(state.timeAway);
    // Set timeAway on state if it has changes - empty timeAway should be null
    return newState.copyWith(
      timeAway: timeAway.changes.isEmpty ? null : timeAway,
    );
  }
}

/// Clears the welcome back dialog by removing timeAway from state.
class DismissWelcomeBackDialogAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    return state.clearTimeAway();
  }
}

/// Sells a specified quantity of an item.
class SellItemAction extends ReduxAction<GlobalState> {
  SellItemAction({required this.item, required this.count});
  final Item item;
  final int count;

  @override
  GlobalState reduce() {
    return state.sellItem(ItemStack(item, count: count));
  }
}

/// Purchases a bank slot from the shop.
class PurchaseBankSlotAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    final cost = state.shop.nextBankSlotCost();
    if (state.gp < cost) {
      throw Exception(
        'Not enough GP to purchase bank slot. Need $cost, have ${state.gp}',
      );
    }
    return state.copyWith(
      gp: state.gp - cost,
      shop: state.shop.copyWith(bankSlots: state.shop.bankSlots + 1),
    );
  }
}
