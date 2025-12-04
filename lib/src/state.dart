import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/types/drop.dart';
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
  const ActiveAction({required this.name, required this.progressTicks});

  factory ActiveAction.fromJson(Map<String, dynamic> json) {
    return ActiveAction(
      name: json['name'] as String,
      progressTicks: json['progressTicks'] as int,
    );
  }
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
}

class Action {
  const Action({
    required this.skill,
    required this.name,
    required this.duration,
    required this.xp,
    required this.unlockLevel,
    required this.outputs,
    this.inputs = const {},
  });
  final Skill skill;
  final String name;
  final int xp;
  final int unlockLevel;
  final Duration duration;
  final Map<String, int> inputs;
  final Map<String, int> outputs;
  Tick get maxValue => duration.inMilliseconds ~/ tickDuration.inMilliseconds;

  List<Drop> get rewards => [...outputs.entries.map((e) => Drop(e.key))];
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

class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.activeAction,
    required this.skillStates,
    required this.actionStates,
    required this.updatedAt,
    required this.gp,
    this.timeAway,
    this.inventoryCapacity = 10,
  });

  GlobalState.empty()
    : this(
        inventory: Inventory.empty(),
        activeAction: null,
        skillStates: {},
        actionStates: {},
        updatedAt: DateTime.timestamp(),
        gp: 0,
        timeAway: null,
        inventoryCapacity: 10,
      );

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
      inventoryCapacity = json['inventoryCapacity'] as int? ?? 10;
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
      'inventoryCapacity': inventoryCapacity,
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

  /// The maximum number of unique item types (slots) the inventory can hold.
  /// Items stack unlimited within their slot.
  final int inventoryCapacity;

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

  /// Checks if an item can be added to the inventory.
  /// Returns true if the item can be added, false if it would exceed capacity.
  /// Items that already exist in inventory can always be added (stacking).
  bool canAddItem(ItemStack item) {
    // If item already exists, we can always stack more
    final itemExists = inventory.items.any((i) => i.name == item.name);
    if (itemExists) {
      return true; // Can always stack existing items
    }
    // If item is new, check if we have space for another slot
    return inventoryUsed < inventoryCapacity;
  }

  GlobalState startAction(Action action) {
    // Validate that all required items are available
    for (final requirement in action.inputs.entries) {
      final itemCount = inventory.countOfItem(requirement.key);
      if (itemCount < requirement.value) {
        throw Exception(
          'Cannot start ${action.name}: Need ${requirement.value} '
          '${requirement.key}, but only have $itemCount',
        );
      }
    }
    final name = action.name;
    return copyWith(activeAction: ActiveAction(name: name, progressTicks: 0));
  }

  GlobalState clearAction() {
    // This can't be copyWith since null means no-update.
    return GlobalState(
      inventory: inventory,
      activeAction: null,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: DateTime.timestamp(),
      gp: gp,
      inventoryCapacity: inventoryCapacity,
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
      inventoryCapacity: inventoryCapacity,
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

  GlobalState updateActiveAction(String actionName, int progressTicks) {
    final activeAction = this.activeAction;
    if (activeAction == null || activeAction.name != actionName) {
      throw Exception('Active action is not $actionName');
    }
    final newActiveAction = activeAction.copyWith(progressTicks: progressTicks);
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

  GlobalState sellItem(String itemName, int count) {
    final itemStack = ItemStack(name: itemName, count: count);
    final newInventory = inventory.removing(itemStack);
    // Calculate GP value from items.dart
    final itemData = itemRegistry.byName(itemName);
    final gpEarned = itemData.sellsFor * count;
    return copyWith(inventory: newInventory, gp: gp + gpEarned);
  }

  GlobalState copyWith({
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState>? skillStates,
    Map<String, ActionState>? actionStates,
    int? gp,
    TimeAway? timeAway,
    int? inventoryCapacity,
  }) {
    return GlobalState(
      inventory: inventory ?? this.inventory,
      activeAction: activeAction ?? this.activeAction,
      skillStates: skillStates ?? this.skillStates,
      actionStates: actionStates ?? this.actionStates,
      updatedAt: DateTime.timestamp(),
      gp: gp ?? this.gp,
      timeAway: timeAway ?? this.timeAway,
      inventoryCapacity: inventoryCapacity ?? this.inventoryCapacity,
    );
  }
}
