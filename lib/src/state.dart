import 'dart:math';

import 'package:async_redux/async_redux.dart';
import 'package:flutter/material.dart';

import 'activities.dart';
import 'services/toast_service.dart';

export 'package:async_redux/async_redux.dart';

extension BuildContextExtension on BuildContext {
  GlobalState get state => getState<GlobalState>();
}

typedef Tick = int;
final Duration tickDuration = const Duration(milliseconds: 100);

class Inventory {
  Inventory.fromJson(Map<String, dynamic> json)
    : _counts = Map<String, int>.from(json['counts']),
      _orderedItems = List<String>.from(json['orderedItems']);

  Map<String, dynamic> toJson() {
    return {'counts': _counts, 'orderedItems': _orderedItems};
  }

  Inventory.fromItems(List<ItemStack> items)
    : _counts = {},
      _orderedItems = [] {
    for (var item in items) {
      _counts[item.name] = item.count;
      _orderedItems.add(item.name);
    }
  }

  Inventory.empty() : this.fromItems([]);

  Inventory._({
    required Map<String, int> counts,
    required List<String> orderedItems,
  }) : _counts = counts,
       _orderedItems = orderedItems;

  final Map<String, int> _counts;
  final List<String> _orderedItems;

  List<ItemStack> get items =>
      _orderedItems.map((e) => ItemStack(name: e, count: _counts[e]!)).toList();

  Inventory adding(ItemStack item) {
    final counts = Map<String, int>.from(_counts);
    final orderedItems = List<String>.from(_orderedItems);
    final existingCount = counts[item.name];
    if (existingCount == null) {
      counts[item.name] = item.count;
      orderedItems.add(item.name);
    } else {
      counts[item.name] = existingCount + item.count;
    }
    return Inventory._(counts: counts, orderedItems: orderedItems);
  }
}

Tick ticksFromDuration(Duration duration) {
  return duration.inMilliseconds ~/ tickDuration.inMilliseconds;
}

Tick ticksSince(DateTime start) {
  return ticksFromDuration(DateTime.timestamp().difference(start));
}

class Recipe {
  const Recipe({
    required this.name,
    required this.ingredients,
    required this.output,
    required this.duration,
  });
  final String name;
  final List<ItemStack> ingredients;
  final ItemStack output;
  final Tick duration;
}

class ItemStack {
  const ItemStack({required this.name, required this.count});
  final String name;
  final int count;

  ItemStack copyWith({int? count}) {
    return ItemStack(name: name, count: count ?? this.count);
  }
}

class ActiveAction {
  const ActiveAction({required this.name, required this.progressTicks});
  final String name;
  final int progressTicks;

  ActiveAction copyWith({String? name, int? progressTicks}) {
    return ActiveAction(
      name: name ?? this.name,
      progressTicks: progressTicks ?? this.progressTicks,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'progressTicks': progressTicks,
  };

  factory ActiveAction.fromJson(Map<String, dynamic> json) {
    return ActiveAction(
      name: json['name'],
      progressTicks: json['progressTicks'],
    );
  }
}

class Action {
  const Action({
    required this.skill,
    required this.name,
    required this.duration,
    required this.xp,
    required this.rewards,
  });
  final Skill skill;
  final String name;
  final int xp;
  final List<ItemStack> rewards;
  final Duration duration;
  Tick get maxValue => duration.inMilliseconds ~/ tickDuration.inMilliseconds;
}

class ActiveActionView {
  const ActiveActionView({required this.action, required this.progressTicks});

  final Action action;
  final int progressTicks;

  double get progress => progressTicks.toDouble() / action.maxValue.toDouble();
  Tick get remainingTicks => action.maxValue - progressTicks;
}

class SkillState {
  const SkillState({required this.xp, required this.masteryXp});
  final int xp;
  final int masteryXp;

  SkillState.empty() : this(xp: 0, masteryXp: 0);

  SkillState copyWith({int? xp, int? masteryXp}) {
    return SkillState(
      xp: xp ?? this.xp,
      masteryXp: masteryXp ?? this.masteryXp,
    );
  }

  SkillState.fromJson(Map<String, dynamic> json)
    : xp = json['xp'],
      masteryXp = json['masteryXp'];

  Map<String, dynamic> toJson() {
    return {'xp': xp, 'masteryXp': masteryXp};
  }
}

class ActionState {
  const ActionState({required this.masteryXp});
  final int masteryXp;

  const ActionState.empty() : this(masteryXp: 0);

  ActionState copyWith({int? masteryXp}) {
    return ActionState(masteryXp: masteryXp ?? this.masteryXp);
  }

  Map<String, dynamic> toJson() {
    return {'masteryXp': masteryXp};
  }

