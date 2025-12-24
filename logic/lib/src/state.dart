import 'dart:math';

import 'package:logic/src/action_state.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/equipment.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/health.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/modifier_old.dart';
import 'package:logic/src/types/resolved_modifiers.dart';
import 'package:logic/src/types/open_result.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:logic/src/types/time_away.dart';
import 'package:meta/meta.dart';

import 'data/xp.dart';

@immutable
class ActiveAction {
  const ActiveAction({
    required this.id,
    required this.remainingTicks,
    required this.totalTicks,
  });

  static ActiveAction? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return ActiveAction.fromJson(json as Map<String, dynamic>);
  }

  factory ActiveAction.fromJson(Map<String, dynamic> json) {
    return ActiveAction(
      id: MelvorId.fromJson(json['id'] as String),
      remainingTicks: json['remainingTicks'] as int,
      totalTicks: json['totalTicks'] as int,
    );
  }

  /// The action ID (matches Action.id).
  final MelvorId id;
  final int remainingTicks;
  final int totalTicks;

  // Computed getter for backward compatibility
  int get progressTicks => totalTicks - remainingTicks;

  ActiveAction copyWith({MelvorId? id, int? remainingTicks, int? totalTicks}) {
    return ActiveAction(
      id: id ?? this.id,
      remainingTicks: remainingTicks ?? this.remainingTicks,
      totalTicks: totalTicks ?? this.totalTicks,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'remainingTicks': remainingTicks,
    'totalTicks': totalTicks,
  };
}

/// Per-skill serialized state.
@immutable
class SkillState {
  const SkillState({required this.xp, required this.masteryPoolXp});

  const SkillState.empty() : this(xp: 0, masteryPoolXp: 0);

  SkillState.fromJson(Map<String, dynamic> json)
    : xp = json['xp'] as int,
      masteryPoolXp = json['masteryPoolXp'] as int;

  // Skill xp accumulated for this Skill, determines skill level.
  final int xp;

  /// The level for this skill, derived from XP.
  int get skillLevel => levelForXp(xp);

  /// Mastery pool xp, accumulated for this skill
  /// Can be spent to gain mastery levels for actions within this skill.
  final int masteryPoolXp;

  SkillState copyWith({int? xp, int? masteryPoolXp}) {
    return SkillState(
      xp: xp ?? this.xp,
      masteryPoolXp: masteryPoolXp ?? this.masteryPoolXp,
    );
  }

  Map<String, dynamic> toJson() {
    return {'xp': xp, 'masteryPoolXp': masteryPoolXp};
  }
}

/// Used for serializing the state of the Shop (what has been purchased).
@immutable
class ShopState {
  const ShopState({required this.purchaseCounts});

  const ShopState.empty() : purchaseCounts = const {};

