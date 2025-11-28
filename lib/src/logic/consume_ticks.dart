import 'dart:math';

import '../data/actions.dart';
import '../state.dart';
import '../data/xp.dart';

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

  TimeAway copyWith({
    Duration? duration,
    Skill? activeSkill,
    Changes? changes,
  }) {
    return TimeAway(
      duration: duration ?? this.duration,
      activeSkill: activeSkill ?? this.activeSkill,
      changes: changes ?? this.changes,
    );
  }

  TimeAway mergeChanges(Changes changes) {
    return copyWith(changes: this.changes.merge(changes));
  }

  TimeAway maybeMergeInto(TimeAway? other) {
    if (other == null) {
      return this;
    }
    return mergeChanges(other.changes);
  }

  Map<String, dynamic> toJson() {
    return {
      'duration': duration.inMilliseconds,
      'activeSkill': activeSkill?.name,
      'changes': changes.toJson(),
    };
  }

  factory TimeAway.fromJson(Map<String, dynamic> json) {
    return TimeAway(
      duration: Duration(milliseconds: json['duration']),
      activeSkill: json['activeSkill'] != null
          ? Skill.fromName(json['activeSkill'])
          : null,
      changes: Changes.fromJson(json['changes']),
    );
  }
}

class Counts<T> {
  const Counts({required this.counts});
  final Map<T, int> counts;

  // There must be a better way to do this in Dart?
  static dynamic toJsonKey<T>(T key) {
    if (key is Skill) {
      return key.name;
    }
    return key;
  }

  // There must be a better way to do this in Dart?
  static T fromJsonKey<T>(dynamic key) {
    if (T == Skill) {
      return Skill.fromName(key as String) as T;
    }
    return key as T;
  }

  const Counts.empty() : this(counts: const {});

  Counts<T> add(Counts<T> other) {
    final newCounts = Map<T, int>.from(counts);
    for (final entry in other.counts.entries) {
      newCounts[entry.key] = (newCounts[entry.key] ?? 0) + entry.value;
    }
    return Counts(counts: newCounts);
  }

  Counts<T> addCount(T key, int value) {
    final newCounts = Map<T, int>.from(counts);
    newCounts[key] = (newCounts[key] ?? 0) + value;
    return Counts(counts: newCounts);
  }

  Iterable<MapEntry<T, int>> get entries => counts.entries;

  bool get isEmpty => counts.isEmpty;

  bool get isNotEmpty => counts.isNotEmpty;

  Map<String, dynamic> toJson() {
    return counts.map((key, value) => MapEntry(Counts.toJsonKey(key), value));
  }

  factory Counts.fromJson(Map<String, dynamic> json) {
    return Counts<T>(
      counts: Map<T, int>.from(
        json.map(
          (key, value) => MapEntry(Counts.fromJsonKey<T>(key), value as int),
        ),
      ),
    );
  }
}

class Changes {
  const Changes({required this.inventoryChanges, required this.skillXpChanges});
  final Counts<String> inventoryChanges;
  final Counts<Skill> skillXpChanges;
  // We don't bother tracking mastery XP changes since they're not displayed
  // in the welcome back dialog.

  const Changes.empty()
    : this(
        inventoryChanges: const Counts<String>.empty(),
        skillXpChanges: const Counts<Skill>.empty(),
      );

  Changes merge(Changes other) {
    return Changes(
      inventoryChanges: inventoryChanges.add(other.inventoryChanges),
      skillXpChanges: skillXpChanges.add(other.skillXpChanges),
    );
  }

  bool get isEmpty => inventoryChanges.isEmpty && skillXpChanges.isEmpty;

  Changes adding(ItemStack item) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(item.name, item.count),
      skillXpChanges: skillXpChanges,
    );
  }

  Changes addingSkillXp(Skill skill, int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges.addCount(skill, amount),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inventoryChanges': inventoryChanges.toJson(),
      'skillXpChanges': skillXpChanges.toJson(),
    };
  }

  factory Changes.fromJson(Map<String, dynamic> json) {
    return Changes(
      inventoryChanges: Counts<String>.fromJson(json['inventoryChanges']),
      skillXpChanges: Counts<Skill>.fromJson(json['skillXpChanges']),
    );
  }
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
