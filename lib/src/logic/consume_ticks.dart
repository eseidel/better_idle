import 'dart:math';

import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/data/xp.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/inventory.dart';
import 'package:better_idle/src/types/time_away.dart';

export 'package:async_redux/async_redux.dart';

export '../types/time_away.dart';

/// Calculates the amount of mastery XP gained per action from raw values.
/// Derived from https://wiki.melvoridle.com/w/Mastery.
int calculateMasteryXpPerAction({
  required int unlockedActions,
  required int playerTotalMasteryForSkill,
  required int totalMasteryForSkill,
  required int itemMasteryLevel,
  required int totalItemsInSkill,
  required double actionSeconds, // In seconds
  required double bonus, // e.g. 0.1 for +10%
}) {
  // We don't currently have a way to get the "total mastery for skill" value,
  // so we're not using the mastery portion of the formula.
  // final masteryPortion =
  //     unlockedActions * (playerTotalMasteryForSkill / totalMasteryForSkill);
  final itemPortion = itemMasteryLevel * (totalItemsInSkill / 10);
  // final baseValue = masteryPortion + itemPortion;
  final baseValue = itemPortion;
  return max(1, baseValue * actionSeconds * 0.5 * (1 + bonus)).toInt();
}

/// Returns the amount of mastery XP gained per action.
// TODO(eseidel): Take a duration instead of using maxDuration?
int masteryXpPerAction(GlobalState state, Action action) {
  final skillState = state.skillState(action.skill);
  final actionState = state.actionState(action.name);
  final actionMasteryLevel = levelForXp(actionState.masteryXp);
  final itemsInSkill = actionRegistry.forSkill(action.skill).length;
  return calculateMasteryXpPerAction(
    unlockedActions: state.unlockedActionsCount(action.skill),
    actionSeconds: action.maxDuration.inSeconds.toDouble(),
    playerTotalMasteryForSkill: skillState.xp,
    totalMasteryForSkill: skillState.masteryXp,
    itemMasteryLevel: actionMasteryLevel,
    totalItemsInSkill: itemsInSkill,
    bonus: 0,
  );
}

class StateUpdateBuilder {
  StateUpdateBuilder(this._state);

  GlobalState _state;
  Changes _changes = const Changes.empty();

  GlobalState get state => _state;

  void setActionProgress(Action action, {required int remainingTicks}) {
    _state = _state.updateActiveAction(
      action.name,
      remainingTicks: remainingTicks,
    );
  }

  void restartCurrentAction(Action action, {Random? random}) {
    // This shouldn't be able to start a *new* action, only restart the current.
    _state = _state.startAction(action, random: random ?? Random());
  }

  /// Adds inventory if there's space. Returns true if successful.
  /// If inventory is full and the item is new, the item is dropped and
  /// tracked in dropped items.
  bool addInventory(ItemStack stack) {
    // Check if inventory is full and this is a new item type
    final isNewItemType = _state.inventory.countOfItem(stack.item) == 0;
    if (_state.isInventoryFull && isNewItemType) {
      // Can't add new item type when inventory is full - drop it
      _changes = _changes.dropping(stack);
      return false;
    }

    // Add the item to inventory (either new slot available or stacking)
    _state = _state.copyWith(inventory: _state.inventory.adding(stack));
    _changes = _changes.adding(stack);
    return true;
  }

  void removeInventory(ItemStack stack) {
    _state = _state.copyWith(inventory: _state.inventory.removing(stack));
    _changes = _changes.removing(stack);
  }

  void addSkillXp(Skill skill, int amount) {
    final oldXp = _state.skillState(skill).xp;
    final oldLevel = levelForXp(oldXp);

    _state = _state.addSkillXp(skill, amount);
    _changes = _changes.addingSkillXp(skill, amount);

    final newXp = _state.skillState(skill).xp;
    final newLevel = levelForXp(newXp);

    // Track level changes
    if (newLevel > oldLevel) {
      _changes = _changes.addingSkillLevel(skill, oldLevel, newLevel);
    }
  }

  void addSkillMasteryXp(Skill skill, int amount) {
    _state = _state.addSkillMasteryXp(skill, amount);
    // Skill Mastery XP is not tracked in the changes object.
  }

  void addActionMasteryXp(String actionName, int amount) {
    _state = _state.addActionMasteryXp(actionName, amount);
    // Action Mastery XP is not tracked in the changes object.
    // Probably getting to 99 is?
  }