  static ShopState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return ShopState.fromJson(json as Map<String, dynamic>);
  }

  factory ShopState.fromJson(Map<String, dynamic> json) {
    final countsJson = json['purchaseCounts'] as Map<String, dynamic>? ?? {};
    final counts = <MelvorId, int>{};
    for (final entry in countsJson.entries) {
      counts[MelvorId.fromJson(entry.key)] = entry.value as int;
    }
    return ShopState(purchaseCounts: counts);
  }

  /// Map of purchase ID to count purchased.
  final Map<MelvorId, int> purchaseCounts;

  /// Returns how many times a purchase has been made.
  int purchaseCount(MelvorId purchaseId) => purchaseCounts[purchaseId] ?? 0;

  /// Returns true if the player owns at least one of this purchase.
  bool owns(MelvorId purchaseId) => purchaseCount(purchaseId) > 0;

  /// Returns the number of bank slots purchased (Extra_Bank_Slot purchase).
  int get bankSlotsPurchased =>
      purchaseCount(MelvorId('melvorD:Extra_Bank_Slot'));

  // Axe tier IDs in order
  static const _axeIds = [
    'melvorD:Iron_Axe',
    'melvorD:Steel_Axe',
    'melvorD:Black_Axe',
    'melvorD:Mithril_Axe',
    'melvorD:Adamant_Axe',
    'melvorD:Rune_Axe',
    'melvorD:Dragon_Axe',
  ];

  // Fishing rod tier IDs in order
  static const _rodIds = [
    'melvorD:Iron_Fishing_Rod',
    'melvorD:Steel_Fishing_Rod',
    'melvorD:Black_Fishing_Rod',
    'melvorD:Mithril_Fishing_Rod',
    'melvorD:Adamant_Fishing_Rod',
    'melvorD:Rune_Fishing_Rod',
    'melvorD:Dragon_Fishing_Rod',
  ];

  // Pickaxe tier IDs in order
  static const _pickaxeIds = [
    'melvorD:Iron_Pickaxe',
    'melvorD:Steel_Pickaxe',
    'melvorD:Black_Pickaxe',
    'melvorD:Mithril_Pickaxe',
    'melvorD:Adamant_Pickaxe',
    'melvorD:Rune_Pickaxe',
    'melvorD:Dragon_Pickaxe',
  ];

  /// Returns how many axe tiers have been purchased (0-7).
  int get axeLevel => _countTiersOwned(_axeIds);

  /// Returns how many fishing rod tiers have been purchased (0-7).
  int get fishingRodLevel => _countTiersOwned(_rodIds);

  /// Returns how many pickaxe tiers have been purchased (0-7).
  int get pickaxeLevel => _countTiersOwned(_pickaxeIds);

  int _countTiersOwned(List<String> tierIds) {
    var count = 0;
    for (final id in tierIds) {
      if (owns(MelvorId(id))) count++;
    }
    return count;
  }

  /// Returns a new ShopState with the given purchase incremented.
  ShopState withPurchase(MelvorId purchaseId, {int count = 1}) {
    final newCounts = Map<MelvorId, int>.from(purchaseCounts);
    newCounts[purchaseId] = (newCounts[purchaseId] ?? 0) + count;
    return ShopState(purchaseCounts: newCounts);
  }

  Map<String, dynamic> toJson() {
    final countsJson = <String, dynamic>{};
    for (final entry in purchaseCounts.entries) {
      countsJson[entry.key.toJson()] = entry.value;
    }
    return {'purchaseCounts': countsJson};
  }

  /// Returns the total skill interval modifier for a skill from owned purchases.
  /// Uses the shop registry to look up which purchases affect this skill.
  int totalSkillIntervalModifier(Skill skill, ShopRegistry registry) {
    return registry.totalSkillIntervalModifier(skill, purchaseCounts);
  }

  /// Returns the cost for the next bank slot purchase.
  int nextBankSlotCost() {
    return calculateBankSlotCost(bankSlotsPurchased);
  }
}

/// The initial number of free bank slots.
const int initialBankSlots = 20;

/// Fixed player stats for now.
Stats playerStats(GlobalState state) {
  return const Stats(minHit: 1, maxHit: 23, damageReduction: 0, attackSpeed: 4);
}

