import 'dart:math';

import 'package:async_redux/async_redux.dart';
import 'package:equatable/equatable.dart';
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

Tick ticksSince(DateTime start) {
  final difference = DateTime.timestamp().difference(start);
  return difference.inMilliseconds ~/ tickDuration.inMilliseconds;
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

class CurrentActivity {
  const CurrentActivity({required this.name, required this.progress});
  final String name;
  final int progress;

  CurrentActivity copyWith({String? name, int? progress}) {
    return CurrentActivity(
      name: name ?? this.name,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'progress': progress};

  factory CurrentActivity.fromJson(Map<String, dynamic> json) {
    return CurrentActivity(name: json['name'], progress: json['progress']);
  }
}

class ToastMessage extends Equatable {
  const ToastMessage(this.message);
  final String message;

  @override
  String toString() => message;

  @override
  List<Object?> get props => [message];
}

typedef ActivityState = int;

class Activity {
  Activity({
    required this.skill,
    required this.name,
    required Duration duration,
    required this.xp,
    required this.rewards,
  }) : maxValue = duration.inMilliseconds ~/ tickDuration.inMilliseconds;
  final Skill skill;
  final String name;
  final int xp;
  final Tick maxValue;
  final List<ItemStack> rewards;
}

class ActivityView {
  const ActivityView({required this.activity, required this.state});

  final Activity activity;
  final ActivityState state;

  double get progress => state.toDouble() / activity.maxValue.toDouble();
  Tick get remainingTicks => activity.maxValue - state;
}

class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.activeActivity,
    required Map<Skill, int> skillXp,
    required this.updatedAt,
  }) : _skillXp = skillXp;

  GlobalState.empty()
    : this(
        inventory: Inventory.empty(),
        activeActivity: null,
        skillXp: {},
        updatedAt: DateTime.timestamp(),
      );

  GlobalState.fromJson(Map<String, dynamic> json)
    : updatedAt = DateTime.parse(json['updatedAt']),
      inventory = Inventory.fromJson(json['inventory']),
      activeActivity = json['activeActivity'] != null
          ? CurrentActivity.fromJson(json['activeActivity'])
          : null,
      _skillXp =
          (json['xp'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              Skill.values.firstWhere((e) => e.name == key),
              value as int,
            ),
          ) ??
          {};

  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'inventory': inventory.toJson(),
      'activeActivity': activeActivity?.toJson(),
      'xp': _skillXp.map((key, value) => MapEntry(key.name, value)),
    };
  }

  final DateTime updatedAt;
  final Inventory inventory;
  final CurrentActivity? activeActivity;
  final Map<Skill, int> _skillXp;

  String? get currentActivityName => activeActivity?.name;

  bool get isActive => activeActivity != null;

  ActivityView? get currentActivity {
    final activity = activeActivity;
    if (activity == null) {
      return null;
    }
    return ActivityView(
      activity: getActivity(activity.name),
      state: activity.progress,
    );
  }

  GlobalState startActivity(String activityName) {
    return copyWith(
      activeActivity: CurrentActivity(name: activityName, progress: 0),
    );
  }

  GlobalState clearActivity() {
    return GlobalState(
      inventory: inventory,
      activeActivity: null,
      skillXp: _skillXp,
      updatedAt: DateTime.timestamp(),
    );
  }

  int skillXp(Skill skill) => _skillXp[skill] ?? 0;

  GlobalState updateActivity(String activityName, ActivityState value) {
    if (activeActivity?.name != activityName) {
      return this;
    }
    return copyWith(activeActivity: activeActivity!.copyWith(progress: value));
  }

  GlobalState addXp(Skill skill, int amount) {
    final newXp = Map<Skill, int>.from(_skillXp);
    newXp[skill] = (newXp[skill] ?? 0) + amount;
    return copyWith(xp: newXp);
  }

  GlobalState copyWith({
    Inventory? inventory,
    CurrentActivity? activeActivity,
    Map<Skill, int>? xp,
  }) {
    return GlobalState(
      inventory: inventory ?? this.inventory,
      activeActivity: activeActivity ?? this.activeActivity,
      skillXp: Map.from(_skillXp)..addAll(xp ?? {}),
      updatedAt: DateTime.timestamp(),
    );
  }
}

