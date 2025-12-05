import 'dart:math';

import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/types/inventory.dart';

export 'package:async_redux/async_redux.dart';

typedef Tick = int;
const Duration tickDuration = Duration(milliseconds: 100);

/// Exception thrown when attempting to add an item to a full inventory.
class InventoryFullException implements Exception {
  const InventoryFullException({
    required this.currentCapacity,
    required this.attemptedItem,
  });

  final int currentCapacity;
  final String attemptedItem;

  @override
  String toString() =>
      'InventoryFullException: Cannot add $attemptedItem - '
      'inventory is full (capacity: $currentCapacity)';
}

Tick ticksFromDuration(Duration duration) {
  return duration.inMilliseconds ~/ tickDuration.inMilliseconds;
}

Tick ticksSince(DateTime start) {
  return ticksFromDuration(DateTime.timestamp().difference(start));
}

class ActiveAction {
  const ActiveAction({
    required this.name,
    required this.remainingTicks,
    required this.totalTicks,
  });

  factory ActiveAction.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final remainingTicks = json['remainingTicks'] as int?;
    final totalTicks = json['totalTicks'] as int?;

    // Backward compatibility: if new fields missing, derive from old fields.
    if (remainingTicks == null || totalTicks == null) {
      final oldProgressTicks = json['progressTicks'] as int? ?? 0;
      final action = actionRegistry.byName(name);
      final defaultTotal = action.maxValue;
      return ActiveAction(
        name: name,
        remainingTicks: defaultTotal - oldProgressTicks,
        totalTicks: defaultTotal,
      );
    }

    return ActiveAction(
      name: name,
      remainingTicks: remainingTicks,
      totalTicks: totalTicks,
    );
  }

  final String name;
  final int remainingTicks;
  final int totalTicks;

  // Computed getter for backward compatibility
  int get progressTicks => totalTicks - remainingTicks;

  ActiveAction copyWith({String? name, int? remainingTicks, int? totalTicks}) {
    return ActiveAction(
      name: name ?? this.name,
      remainingTicks: remainingTicks ?? this.remainingTicks,
      totalTicks: totalTicks ?? this.totalTicks,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'remainingTicks': remainingTicks,
    'totalTicks': totalTicks,
  };
}

class SkillState {
  const SkillState({required this.xp, required this.masteryXp});

  SkillState.empty() : this(xp: 0, masteryXp: 0);

  SkillState.fromJson(Map<String, dynamic> json)
    : xp = json['xp'] as int,
      masteryXp = json['masteryXp'] as int;
  final int xp;
  final int masteryXp;

  SkillState copyWith({int? xp, int? masteryXp}) {
    return SkillState(
      xp: xp ?? this.xp,
      masteryXp: masteryXp ?? this.masteryXp,
    );
  }

  Map<String, dynamic> toJson() {
    return {'xp': xp, 'masteryXp': masteryXp};
  }
}

class ActionState {
  const ActionState({required this.masteryXp});

  const ActionState.empty() : this(masteryXp: 0);

  factory ActionState.fromJson(Map<String, dynamic> json) {
    return ActionState(masteryXp: json['masteryXp'] as int);
  }
  final int masteryXp;

  ActionState copyWith({int? masteryXp}) {
    return ActionState(masteryXp: masteryXp ?? this.masteryXp);
  }

  Map<String, dynamic> toJson() {
    return {'masteryXp': masteryXp};
  }
}

class ShopState {
  const ShopState({required this.bankSlots});

  const ShopState.empty() : this(bankSlots: 0);

  factory ShopState.fromJson(Map<String, dynamic> json) {
    return ShopState(bankSlots: json['bankSlots'] as int);
  }
  final int bankSlots;

  ShopState copyWith({int? bankSlots}) {
    return ShopState(bankSlots: bankSlots ?? this.bankSlots);
  }

  Map<String, dynamic> toJson() {
    return {'bankSlots': bankSlots};
  }