  factory ActionState.fromJson(Map<String, dynamic> json) {
    return ActionState(masteryXp: json['masteryXp']);
  }
}

class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.activeAction,
    required this.skillStates,
    required this.actionStates,
    required this.updatedAt,
  });

  GlobalState.empty()
    : this(
        inventory: Inventory.empty(),
        activeAction: null,
        skillStates: {},
        actionStates: {},
        updatedAt: DateTime.timestamp(),
      );

  GlobalState.fromJson(Map<String, dynamic> json)
    : updatedAt = DateTime.parse(json['updatedAt']),
      inventory = Inventory.fromJson(json['inventory']),
      activeAction = json['activeAction'] != null
          ? ActiveAction.fromJson(json['activeAction'])
          : null,
      skillStates =
          (json['skillStates'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              Skill.fromName(key),
              SkillState.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {},
      actionStates =
          (json['actionStates'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              ActionState.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {};
  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'inventory': inventory.toJson(),
      'activeAction': activeAction?.toJson(),
      'skillStates': skillStates.map(
        (key, value) => MapEntry(key.name, value.toJson()),
      ),
      'actionStates': actionStates.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  final DateTime updatedAt;
  final Inventory inventory;
  final ActiveAction? activeAction;
  final Map<Skill, SkillState> skillStates;
  final Map<String, ActionState> actionStates;

  String? get activeActionName => activeAction?.name;

  bool get isActive => activeAction != null;

  ActiveActionView? get activeActionView {
    final active = activeAction;
    if (active == null) {
      return null;
    }
    final action = actionRegistry.byName(active.name);
    return ActiveActionView(
      action: action,
      progressTicks: active.progressTicks,
    );
  }

  Skill? get activeSkill => activeActionView?.action.skill;

  GlobalState startAction(Action action) {
    return copyWith(
      activeAction: ActiveAction(name: action.name, progressTicks: 0),
    );
  }

  GlobalState clearAction() {
    return GlobalState(
      inventory: inventory,
      activeAction: null,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: DateTime.timestamp(),
    );
  }

  SkillState skillState(Skill skill) =>
      skillStates[skill] ?? SkillState.empty();

  ActionState actionState(String action) =>
      actionStates[action] ?? ActionState.empty();

  GlobalState updateAction(String actionName, int progressTicks) {
    if (activeAction?.name != actionName) {
      return this;
    }
    return copyWith(
      activeAction: activeAction!.copyWith(progressTicks: progressTicks),
    );
  }

  GlobalState addSkillXp(Skill skill, int amount) {
    final newState = skillState(
      skill,
    ).copyWith(xp: skillState(skill).xp + amount);
    final newSkillStates = Map<Skill, SkillState>.from(skillStates);
    newSkillStates[skill] = newState;
    return copyWith(skillStates: newSkillStates);
  }

  GlobalState copyWith({
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState>? skillStates,
    Map<String, ActionState>? actionStates,
  }) {
    return GlobalState(
      inventory: inventory ?? this.inventory,
      activeAction: activeAction ?? this.activeAction,
      skillStates: skillStates ?? this.skillStates,
      actionStates: actionStates ?? this.actionStates,
      updatedAt: DateTime.timestamp(),
    );
  }
}

int calculateMasteryXp({
  required int unlockedActions,
  required int playerTotalMasteryForSkill,
  required int totalMasteryForSkill,
  required int itemMasteryLevel,
  required int totalItemsInSkill,
  required double actionSeconds, // In seconds
  required double bonus, // e.g. 0.1 for +10%
}) {
  final masteryPortion =
      unlockedActions * (playerTotalMasteryForSkill / totalMasteryForSkill);
  final itemPortion = itemMasteryLevel * (totalItemsInSkill / 10);
  final baseValue = masteryPortion + itemPortion;
  return max(1, baseValue * actionSeconds * 0.5 * (1 + bonus)).toInt();
}

int masteryXpForAction(GlobalState state, Action action) {
  return calculateMasteryXp(
    unlockedActions: 1,
    actionSeconds: action.duration.inSeconds.toDouble(),
    playerTotalMasteryForSkill: state.skillState(action.skill).xp,
    totalMasteryForSkill: 1000,
    itemMasteryLevel: 1,
    totalItemsInSkill: 100,
    bonus: 0.0,
  );
}

abstract class GameActionBuilder {
  GlobalState get state;
  void setActionProgress(Action action, int progress);
  void addInventory(ItemStack item);
  void addXp(Skill skill, int amount);
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
  void addXp(Skill skill, int amount) {
    _state = _state.addSkillXp(skill, amount);
    _changes = _changes.addingXp(skill, amount);
  }

  GlobalState build() {
    return _state;
  }

  Changes get changes => _changes;
}

void consumeTicks(GameActionBuilder builder, Tick ticks) {
  GlobalState state = builder.state;
  final startingAction = state.activeAction;
  if (startingAction == null) {
    return;
  }
  // The active action can never change during this loop other than to
  // be cleared. So we can just use the starting action name.
  final actionName = startingAction.name;
  while (ticks > 0) {
    final action = actionRegistry.byName(actionName);
    final beforeUpdate = state.activeActionView;
    if (beforeUpdate == null) {
      return;
    }
    final ticksToApply = min(ticks, beforeUpdate.remainingTicks);
    final progressTicks = beforeUpdate.progressTicks + ticksToApply;
    ticks -= ticksToApply;
    final afterUpdate = ActiveActionView(
      action: action,
      progressTicks: progressTicks,
    );

    builder.setActionProgress(action, progressTicks);

    if (afterUpdate.remainingTicks <= 0) {
      // This activity is complete
      // Add rewards
      for (final reward in action.rewards) {
        builder.addInventory(reward);
      }

      // Add XP
      builder.addXp(action.skill, action.xp);

      // Reset progress for the *current* activity if it's still the same
      if (builder.state.activeAction?.name == actionName) {
        builder.setActionProgress(action, 0);
      }
    }
  }
}

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
      activeSkill: state.activeActionView?.action.skill,
      changes: builder.changes,
    );
    return builder.build();
  }
}