abstract class GameActionBuilder {
  GlobalState get state;
  void setActivityProgress(String activityName, ActivityState progress);
  void addInventory(ItemStack item);
  void addXp(Skill skill, int amount);
}

class Changes {
  const Changes({required this.inventoryChanges, required this.xpChanges});
  final Map<String, int> inventoryChanges;
  final Map<String, int> xpChanges;

  factory Changes.empty() {
    return const Changes(inventoryChanges: {}, xpChanges: {});
  }

  Changes merge(Changes other) {
    return Changes(
      inventoryChanges: Map<String, int>.from(inventoryChanges)
        ..addAll(other.inventoryChanges),
      xpChanges: Map<String, int>.from(xpChanges)..addAll(other.xpChanges),
    );
  }

  bool get isEmpty => inventoryChanges.isEmpty && xpChanges.isEmpty;

  Changes adding(ItemStack item) {
    return Changes(
      inventoryChanges: Map<String, int>.from(inventoryChanges)
        ..addAll({item.name: item.count}),
      xpChanges: xpChanges,
    );
  }

  Changes addingXp(Skill skill, int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      xpChanges: Map<String, int>.from(xpChanges)..addAll({skill.name: amount}),
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
  void setActivityProgress(String activityName, ActivityState progress) {
    _state = _state.updateActivity(activityName, progress);
  }

  @override
  void addInventory(ItemStack item) {
    _state = _state.copyWith(inventory: _state.inventory.adding(item));
    _changes = _changes.adding(item);
  }

  @override
  void addXp(Skill skill, int amount) {
    _state = _state.addXp(skill, amount);
    _changes = _changes.addingXp(skill, amount);
  }

  GlobalState build() {
    return _state;
  }

  Changes get changes => _changes;
}

void consumeTicks(GameActionBuilder builder, Tick ticks) {
  GlobalState state = builder.state;
  final startingActivity = state.activeActivity;
  if (startingActivity == null) {
    return;
  }
  String activityName = startingActivity.name;
  while (ticks > 0) {
    final currentActivity = builder.state.activeActivity;
    if (currentActivity == null) {
      break;
    }
    activityName = currentActivity.name;

    final activity = getActivity(activityName);
    ActivityState activityState = currentActivity.progress;
    final beforeUpdate = ActivityView(activity: activity, state: activityState);
    final ticksToApply = min(ticks, beforeUpdate.remainingTicks);
    activityState += ticksToApply;
    ticks -= ticksToApply;
    final afterUpdate = ActivityView(activity: activity, state: activityState);

    builder.setActivityProgress(activityName, activityState);

    if (afterUpdate.remainingTicks <= 0) {
      // This activity is complete
      // Add rewards
      for (final reward in activity.rewards) {
        builder.addInventory(reward);
      }

      // Add XP
      builder.addXp(activity.skill, activity.xp);

      // Reset progress for the *current* activity if it's still the same
      if (builder.state.activeActivity?.name == activityName) {
        builder.setActivityProgress(activityName, 0);
      }
    }
  }
}

class StartActivityAction extends ReduxAction<GlobalState> {
  StartActivityAction({required this.activityName});
  final String activityName;
  @override
  GlobalState reduce() {
    // We need to stop the current activity or wait for it to finish?
    return store.state.startActivity(activityName);
  }
}

class UpdateActivityProgressAction extends ReduxAction<GlobalState> {
  UpdateActivityProgressAction({required this.now});
  final DateTime now;

  @override
  GlobalState reduce() {
    final activity = state.currentActivity;
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

class StopActivityAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    // This might need to either wait for the activity to finish, or cancel it?
    return state.clearActivity();
  }
}
