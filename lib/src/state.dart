import 'dart:math';

import 'package:async_redux/async_redux.dart';
import 'package:flutter/material.dart';

export 'package:async_redux/async_redux.dart';

extension BuildContextExtension on BuildContext {
  GlobalState get state => getState<GlobalState>();
}

typedef Tick = int;
final Duration tickDuration = const Duration(milliseconds: 100);

class Inventory {
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

class Activity {
  const Activity({
    required this.name,
    required this.maxValue,
    this.value = 0,
    this.onComplete,
  });
  final String name;
  final Tick value;
  final Tick maxValue;
  final GlobalState Function(GlobalState state)? onComplete;

  double get progress => value.toDouble() / maxValue.toDouble();
  Tick get remainingTicks => maxValue - value;

  Activity copyWith({int? value}) {
    return Activity(
      name: name,
      maxValue: maxValue,
      value: value ?? this.value,
      onComplete: onComplete,
    );
  }
}

class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.currentActivity,
    required this.updatedAt,
  });

  GlobalState.empty()
    : this(
        inventory: Inventory.empty(),
        currentActivity: null,
        updatedAt: DateTime.timestamp(),
      );

  final DateTime updatedAt;
  final Inventory inventory;
  final Activity? currentActivity;

  GlobalState clearActivity() {
    return GlobalState(
      inventory: inventory,
      currentActivity: null,
      updatedAt: DateTime.timestamp(),
    );
  }

  GlobalState copyWith({Inventory? inventory, Activity? currentActivity}) {
    return GlobalState(
      inventory: inventory ?? this.inventory,
      currentActivity: currentActivity ?? this.currentActivity,
      updatedAt: DateTime.timestamp(),
    );
  }
}

GlobalState consumeTicks(GlobalState startingState, Tick ticks) {
  GlobalState state = startingState;
  final startingActivity = state.currentActivity;
  if (startingActivity == null) {
    return state;
  }
  Activity activity = startingActivity;
  while (ticks > 0) {
    final ticksToApply = min(ticks, activity.remainingTicks);
    activity = activity.copyWith(value: activity.value + ticksToApply);
    ticks -= ticksToApply;
    if (activity.remainingTicks <= 0) {
      // This activity is complete, so we need to call the onComplete callback
      // and start the next activity
      state = activity.onComplete?.call(state) ?? state;
      activity = activity.copyWith(value: 0);
    }
    state = state.copyWith(currentActivity: activity);
  }
  return state;
}

class StartActivityAction extends ReduxAction<GlobalState> {
  StartActivityAction({required this.activity});
  final Activity activity;
  @override
  GlobalState reduce() {
    // We need to stop the current activity or wait for it to finish?
    return store.state.copyWith(currentActivity: activity);
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
