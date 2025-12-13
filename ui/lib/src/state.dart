import 'dart:math';

import 'package:logic/logic.dart';
import 'package:meta/meta.dart';

export 'package:async_redux/async_redux.dart';
// Re-export types from logic package for backward compatibility
export 'package:logic/logic.dart'
    show
        ActionState,
        CombatActionState,
        MiningState,
        Tick,
        monsterRespawnDuration,
        tickDuration,
        ticksFromDuration;

@immutable
class ActiveAction {
  const ActiveAction({
    required this.name,
    required this.remainingTicks,
    required this.totalTicks,
  });

  factory ActiveAction.fromJson(Map<String, dynamic> json) {
    return ActiveAction(
      name: json['name'] as String,
      remainingTicks: json['remainingTicks'] as int,
      totalTicks: json['totalTicks'] as int,
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

/// Per-skill serialized state.
@immutable
class SkillState {
  const SkillState({required this.xp, required this.masteryXp});

  const SkillState.empty() : this(xp: 0, masteryXp: 0);

  SkillState.fromJson(Map<String, dynamic> json)
    : xp = json['xp'] as int,
      masteryXp = json['masteryXp'] as int;

  // Skill xp accumulated for this Skill, determines skill level.
  final int xp;

  /// Mastery xp accumulated for this Skill, determines mastery level.
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

/// Used for serializing the state of the Shop (what has been purchased).
@immutable
class ShopState {
  const ShopState({required this.bankSlots});

  const ShopState.empty() : this(bankSlots: 0);

  factory ShopState.fromJson(Map<String, dynamic> json) {
    return ShopState(bankSlots: json['bankSlots'] as int);
  }

  /// How many bank slots the player has purchased.
  final int bankSlots;

  ShopState copyWith({int? bankSlots}) {
    return ShopState(bankSlots: bankSlots ?? this.bankSlots);
  }

  Map<String, dynamic> toJson() {
    return {'bankSlots': bankSlots};
  }

  /// What the next bank slot will cost.
  int nextBankSlotCost() {
    // https://wiki.melvoridle.com/w/Bank
    // C_b = \left \lfloor \frac{132\,728\,500 \times (n+2)}{142\,015^{\left (\frac{163}{122+n} \right )}}\right \rfloor
    final n = bankSlots;
    final cost = (132728500 * (n + 2) / pow(142015, 163 / (122 + n))).floor();
    return cost.clamp(0, 5000000);
  }
}

/// The initial number of free bank slots.
const int initialBankSlots = 20;

/// Fixed player stats for now.
Stats playerStats(GlobalState state) {
  return const Stats(minHit: 1, maxHit: 23, damageReduction: 0, attackSpeed: 4);
}

/// Maximum player HP.
const int maxPlayerHp = 100;

/// Primary state object serialized to disk and used in memory.
@immutable
class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.activeAction,
    required this.skillStates,
    required this.actionStates,
    required this.updatedAt,
    required this.gp,
    required this.shop,
    required this.playerHp,
    this.timeAway,
  });

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
          : const ShopState.empty(),
      playerHp = json['playerHp'] as int? ?? maxPlayerHp;

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
        playerHp: maxPlayerHp,
      );

  @visibleForTesting
  factory GlobalState.test({
    Inventory inventory = const Inventory.empty(),
    ActiveAction? activeAction,
    Map<Skill, SkillState> skillStates = const {},
    Map<String, ActionState> actionStates = const {},
    DateTime? updatedAt,
    int gp = 0,
    TimeAway? timeAway,
    ShopState shop = const ShopState.empty(),
    int playerHp = maxPlayerHp,
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
      playerHp: playerHp,
    );
  }

  bool validate() {
    // Confirm that activeAction.name is a valid action.
    final actionName = activeAction?.name;
    if (actionName != null) {
      // This will throw a StateError if the action is missing.
      actionRegistry.byName(actionName);
    }
    return true;
  }

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
      'playerHp': playerHp,
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

  /// The current player HP.
  final int playerHp;

  int get inventoryCapacity => shop.bankSlots + initialBankSlots;

  bool get isActive => activeAction != null;

  /// Returns true if there are any active mining timers (respawn or regen).
  bool get hasActiveResourceTimers {
    for (final actionState in actionStates.values) {
      final mining = actionState.mining;
      if (mining == null) continue;

      // Check for active respawn timer
      if (mining.respawnTicksRemaining != null &&
          mining.respawnTicksRemaining! > 0) {
        return true;
      }
      // Check for active HP regeneration
      if (mining.totalHpLost > 0) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if the game loop should be running.
  bool get shouldTick => isActive || hasActiveResourceTimers;

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
    // Only SkillActions have inputs to check
    if (action is SkillAction) {
      // Check inputs
      for (final requirement in action.inputs.entries) {
        final item = itemRegistry.byName(requirement.key);
        final itemCount = inventory.countOfItem(item);
        if (itemCount < requirement.value) {
          return false;
        }
      }

      // Check if mining node is depleted
      if (action is MiningAction) {
        final actionState = this.actionState(action.name);
        final miningState = actionState.mining ?? const MiningState.empty();
        if (miningState.isDepleted) {
          return false; // Can't mine depleted node
        }
      }
    }

    // CombatActions can always be started
    return true;
  }

  GlobalState startAction(Action action, {Random? random}) {
    final name = action.name;
    int totalTicks;

    if (action is SkillAction) {
      // Validate that all required items are available for skill actions
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
      totalTicks = action.rollDuration(random ?? Random());
      return copyWith(
        activeAction: ActiveAction(
          name: name,
          remainingTicks: totalTicks,
          totalTicks: totalTicks,
        ),
      );
    } else if (action is CombatAction) {
      // Combat actions don't have inputs or duration-based completion.
      // The tick represents the time until the first player attack.
      final pStats = playerStats(this);
      totalTicks = ticksFromDuration(
        Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
      );
      // Initialize combat state with the combat action
      final combatState = CombatActionState.start(action, pStats);
      final newActionStates = Map<String, ActionState>.from(actionStates);
      final existingState = actionState(name);
      newActionStates[name] = existingState.copyWith(combat: combatState);
      return copyWith(
        activeAction: ActiveAction(
          name: name,
          remainingTicks: totalTicks,
          totalTicks: totalTicks,
        ),
        actionStates: newActionStates,
      );
    } else {
      throw Exception('Unknown action type: ${action.runtimeType}');
    }
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
      playerHp: playerHp,
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
      playerHp: playerHp,
    );
  }

  SkillState skillState(Skill skill) =>
      skillStates[skill] ?? const SkillState.empty();

  // TODO(eseidel): Implement this.
  int unlockedActionsCount(Skill skill) => 1;

  ActionState actionState(String action) =>
      actionStates[action] ?? const ActionState.empty();

  int activeProgress(Action action) {
    final active = activeAction;
    if (active == null || active.name != action.name) {
      return 0;
    }
    return active.progressTicks;
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
    int? playerHp,
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
      playerHp: playerHp ?? this.playerHp,
    );
  }
}
