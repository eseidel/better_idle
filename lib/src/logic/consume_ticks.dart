import 'dart:math';

import '../data/actions.dart';
import '../data/xp.dart';
import '../state.dart';
import '../types/inventory.dart';
import '../types/time_away.dart';

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
int masteryXpPerAction(GlobalState state, Action action) {
  final skillState = state.skillState(action.skill);
  final actionState = state.actionState(action.name);
  final actionMasteryLevel = levelForXp(actionState.masteryXp);
  final itemsInSkill = actionRegistry.forSkill(action.skill).length;
  return calculateMasteryXpPerAction(
    unlockedActions: state.unlockedActionsCount(action.skill),
    actionSeconds: action.duration.inSeconds.toDouble(),
    playerTotalMasteryForSkill: skillState.xp,
    totalMasteryForSkill: skillState.masteryXp,
    itemMasteryLevel: actionMasteryLevel,
    totalItemsInSkill: itemsInSkill,
    bonus: 0.0,
  );
}

class StateUpdateBuilder {
  StateUpdateBuilder(this._state);

  GlobalState _state;
  Changes _changes = Changes.empty();

  GlobalState get state => _state;

  void setActionProgress(Action action, int progress) {
    _state = _state.updateActiveAction(action.name, progress);
  }

  void addInventory(ItemStack item) {
    _state = _state.copyWith(inventory: _state.inventory.adding(item));
    _changes = _changes.adding(item);
  }

  void addSkillXp(Skill skill, int amount) {
    _state = _state.addSkillXp(skill, amount);
    _changes = _changes.addingSkillXp(skill, amount);
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

  GlobalState build() => _state;

  Changes get changes => _changes;
}

class _Progress {
  const _Progress(this.action, this.progressTicks);
  final Action action;
  final int progressTicks;

  int get remainingTicks => action.maxValue - progressTicks;
}

void completeAction(StateUpdateBuilder builder, Action action) {
  for (final reward in action.rewards) {
    builder.addInventory(reward);
  }
  builder.addSkillXp(action.skill, action.xp);
  final masteryXpToAdd = masteryXpPerAction(builder.state, action);
  builder.addActionMasteryXp(action.name, masteryXpToAdd);
  final skillMasteryXp = max(1, (0.25 * masteryXpToAdd).toInt());
  builder.addSkillMasteryXp(action.skill, skillMasteryXp);
}

void consumeTicks(StateUpdateBuilder builder, Tick ticks) {
  GlobalState state = builder.state;
  final startingAction = state.activeAction;
  if (startingAction == null) {
    return;
  }
  // The active action can never change during this loop other than to
  // be cleared. So we can just use the starting action name.
  final action = actionRegistry.byName(startingAction.name);
  while (ticks > 0) {
    final before = _Progress(action, state.activeProgress(action));
    final ticksToApply = min(ticks, before.remainingTicks);
    final progressTicks = before.progressTicks + ticksToApply;
    ticks -= ticksToApply;
    builder.setActionProgress(action, progressTicks);

    final after = _Progress(action, progressTicks);
    if (after.remainingTicks <= 0) {
      completeAction(builder, action);

      // Reset progress for the *current* activity.
      if (builder.state.activeAction?.name != startingAction.name) {
        throw Exception('Active action changed during consumption?');
      }
      builder.setActionProgress(action, 0);
    }
  }
}
