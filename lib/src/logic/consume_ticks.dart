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

/// Gets the current HP of a resource node.
int getCurrentHp(Action action, ActionState actionState, int masteryLevel) {
  if (action.resourceProperties == null) {
    throw Exception('Action does not have resource properties');
  }

  final maxHp = action.resourceProperties!.maxHpForMasteryLevel(masteryLevel);
  return max(0, maxHp - actionState.totalHpLost);
}

/// Returns true if the node is currently depleted and not yet respawned.
bool isNodeDepleted(ActionState actionState) {
  return actionState.respawnTicksRemaining != null &&
      actionState.respawnTicksRemaining! > 0;
}

/// Applies HP regeneration and respawn countdowns to resource-based actions.
/// Returns updated ActionState with HP regenerated and/or respawn progressed.
ActionState applyResourceTicks(ActionState actionState, Tick ticksElapsed) {
  var newState = actionState;
  var ticksRemaining = ticksElapsed;

  // If node is depleted, count down respawn timer
  if (newState.respawnTicksRemaining != null) {
    final respawnTicks = newState.respawnTicksRemaining!;
    if (ticksRemaining >= respawnTicks) {
      // Node has respawned at full health
      ticksRemaining -= respawnTicks;
      newState = ActionState(
        masteryXp: newState.masteryXp,
        // totalHpLost: 0 (default - full health on respawn)
        // respawnTicksRemaining: null (default - not depleted)
        // hpRegenTicksRemaining: 0 (default - no regen needed)
      );
    } else {
      // Still respawning, reduce timer
      return newState.copyWith(
        respawnTicksRemaining: respawnTicks - ticksRemaining,
      );
    }
  }

  // Apply HP regeneration if not depleted
  const ticksPer1Hp = 100; // 10 seconds = 100 ticks = 1 HP
  var regenTicks = newState.hpRegenTicksRemaining - ticksRemaining;

  while (regenTicks <= 0 && newState.totalHpLost > 0) {
    // Regenerate 1 HP
    newState = newState.copyWith(totalHpLost: max(0, newState.totalHpLost - 1));
    regenTicks += ticksPer1Hp;
  }

  // Ensure regen ticks stay in valid range
  if (newState.totalHpLost == 0) {
    regenTicks = 0; // No need to track regen when at full HP
  } else if (regenTicks > ticksPer1Hp) {
    regenTicks = ticksPer1Hp; // Cap at one regen cycle
  }

  return newState.copyWith(hpRegenTicksRemaining: max(0, regenTicks));
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

  void updateActionState(String actionName, ActionState newState) {
    final newActionStates = Map<String, ActionState>.from(_state.actionStates);
    newActionStates[actionName] = newState;
    _state = _state.copyWith(actionStates: newActionStates);
  }

  void clearAction() {
    _state = _state.clearAction();
  }

  /// Depletes a resource node and starts its respawn timer.
  void depleteResourceNode(String actionName, Action action, int totalHpLost) {
    final respawnTicks = ticksFromDuration(
      action.resourceProperties!.respawnTime,
    );
    final actionState = _state.actionState(actionName);
    updateActionState(
      actionName,
      actionState.copyWith(
        totalHpLost: totalHpLost,
        respawnTicksRemaining: respawnTicks,
      ),
    );
  }

  /// Damages a resource node and starts HP regeneration if needed.
  void damageResourceNode(String actionName, int totalHpLost) {
    final actionState = _state.actionState(actionName);
    final ticksPer1Hp = ticksFromDuration(const Duration(seconds: 10));
    updateActionState(
      actionName,
      actionState.copyWith(
        totalHpLost: totalHpLost,
        hpRegenTicksRemaining: actionState.hpRegenTicksRemaining == 0
            ? ticksPer1Hp
            : actionState.hpRegenTicksRemaining,
      ),
    );
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

  // Handle resource depletion for mining
  if (action.resourceProperties != null) {
    final actionState = builder.state.actionState(action.name);
    final masteryLevel = levelForXp(actionState.masteryXp);

    // Increment damage
    final newTotalHpLost = actionState.totalHpLost + 1;
    final currentHp = getCurrentHp(
      action,
      actionState.copyWith(totalHpLost: newTotalHpLost),
      masteryLevel,
    );

    // Check if depleted
    if (currentHp <= 0) {
      // Node is depleted - set respawn timer
      builder.depleteResourceNode(action.name, action, newTotalHpLost);
      canRepeatAction = false; // Can't continue mining
    } else {
      // Still has HP, just update damage and start regen countdown if needed
      builder.damageResourceNode(action.name, newTotalHpLost);
    }
  }

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

  // Apply HP regeneration and respawn for resource-based actions
  if (action.resourceProperties != null) {
    final actionState = state.actionState(action.name);

    // Check if node was depleted at the start
    final wasDepletedAtStart = isNodeDepleted(actionState);

    // Apply ticks to resource (regen and respawn)
    final updatedState = applyResourceTicks(actionState, ticks);
    builder.updateActionState(action.name, updatedState);

    // Check if node is still depleted after applying ticks
    if (isNodeDepleted(updatedState)) {
      // Node is still depleted, can't mine yet - all ticks consumed waiting
      return;
    } else if (wasDepletedAtStart) {
      // Node WAS depleted but has now respawned
      // Subtract the ticks we spent waiting for respawn
      final respawnTicksConsumed = actionState.respawnTicksRemaining!;
      ticksToConsume -= respawnTicksConsumed;
      // Restart the action with fresh duration since we were waiting
      builder.restartCurrentAction(action, random: rng);
    }
  }

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

      // Check if node was depleted after completion
      if (action.resourceProperties != null && !canRepeat) {
        final currentActionState = builder.state.actionState(action.name);
        if (isNodeDepleted(currentActionState)) {
          // Node depleted, wait for respawn
          final respawnTicks = currentActionState.respawnTicksRemaining!;
          if (ticksToConsume >= respawnTicks) {
            // We have enough ticks to wait for respawn
            ticksToConsume -= respawnTicks;
            // Apply respawn ticks to bring node back
            final respawnedState = applyResourceTicks(
              currentActionState,
              respawnTicks,
            );
            builder.updateActionState(action.name, respawnedState);
            // Try to restart action now that node has respawned
            if (builder.state.canStartAction(action)) {
              builder.restartCurrentAction(action, random: rng);
              continue; // Continue the loop to keep mining
            }
          } else {
            // Not enough ticks for respawn yet - apply partial respawn progress
            // but keep the action active so it resumes when node respawns
            final partialRespawnState = applyResourceTicks(
              currentActionState,
              ticksToConsume,
            );
            builder.updateActionState(action.name, partialRespawnState);
            break; // Stop processing but keep action active
          }
        }
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