  void clearAction() {
    _state = _state.clearAction();
  }

  GlobalState build() => _state;

  Changes get changes => _changes;
}

class _Progress {
  const _Progress(this.action, this.remainingTicks, this.totalTicks);
  final Action action;
  final int remainingTicks;
  final int totalTicks;

  // Computed getter for convenience
  int get progressTicks => totalTicks - remainingTicks;
}

class XpPerAction {
  const XpPerAction({required this.xp, required this.masteryXp});
  final int xp;
  final int masteryXp;
  int get masteryPoolXp => max(1, (0.25 * masteryXp).toInt());
}

XpPerAction xpPerAction(GlobalState state, Action action) {
  return XpPerAction(
    xp: action.xp,
    masteryXp: masteryXpPerAction(state, action),
  );
}

/// Completes an action, consuming inputs, adding outputs, and awarding XP.
/// Returns true if the action can repeat (no items were dropped).
bool completeAction(
  StateUpdateBuilder builder,
  Action action, {
  Random? random,
}) {
  final rng = random ?? Random();
  var canRepeatAction = true;

  // Consume required items
  for (final requirement in action.inputs.entries) {
    final item = itemRegistry.byName(requirement.key);
    builder.removeInventory(ItemStack(item, count: requirement.value));
  }

  // Process all drops (action-level, skill-level, and global)
  for (final drop in dropsRegistry.allDropsForAction(action)) {
    if (drop.rate >= 1.0 || rng.nextDouble() < drop.rate) {
      final success = builder.addInventory(drop.toItemStack());
      if (!success) {
        // Item was dropped, can't repeat action
        canRepeatAction = false;
      }
    }
  }
  final perAction = xpPerAction(builder.state, action);

  builder
    ..addSkillXp(action.skill, perAction.xp)
    ..addActionMasteryXp(action.name, perAction.masteryXp)
    ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp);

  return canRepeatAction;
}

/// Consumes a specified number of ticks and updates the state.
void consumeTicks(StateUpdateBuilder builder, Tick ticks, {Random? random}) {
  final state = builder.state;
  final startingAction = state.activeAction;
  if (startingAction == null) {
    return;
  }
  // The active action can never change during this loop other than to
  // be cleared. So we can just use the starting action name.
  final action = actionRegistry.byName(startingAction.name);
  var ticksToConsume = ticks;
  final rng = random ?? Random();

  while (ticksToConsume > 0) {
    final currentAction = builder.state.activeAction;
    if (currentAction == null || currentAction.name != startingAction.name) {
      break;
    }

    final before = _Progress(
      action,
      currentAction.remainingTicks,
      currentAction.totalTicks,
    );
    final ticksToApply = min(ticksToConsume, before.remainingTicks);
    final newRemainingTicks = before.remainingTicks - ticksToApply;
    ticksToConsume -= ticksToApply;
    builder.setActionProgress(action, remainingTicks: newRemainingTicks);

    if (newRemainingTicks <= 0) {
      final canRepeat = completeAction(builder, action, random: rng);

      // Reset progress for the *current* activity.
      if (builder.state.activeAction?.name != startingAction.name) {
        throw Exception('Active action changed during consumption?');
      }

      // Start the action again if we can and it's safe to repeat.
      // If items were dropped, stop the action to avoid further drops.
      if (canRepeat && builder.state.canStartAction(action)) {
        builder.restartCurrentAction(action, random: rng);
      } else {
        // Otherwise, clear the action and break out of the loop.
        builder.clearAction();
        break;
      }
    }
  }
}

/// Consumes a specified number of ticks and returns the changes.
(TimeAway, GlobalState) consumeManyTicks(
  GlobalState state,
  Tick ticks, {
  DateTime? endTime,
}) {
  final action = state.activeAction;
  if (action == null) {
    // No activity active, return empty changes
    return (TimeAway.empty(), state);
  }
  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, ticks);
  final startTime = state.updatedAt;
  final calculatedEndTime =
      endTime ??
      startTime.add(
        Duration(milliseconds: ticks * tickDuration.inMilliseconds),
      );
  final timeAway = TimeAway(
    startTime: startTime,
    endTime: calculatedEndTime,
    activeSkill: state.activeSkill,
    activeAction: actionRegistry.byName(action.name),
    changes: builder.changes,
  );
  return (timeAway, builder.build());
}
