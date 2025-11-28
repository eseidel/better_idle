import 'dart:math';

import 'activities.dart';
import 'state.dart';
import 'xp.dart';

export 'package:async_redux/async_redux.dart';

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

abstract class GameActionBuilder {
  GlobalState get state;
  void setActionProgress(Action action, int progress);
  void addInventory(ItemStack item);
  void addSkillXp(Skill skill, int amount);
  void addMasteryXp(Skill skill, int amount);
}

class TimeAway {
  const TimeAway({
    required this.duration,
    required this.activeSkill,
    required this.changes,
  });
  final Duration duration;
  final Skill? activeSkill;
  final Changes changes;

  const TimeAway.empty()
    : this(
        duration: Duration.zero,
        activeSkill: null,
        changes: const Changes.empty(),
      );
}

class Counts<T> {
  const Counts({required this.counts});
  final Map<T, int> counts;

  const Counts.empty() : this(counts: const {});

  Counts<T> add(Counts<T> other) {
    for (final entry in other.counts.entries) {
      counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
    }
    return Counts(counts: counts);
  }

  Counts<T> addCount(T key, int value) {
    final newCounts = Map<T, int>.from(counts);
    newCounts[key] = (newCounts[key] ?? 0) + value;
    return Counts(counts: newCounts);
  }

  Iterable<MapEntry<T, int>> get entries => counts.entries;

  bool get isEmpty => counts.isEmpty;

  bool get isNotEmpty => counts.isNotEmpty;
}

class Changes {
  const Changes({required this.inventoryChanges, required this.xpChanges});
  final Counts<String> inventoryChanges;
  final Counts<Skill> xpChanges;

  const Changes.empty()
    : this(
        inventoryChanges: const Counts<String>.empty(),
        xpChanges: const Counts<Skill>.empty(),
      );

  Changes merge(Changes other) {
    return Changes(
      inventoryChanges: inventoryChanges.add(other.inventoryChanges),
      xpChanges: xpChanges.add(other.xpChanges),
    );
  }

  bool get isEmpty => inventoryChanges.isEmpty && xpChanges.isEmpty;

  Changes adding(ItemStack item) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(item.name, item.count),
      xpChanges: xpChanges,
    );
  }

  Changes addingXp(Skill skill, int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      xpChanges: xpChanges.addCount(skill, amount),
    );
  }
}

class StateUpdateBuilder implements GameActionBuilder {
  StateUpdateBuilder(this._state);

  GlobalState _state;
  Changes _changes = Changes.empty();

  @override
  GlobalState get state => _state;

  @override
  void setActionProgress(Action action, int progress) {
    _state = _state.updateAction(action.name, progress);
  }

  @override
  void addInventory(ItemStack item) {
    _state = _state.copyWith(inventory: _state.inventory.adding(item));
    _changes = _changes.adding(item);
  }

  @override
  void addSkillXp(Skill skill, int amount) {
    _state = _state.addSkillXp(skill, amount);
    _changes = _changes.addingXp(skill, amount);
  }

  @override
  void addMasteryXp(Skill skill, int amount) {
    _state = _state.addMasteryXp(skill, amount);
    _changes = _changes.addingXp(skill, amount);
  }

  GlobalState build() {
    return _state;
  }

  Changes get changes => _changes;
}

class _Progress {
  const _Progress(this.action, this.progressTicks);
  final Action action;
  final int progressTicks;

  int get remainingTicks => action.maxValue - progressTicks;
}

void completeAction(GameActionBuilder builder, Action action) {
  for (final reward in action.rewards) {
    builder.addInventory(reward);
  }
  builder.addSkillXp(action.skill, action.xp);
  builder.addMasteryXp(action.skill, masteryXpPerAction(builder.state, action));
}

void consumeTicks(GameActionBuilder builder, Tick ticks) {
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