/// Primary state object serialized to disk and used in memory.
@immutable
class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.activeAction,
    required this.skillStates,
    required this.actionStates,
    required this.updatedAt,
    required this.currencies,
    required this.shop,
    required this.health,
    required this.equipment,
    this.timeAway,
    this.stunned = const StunnedState.fresh(),
    required this.registries,
  });

  GlobalState.fromJson(this.registries, Map<String, dynamic> json)
    : updatedAt = DateTime.parse(json['updatedAt'] as String),
      inventory = Inventory.fromJson(
        registries.items,
        json['inventory'] as Map<String, dynamic>,
      ),
      activeAction = ActiveAction.maybeFromJson(json['activeAction']),
      skillStates =
          maybeMap(
            json['skillStates'],
            toKey: Skill.fromName,
            toValue: (value) => SkillState.fromJson(value),
          ) ??
          const {},
      actionStates =
          maybeMap(
            json['actionStates'],
            toValue: (value) => ActionState.fromJson(value),
          ) ??
          const {},
      currencies = _currenciesFromJson(json),
      timeAway = TimeAway.maybeFromJson(registries, json['timeAway']),
      shop = ShopState.maybeFromJson(json['shop']) ?? const ShopState.empty(),
      health =
          HealthState.maybeFromJson(json['health']) ?? const HealthState.full(),
      equipment =
          Equipment.maybeFromJson(registries.items, json['equipment']) ??
          const Equipment.empty(),
      stunned =
          StunnedState.maybeFromJson(json['stunned']) ??
          const StunnedState.fresh();

  static Map<Currency, int> _currenciesFromJson(Map<String, dynamic> json) {
    final currenciesJson = json['currencies'] as Map<String, dynamic>? ?? {};
    return currenciesJson.map((key, value) {
      final currency = Currency.fromId(key);
      return MapEntry(currency, value as int);
    });
  }

  GlobalState.empty(Registries registries)
    : this(
        inventory: Inventory.empty(registries.items),
        activeAction: null,
        // Start with level 10 Hitpoints (1154 XP) for 100 HP
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
        },
        actionStates: {},
        updatedAt: DateTime.timestamp(),
        currencies: const {},
        timeAway: null,
        shop: const ShopState.empty(),
        health: const HealthState.full(),
        equipment: const Equipment.empty(),
        registries: registries,
      );

  @visibleForTesting
  factory GlobalState.test(
    Registries registries, {
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState> skillStates = const {},
    Map<MelvorId, ActionState> actionStates = const {},
    DateTime? updatedAt,
    int gp = 0,
    Map<Currency, int>? currencies,
    TimeAway? timeAway,
    ShopState shop = const ShopState.empty(),
    HealthState health = const HealthState.full(),
    Equipment equipment = const Equipment.empty(),
    StunnedState stunned = const StunnedState.fresh(),
  }) {
    // Support both gp parameter (for existing tests) and currencies map
    final currenciesMap = currencies ?? (gp > 0 ? {Currency.gp: gp} : const {});
    return GlobalState(
      registries: registries,
      inventory: inventory ?? Inventory.empty(registries.items),
      activeAction: activeAction,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: updatedAt ?? DateTime.timestamp(),
      currencies: currenciesMap,
      timeAway: timeAway,
      shop: shop,
      health: health,
      equipment: equipment,
      stunned: stunned,
    );
  }

  bool validate() {
    // Confirm that activeAction.id is a valid action.
    final actionId = activeAction?.id;
    if (actionId != null) {
      // This will throw a StateError if the action is missing.
      registries.actions.byId(actionId);
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
      'currencies': currencies.map((key, value) => MapEntry(key.id, value)),
      'timeAway': timeAway?.toJson(),
      'shop': shop.toJson(),
      'health': health.toJson(),
      'equipment': equipment.toJson(),
      'stunned': stunned.toJson(),
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
  final Map<MelvorId, ActionState> actionStates;

  /// The player's currencies (GP, Slayer Coins, etc.).
  final Map<Currency, int> currencies;

  /// The current gold pieces (GP) the player has, convenience getter.
  /// Callers need to be careful not to ignore other currencies.
  int get gp => currency(Currency.gp);

  /// Gets the amount of a specific currency.
  int currency(Currency type) => currencies[type] ?? 0;

  /// Time away represents the accumulated changes since the last time the
  /// user interacted with the app.  It is persisted to disk, for the case in
  /// which the user kills the app with the "welcome back" dialog open.
  final TimeAway? timeAway;

  /// The shop state.
  final ShopState shop;

  /// The player's health state.
  final HealthState health;

  /// This is the game data used to load the state.
  final Registries registries;

  /// The player's maximum HP (computed from Hitpoints skill level).
  /// Each Hitpoints level grants 10 HP.
  int get maxPlayerHp {
    final hitpointsLevel = skillState(Skill.hitpoints).skillLevel;
    return hitpointsLevel * 10;
  }

  /// The current player HP (computed from maxPlayerHp - lostHp).
  int get playerHp => (maxPlayerHp - health.lostHp).clamp(0, maxPlayerHp);

  /// The player's equipped items.
  final Equipment equipment;

  /// The player's stunned state.
  final StunnedState stunned;

  /// Whether the player is currently stunned.
  bool get isStunned => stunned.isStunned;

  int get inventoryCapacity => shop.bankSlotsPurchased + initialBankSlots;

  bool get isActive => activeAction != null;

  /// Returns true if there are any active background timers
  /// (mining respawn/regen, player HP regen, stunned countdown).
  bool get hasActiveBackgroundTimers {
    // Check stunned countdown
    if (isStunned) {
      return true;
    }

    // Check player HP regeneration
    if (health.lostHp > 0) {
      return true;
    }

    // Check mining node timers
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
  bool get shouldTick => isActive || hasActiveBackgroundTimers;

  Skill? activeSkill() {
    final actionId = activeAction?.id;
    if (actionId == null) {
      return null;
    }
    return registries.actions.byId(actionId).skill;
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
        final item = registries.items.byId(requirement.key);
        final itemCount = inventory.countOfItem(item);
        if (itemCount < requirement.value) {
          return false;
        }
      }

      // Check if mining node is depleted
      if (action is MiningAction) {
        final actionState = this.actionState(action.id);
        final miningState = actionState.mining ?? const MiningState.empty();
        if (miningState.isDepleted) {
          return false; // Can't mine depleted node
        }
      }
    }

    // CombatActions can always be started
    return true;
  }

  /// Returns the shop duration modifier for a skill as a decimal fraction.
  /// For example, -0.05 means 5% reduction.
  /// This is a convenience method that combines ShopState and ShopRegistry.
  double shopDurationModifierForSkill(Skill skill) {
    return shop.totalSkillIntervalModifier(skill, registries.shop) / 100.0;
  }

  /// Resolves mastery-based skill interval modifiers for an action.
  ///
  /// Reads from [MasteryBonusRegistry] and evaluates which bonuses apply
  /// based on the current mastery level. Returns resolved flat and percentage
  /// modifiers that affect action duration.
  ResolvedModifiers resolveMasteryModifiers(SkillAction action) {
    final masteryLevel = actionState(action.id).masteryLevel;
    final skillBonuses = registries.masteryBonuses.forSkill(action.skill.id);
    if (skillBonuses == null) return ResolvedModifiers.empty;

    var flatMs = 0;
    var percent = 0.0;

    for (final bonus in skillBonuses.bonuses) {
      final count = bonus.countAtLevel(masteryLevel);
      if (count == 0) continue;

      // Handle flatSkillInterval (flat milliseconds)
      final flatMod = bonus.modifiers.byName('flatSkillInterval');
      if (flatMod != null) {
        for (final entry in flatMod.entries) {
          final scope = entry.scope;
          if (scope == null ||
              scope.matchesSkillForMastery(
                action.skill.id,
                autoScopeToAction: bonus.autoScopeToAction,
              )) {
            flatMs += (entry.value * count).toInt();
          }
        }
      }

      // Handle skillInterval (percentage points, e.g., -5 = -5%)
      final percentMod = bonus.modifiers.byName('skillInterval');
      if (percentMod != null) {
        for (final entry in percentMod.entries) {
          final scope = entry.scope;
          if (scope == null ||
              scope.matchesSkillForMastery(
                action.skill.id,
                autoScopeToAction: bonus.autoScopeToAction,
              )) {
            percent += entry.value * count;
          }
        }
      }
    }

    return ResolvedModifiers(
      flatSkillIntervalMs: flatMs,
      // Convert percentage points to decimal (e.g., -5 -> -0.05)
      skillIntervalPercent: percent / 100.0,
    );
  }

  /// Rolls duration for a skill action and applies all relevant modifiers.
  /// This centralizes duration modifier logic for shop upgrades and mastery.
  /// Percentage modifiers are applied first, then flat modifiers.
  int rollDurationWithModifiers(
    SkillAction action,
    Random random,
    ShopRegistry shopRegistry,
  ) {
    final ticks = action.rollDuration(random);

    // Collect all modifiers
    final modifiers = <ModifierOld>[];

    // Shop upgrade modifiers (percentage only)
    // The totalSkillIntervalModifier returns percentage points (e.g., -5 for 5% reduction)
    // Convert to Modifier.percent format (-0.05 = 5% reduction)
    final shopModifier = shop.totalSkillIntervalModifier(
      action.skill,
      shopRegistry,
    );
    if (shopModifier != 0) {
      modifiers.add(ModifierOld(percent: shopModifier / 100.0));
    }

    // Mastery-based modifiers from data (can include both percent and flat)
    final masteryModifier = resolveMasteryModifiers(action).toModifierOld();
    if (!masteryModifier.isEmpty) {
      modifiers.add(masteryModifier);
    }

    // Combine and apply all modifiers
    if (modifiers.isEmpty) {
      return ticks;
    }

    final combined = ModifierOld.combineAll(modifiers);
    return combined.applyToInt(ticks);
  }

  GlobalState startAction(Action action, {required Random random}) {
    if (isStunned) {
      throw const StunnedException('Cannot start action while stunned');
    }

    final actionId = action.id;
    int totalTicks;

    if (action is SkillAction) {
      // Validate that all required items are available for skill actions
      for (final requirement in action.inputs.entries) {
        final item = registries.items.byId(requirement.key);
        final itemCount = inventory.countOfItem(item);
        if (itemCount < requirement.value) {
          throw Exception(
            'Cannot start ${action.name}: Need ${requirement.value} '
            '${requirement.key.name}, but only have $itemCount',
          );
        }
      }
      totalTicks = rollDurationWithModifiers(action, random, registries.shop);
      return copyWith(
        activeAction: ActiveAction(
          id: actionId,
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
      final newActionStates = Map<MelvorId, ActionState>.from(actionStates);
      final existingState = actionState(actionId);
      newActionStates[actionId] = existingState.copyWith(combat: combatState);
      return copyWith(
        activeAction: ActiveAction(
          id: actionId,
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
    if (isStunned) {
      throw const StunnedException('Cannot stop action while stunned');
    }

    // This can't be copyWith since null means no-update.
    return GlobalState(
      registries: registries,
      inventory: inventory,
      shop: shop,
      activeAction: null,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: DateTime.timestamp(),
      currencies: currencies,
      health: health,
      equipment: equipment,
      stunned: stunned,
    );
  }

  GlobalState clearTimeAway() {
    // This can't be copyWith since null means no-update.
    return GlobalState(
      registries: registries,
      inventory: inventory,
      activeAction: activeAction,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: DateTime.timestamp(),
      currencies: currencies,
      shop: shop,
      health: health,
      equipment: equipment,
      stunned: stunned,
    );
  }

  SkillState skillState(Skill skill) =>
      skillStates[skill] ?? const SkillState.empty();

  // TODO(eseidel): Implement this.
  int unlockedActionsCount(Skill skill) => 1;

  ActionState actionState(MelvorId action) =>
      actionStates[action] ?? const ActionState.empty();

  int activeProgress(Action action) {
    final active = activeAction;
    if (active == null || active.id != action.id) {
      return 0;
    }
    return active.progressTicks;
  }

  GlobalState updateActiveAction(
    MelvorId actionId, {
    required int remainingTicks,
  }) {
    final activeAction = this.activeAction;
    if (activeAction == null || activeAction.id != actionId) {
      throw Exception('Active action is not $actionId');
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
    final newState = oldState.copyWith(
      masteryPoolXp: oldState.masteryPoolXp + amount,
    );
    return _updateSkillState(skill, newState);
  }

  GlobalState _updateSkillState(Skill skill, SkillState state) {
    final newSkillStates = Map<Skill, SkillState>.from(skillStates);
    newSkillStates[skill] = state;
    return copyWith(skillStates: newSkillStates);
  }

  GlobalState addActionMasteryXp(MelvorId actionId, int amount) {
    final oldState = actionState(actionId);
    final newState = oldState.copyWith(masteryXp: oldState.masteryXp + amount);
    final newActionStates = Map<MelvorId, ActionState>.from(actionStates);
    newActionStates[actionId] = newState;
    return copyWith(actionStates: newActionStates);
  }

  GlobalState sellItem(ItemStack stack) {
    final newInventory = inventory.removing(stack);
    return addCurrency(
      Currency.gp,
      stack.sellsFor,
    ).copyWith(inventory: newInventory);
  }

  /// Adds an amount of a specific currency.
  GlobalState addCurrency(Currency type, int amount) {
    final newCurrencies = Map<Currency, int>.from(currencies);
    newCurrencies[type] = (newCurrencies[type] ?? 0) + amount;
    return copyWith(currencies: newCurrencies);
  }

  /// Equips food from the inventory to an equipment slot.
  /// Removes the item from inventory and adds it to equipment.
  GlobalState equipFood(ItemStack stack) {
    if (!equipment.canEquipFood(stack.item)) {
      throw StateError('Cannot equip food: ${stack.item.name}');
    }
    final newInventory = inventory.removing(stack);
    final newEquipment = equipment.equipFood(stack);
    return copyWith(inventory: newInventory, equipment: newEquipment);
  }

  /// Unequips food from an equipment slot and moves it to inventory.
  /// Throws StateError if inventory is full and can't accept the item.
  /// Throws ArgumentError if the slot is empty or index is invalid.
  GlobalState unequipFood(int slotIndex) {
    final result = equipment.unequipFood(slotIndex);
    if (result == null) {
      throw ArgumentError('No food in slot $slotIndex to unequip');
    }
    final (food, newEquipment) = result;
    if (!inventory.canAdd(food.item, capacity: inventoryCapacity)) {
      throw StateError('Inventory is full, cannot unequip ${food.item.name}');
    }
    final newInventory = inventory.adding(food);
    return copyWith(inventory: newInventory, equipment: newEquipment);
  }

  /// Eats the currently selected food, healing the player.
  /// Returns null if no food is selected or player is at full health.
  GlobalState? eatSelectedFood() {
    final food = equipment.selectedFood;
    if (food == null) return null;

    final healAmount = food.item.healsFor;
    if (healAmount == null) return null;

    // Don't eat if already at full health
    if (health.isFullHealth) return null;

    final newEquipment = equipment.consumeSelectedFood();
    if (newEquipment == null) return null;

    final newHealth = health.heal(healAmount);
    return copyWith(equipment: newEquipment, health: newHealth);
  }

  /// Selects a food equipment slot.
  GlobalState selectFoodSlot(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= foodSlotCount) {
      throw ArgumentError('Invalid food slot index: $slotIndex');
    }
    return copyWith(equipment: equipment.copyWith(selectedFoodSlot: slotIndex));
  }

  /// Equips a gear item from inventory to a specific equipment slot.
  /// Removes one item from inventory and equips it.
  /// If there was an item in that slot, it's returned to inventory.
  /// Throws StateError if player doesn't have the item or inventory is full
  /// when swapping.
  GlobalState equipGear(Item item, EquipmentSlot slot) {
    if (!item.isEquippable) {
      throw StateError('Cannot equip ${item.name}: not equippable');
    }
    if (!item.canEquipInSlot(slot)) {
      throw StateError(
        'Cannot equip ${item.name} in $slot slot. '
        'Valid slots: ${item.validSlots}',
      );
    }
    if (inventory.countOfItem(item) < 1) {
      throw StateError('Cannot equip ${item.name}: not in inventory');
    }

    // Check if we're swapping and have room in inventory
    final previousItem = equipment.gearInSlot(slot);
    if (previousItem != null) {
      if (!inventory.canAdd(previousItem, capacity: inventoryCapacity)) {
        throw StateError(
          'Inventory is full, cannot swap ${previousItem.name} for '
          '${item.name}',
        );
      }
    }

    // Remove item from inventory
    var newInventory = inventory.removing(ItemStack(item, count: 1));

    // Equip the item
    final (newEquipment, swappedItem) = equipment.equipGear(item, slot);

    // Add swapped item back to inventory if there was one
    if (swappedItem != null) {
      newInventory = newInventory.adding(ItemStack(swappedItem, count: 1));
    }

    return copyWith(inventory: newInventory, equipment: newEquipment);
  }

  /// Unequips gear from a specific slot and moves it to inventory.
  /// Throws StateError if inventory is full.
  /// Returns null if the slot is empty.
  GlobalState? unequipGear(EquipmentSlot slot) {
    final result = equipment.unequipGear(slot);
    if (result == null) return null;

    final (item, newEquipment) = result;
    if (!inventory.canAdd(item, capacity: inventoryCapacity)) {
      throw StateError('Inventory is full, cannot unequip ${item.name}');
    }
    final newInventory = inventory.adding(ItemStack(item, count: 1));
    return copyWith(inventory: newInventory, equipment: newEquipment);
  }

  /// Opens openable items and adds the resulting drops to inventory.
  /// Opens items one by one until inventory is full or count is reached.
  /// Returns (newState, OpenResult) with combined drops and any error.
  /// Throws StateError if player doesn't have the item or item is not openable.
  (GlobalState, OpenResult) openItems(
    Item item, {
    required int count,
    required Random random,
  }) {
    if (!item.isOpenable) {
      throw StateError('Cannot open ${item.name}: not an openable item');
    }

    final availableCount = inventory.countOfItem(item);
    if (availableCount < 1) {
      throw StateError('Cannot open ${item.name}: not in inventory');
    }

    // Clamp count to available
    final toOpen = count.clamp(1, availableCount);

    var currentInventory = inventory;
    var result = const OpenResult(openedCount: 0, drops: {});

    for (var i = 0; i < toOpen; i++) {
      // Roll the drop for this item
      final drop = item.open(registries.items, random);

      // Check if we can add the drop
      if (!currentInventory.canAdd(drop.item, capacity: inventoryCapacity)) {
        result = result.withError('Inventory full');
        break;
      }

      // Remove one openable and add the drop
      currentInventory = currentInventory
          .removing(ItemStack(item, count: 1))
          .adding(drop);
      result = result.addDrop(drop);
    }

    return (copyWith(inventory: currentInventory), result);
  }

  GlobalState copyWith({
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState>? skillStates,
    Map<MelvorId, ActionState>? actionStates,
    Map<Currency, int>? currencies,
    int? gp, // Convenience parameter for setting GP directly
    TimeAway? timeAway,
    ShopState? shop,
    HealthState? health,
    Equipment? equipment,
    StunnedState? stunned,
  }) {
    // Handle gp convenience parameter
    var newCurrencies = currencies ?? this.currencies;
    if (gp != null) {
      newCurrencies = Map<Currency, int>.from(newCurrencies);
      newCurrencies[Currency.gp] = gp;
    }
    return GlobalState(
      registries: registries,
      inventory: inventory ?? this.inventory,
      activeAction: activeAction ?? this.activeAction,
      skillStates: skillStates ?? this.skillStates,
      actionStates: actionStates ?? this.actionStates,
      updatedAt: DateTime.timestamp(),
      currencies: newCurrencies,
      timeAway: timeAway ?? this.timeAway,
      shop: shop ?? this.shop,
      health: health ?? this.health,
      equipment: equipment ?? this.equipment,
      stunned: stunned ?? this.stunned,
    );
  }
}
