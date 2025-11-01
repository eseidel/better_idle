import 'dart:math';

import 'package:async_redux/async_redux.dart';
import 'package:flutter/material.dart';

import 'activities.dart';

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

typedef ActivityState = int;

class Activity {
  const Activity({required this.name, required this.maxValue, this.onComplete});
  final String name;
  final Tick maxValue;
  final GlobalState Function(GlobalState state)? onComplete;
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
    required this.currentActivityName,
    required this.activities,
    required this.updatedAt,
  });

  GlobalState.empty()
    : this(
        inventory: Inventory.empty(),
        currentActivityName: null,
        activities: {},
        updatedAt: DateTime.timestamp(),
      );

  GlobalState.fromJson(Map<String, dynamic> json)
    : updatedAt = DateTime.parse(json['updatedAt']),
      inventory = Inventory.fromJson(json['inventory']),
      currentActivityName = json['currentActivityName'],
      activities = Map<String, int>.from(json['activities']);

  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'inventory': inventory.toJson(),
      'currentActivityName': currentActivityName,
      'activities': activities.map((key, value) => MapEntry(key, value)),
    };
  }

  final DateTime updatedAt;
  final Inventory inventory;
  final String? currentActivityName;

  bool get isActive => currentActivityName != null;

  ActivityView? get currentActivity {
    final name = currentActivityName;
    if (name == null) {
      return null;
    }
    final state = activities[name] ?? 0;
    return ActivityView(activity: getActivity(name), state: state);
  }

  final Map<String, ActivityState> activities;

  GlobalState startActivity(String activityName) {
    final activities = Map<String, ActivityState>.from(this.activities);
    activities[activityName] = 0;
    return copyWith(currentActivityName: activityName, activities: activities);
  }

  GlobalState clearActivity() {
    return GlobalState(
      inventory: inventory,
      currentActivityName: null,
      activities: activities,
      updatedAt: DateTime.timestamp(),
    );
  }

  GlobalState updateActivity(String activityName, ActivityState value) {
    final activities = Map<String, ActivityState>.from(this.activities);
    activities[activityName] = value;
    return copyWith(activities: activities);
  }

  GlobalState copyWith({
    Inventory? inventory,
    String? currentActivityName,
    Map<String, ActivityState>? activities,
  }) {
    return GlobalState(
      inventory: inventory ?? this.inventory,
      currentActivityName: currentActivityName ?? this.currentActivityName,
      // Shallow copy, might not be enough if state is deeply nested.
      activities: Map.from(activities ?? this.activities),
      updatedAt: DateTime.timestamp(),
    );
  }
}

GlobalState consumeTicks(GlobalState startingState, Tick ticks) {
  GlobalState state = startingState;
  final startingActivityName = state.currentActivityName;
  if (startingActivityName == null) {
    return state;
  }
  String? activityName = startingActivityName;
  while (ticks > 0) {
    final activity = getActivity(activityName);
    ActivityState activityState = state.activities[activityName] ?? 0;
    final beforeUpdate = ActivityView(activity: activity, state: activityState);
    final ticksToApply = min(ticks, beforeUpdate.remainingTicks);
    activityState += ticksToApply;
    ticks -= ticksToApply;
    final afterUpdate = ActivityView(activity: activity, state: activityState);
    if (afterUpdate.remainingTicks <= 0) {
      // This activity is complete, so we need to call the onComplete callback
      // and start the next activity
      state = activity.onComplete?.call(state) ?? state;
      // This will reset the activity to 0, will not change which activity is currently active.
      activityState = 0;
    }
    state = state.updateActivity(activityName, activityState);
  }
  return state;
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
    final newState = consumeTicks(state, ticks);
    return newState;
  }
}

class StopActivityAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    // This might need to either wait for the activity to finish, or cancel it?
    return state.clearActivity();
  }
}