  int nextBankSlotCost() {
    // https://wiki.melvoridle.com/w/Bank
    // C_b = \left \lfloor \frac{132\,728\,500 \times (n+2)}{142\,015^{\left (\frac{163}{122+n} \right )}}\right \rfloor
    final n = bankSlots;
    return (132728500 * (n + 2) / pow(142015, 163 / (122 + n))).floor();
  }
}

/// The initial number of free bank slots.
const int initialBankSlots = 20;

class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.activeAction,
    required this.skillStates,
    required this.actionStates,
    required this.updatedAt,
    required this.gp,
    required this.shop,
    this.timeAway,
  });

  GlobalState.empty()
    : this(
        inventory: const Inventory.empty(),
        activeAction: null,
        skillStates: {},
        actionStates: {},
        updatedAt: DateTime.timestamp(),
        gp: 0,
        timeAway: null,
        shop: const ShopState.empty(),
      );

  factory GlobalState.test({
    Inventory inventory = const Inventory.empty(),
    ActiveAction? activeAction,
    Map<Skill, SkillState> skillStates = const {},
    Map<String, ActionState> actionStates = const {},
    DateTime? updatedAt,
    int gp = 0,
    TimeAway? timeAway,
    ShopState shop = const ShopState.empty(),
  }) {
    return GlobalState(
      inventory: inventory,
      activeAction: activeAction,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: updatedAt ?? DateTime.timestamp(),
      gp: gp,
      timeAway: timeAway,
      shop: shop,
    );
  }

  GlobalState.fromJson(Map<String, dynamic> json)
    : updatedAt = DateTime.parse(json['updatedAt'] as String),
      inventory = Inventory.fromJson(json['inventory'] as Map<String, dynamic>),
      activeAction = json['activeAction'] != null
          ? ActiveAction.fromJson(json['activeAction'] as Map<String, dynamic>)
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
          {},
      gp = json['gp'] as int? ?? 0,
      timeAway = json['timeAway'] != null
          ? TimeAway.fromJson(json['timeAway'] as Map<String, dynamic>)
          : null,
      shop = json['shop'] != null
          ? ShopState.fromJson(json['shop'] as Map<String, dynamic>)
          : const ShopState.empty();

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
      'gp': gp,
      'timeAway': timeAway?.toJson(),
      'shop': shop.toJson(),
    };
  }

  /// The last time the state was updated (created since it's immutable).
  final DateTime updatedAt;

  /// The inventory of items.
  final Inventory inventory;

  /// The active action.
  final ActiveAction? activeAction;

  /// The accumulated skill states.
  final Map<Skill, SkillState> skillStates;

  /// The accumulated action states.
  final Map<String, ActionState> actionStates;

  /// The current gold pieces (GP) the player has.
  final int gp;

  /// Time away represents the accumulated changes since the last time the
  /// user interacted with the app.  It is persisted to disk, for the case in
  /// which the user kills the app with the "welcome back" dialog open.
  final TimeAway? timeAway;

  /// The shop state.
  final ShopState shop;

  int get inventoryCapacity => shop.bankSlots + initialBankSlots;

  bool get isActive => activeAction != null;

  Skill? get activeSkill {
    final name = activeAction?.name;
    if (name == null) {
      return null;
    }
    return actionRegistry.byName(name).skill;
  }

  /// Returns the number of unique item types (slots) used in inventory.
  int get inventoryUsed => inventory.items.length;

  /// Returns the number of available inventory slots remaining.
  int get inventoryRemaining => inventoryCapacity - inventoryUsed;

  /// Returns true if the inventory is at capacity (no more slots available).
  bool get isInventoryFull => inventoryUsed >= inventoryCapacity;

  /// Returns true if all required inputs for the action are available.
  bool canStartAction(Action action) {
    for (final requirement in action.inputs.entries) {
      final item = itemRegistry.byName(requirement.key);
      final itemCount = inventory.countOfItem(item);
      if (itemCount < requirement.value) {
        return false;
      }
    }
    return true;
  }

  GlobalState startAction(Action action, {Random? random}) {
    // Validate that all required items are available
    for (final requirement in action.inputs.entries) {
      final item = itemRegistry.byName(requirement.key);
      final itemCount = inventory.countOfItem(item);
      if (itemCount < requirement.value) {
        throw Exception(
          'Cannot start ${action.name}: Need ${requirement.value} '
          '${requirement.key}, but only have $itemCount',
        );
      }
    }
    final name = action.name;
    final totalTicks = action.rollDuration(random ?? Random());
    return copyWith(
      activeAction: ActiveAction(
        name: name,
        remainingTicks: totalTicks,
        totalTicks: totalTicks,
      ),
    );
  }

  GlobalState clearAction() {
    // This can't be copyWith since null means no-update.
    return GlobalState(
      inventory: inventory,
      shop: shop,
      activeAction: null,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: DateTime.timestamp(),
      gp: gp,
    );
  }

  GlobalState clearTimeAway() {
    // This can't be copyWith since null means no-update.
    return GlobalState(
      inventory: inventory,
      activeAction: activeAction,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: DateTime.timestamp(),
      gp: gp,
      shop: shop,
    );
  }

  SkillState skillState(Skill skill) =>
      skillStates[skill] ?? SkillState.empty();

  // TODO(eseidel): Implement this.
  int unlockedActionsCount(Skill skill) => 1;

  ActionState actionState(String action) =>
      actionStates[action] ?? const ActionState.empty();

  int activeProgress(Action action) {
    if (activeAction?.name != action.name) {
      return 0;
    }
    return activeAction!.progressTicks;
  }

  GlobalState updateActiveAction(
    String actionName, {
    required int remainingTicks,
  }) {
    final activeAction = this.activeAction;
    if (activeAction == null || activeAction.name != actionName) {
      throw Exception('Active action is not $actionName');
    }
    final newActiveAction = activeAction.copyWith(
      remainingTicks: remainingTicks,
    );
    return copyWith(activeAction: newActiveAction);
  }

  GlobalState addSkillXp(Skill skill, int amount) {
    final oldState = skillState(skill);
    final newState = oldState.copyWith(xp: oldState.xp + amount);
    return _updateSkillState(skill, newState);
  }

  GlobalState addSkillMasteryXp(Skill skill, int amount) {
    final oldState = skillState(skill);
    final newState = oldState.copyWith(masteryXp: oldState.masteryXp + amount);
    return _updateSkillState(skill, newState);
  }

  GlobalState _updateSkillState(Skill skill, SkillState state) {
    final newSkillStates = Map<Skill, SkillState>.from(skillStates);
    newSkillStates[skill] = state;
    return copyWith(skillStates: newSkillStates);
  }

  GlobalState addActionMasteryXp(String actionName, int amount) {
    final oldState = actionState(actionName);
    final newState = oldState.copyWith(masteryXp: oldState.masteryXp + amount);
    final newActionStates = Map<String, ActionState>.from(actionStates);
    newActionStates[actionName] = newState;
    return copyWith(actionStates: newActionStates);
  }

  GlobalState sellItem(ItemStack stack) {
    final newInventory = inventory.removing(stack);
    return copyWith(inventory: newInventory, gp: gp + stack.sellsFor);
  }

  GlobalState copyWith({
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState>? skillStates,
    Map<String, ActionState>? actionStates,
    int? gp,
    TimeAway? timeAway,
    ShopState? shop,
  }) {
    return GlobalState(
      inventory: inventory ?? this.inventory,
      activeAction: activeAction ?? this.activeAction,
      skillStates: skillStates ?? this.skillStates,
      actionStates: actionStates ?? this.actionStates,
      updatedAt: DateTime.timestamp(),
      gp: gp ?? this.gp,
      timeAway: timeAway ?? this.timeAway,
      shop: shop ?? this.shop,
    );
  }
}
