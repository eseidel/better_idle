import 'dart:math';

import 'package:logic/src/action_state.dart';
import 'package:logic/src/combat_stats.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/plot_state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/equipment.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/health.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/open_result.dart';
import 'package:logic/src/types/resolved_modifiers.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:logic/src/types/time_away.dart';
import 'package:meta/meta.dart';

/// The type of combat the player is using.
///
/// Determines which skill levels affect combat calculations and which
/// equipment bonuses apply.
enum CombatType {
  /// Melee combat using Attack, Strength, Defence skills.
  melee,

  /// Ranged combat using Ranged skill.
  ranged,

  /// Magic combat using Magic skill.
  magic;

  factory CombatType.fromJson(String value) {
    return CombatType.values.firstWhere((e) => e.name == value);
  }

  String toJson() => name;
}

/// The player's selected melee attack style for combat XP distribution.
///
/// Each style determines which combat skill receives XP from damage dealt:
/// - [stab]: Attack XP (4 XP per damage)
/// - [slash]: Strength XP (4 XP per damage)
/// - [block]: Defence XP (4 XP per damage)
/// - [controlled]: Split XP to all three (1.33 XP per damage each)
///
/// Hitpoints always receives XP regardless of style (1.33 XP per damage).
enum AttackStyle {
  // Melee styles
  stab,
  slash,
  block,
  controlled,

  // Ranged styles
  /// Accurate: Ranged XP, +3 effective Ranged level for accuracy.
  accurate,

  /// Rapid: Ranged XP, faster attack speed.
  rapid,

  /// LongRange: Ranged + Defence XP, +3 effective Defence level.
  longRange,

  // Magic styles
  /// Standard: Magic XP, balanced magic combat.
  standard,

  /// Defensive: Magic + Defence XP, +3 effective Defence level.
  defensive;

  factory AttackStyle.fromJson(String value) {
    return switch (value) {
      // Melee styles
      'stab' => AttackStyle.stab,
      'slash' => AttackStyle.slash,
      'block' => AttackStyle.block,
      'controlled' => AttackStyle.controlled,
      // Ranged styles
      'accurate' => AttackStyle.accurate,
      'rapid' => AttackStyle.rapid,
      // Melvor Idle uses "longrange" for longRange.
      // cspell:ignore longrange
      'longrange' || 'longRange' => AttackStyle.longRange,
      // Magic styles
      'standard' => AttackStyle.standard,
      'defensive' => AttackStyle.defensive,
      _ => throw ArgumentError('Invalid attack style: $value'),
    };
  }

  String toJson() => name;

  /// Returns the combat type for this attack style.
  CombatType get combatType {
    return switch (this) {
      stab || slash || block || controlled => CombatType.melee,
      accurate || rapid || longRange => CombatType.ranged,
      standard || defensive => CombatType.magic,
    };
  }

  /// Returns true if this is a melee attack style.
  bool get isMelee => combatType == CombatType.melee;

  /// Returns true if this is a ranged attack style.
  bool get isRanged => combatType == CombatType.ranged;

  /// Returns true if this is a magic attack style.
  bool get isMagic => combatType == CombatType.magic;
}

@immutable
class ActiveAction {
  const ActiveAction({
    required this.id,
    required this.remainingTicks,
    required this.totalTicks,
  });

  factory ActiveAction.fromJson(Map<String, dynamic> json) {
    return ActiveAction(
      id: ActionId.fromJson(json['id'] as String),
      remainingTicks: json['remainingTicks'] as int,
      totalTicks: json['totalTicks'] as int,
    );
  }

  static ActiveAction? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return ActiveAction.fromJson(json as Map<String, dynamic>);
  }

  final ActionId id;
  final int remainingTicks;
  final int totalTicks;

  int get progressTicks => totalTicks - remainingTicks;

  ActiveAction copyWith({ActionId? id, int? remainingTicks, int? totalTicks}) {
    return ActiveAction(
      id: id ?? this.id,
      remainingTicks: remainingTicks ?? this.remainingTicks,
      totalTicks: totalTicks ?? this.totalTicks,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
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

  factory ShopState.fromJson(Map<String, dynamic> json) {
    final countsJson = json['purchaseCounts'] as Map<String, dynamic>? ?? {};
    final counts = <MelvorId, int>{};
    for (final entry in countsJson.entries) {
      counts[MelvorId.fromJson(entry.key)] = entry.value as int;
    }
    return ShopState(purchaseCounts: counts);
  }

  const ShopState.empty() : purchaseCounts = const {};

  static ShopState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return ShopState.fromJson(json as Map<String, dynamic>);
  }

  /// Map of purchase ID to count purchased.
  final Map<MelvorId, int> purchaseCounts;

  /// Returns how many times a purchase has been made.
  int purchaseCount(MelvorId purchaseId) => purchaseCounts[purchaseId] ?? 0;

  /// Returns true if the player owns at least one of this purchase.
  bool owns(MelvorId purchaseId) => purchaseCount(purchaseId) > 0;

  /// Returns the number of bank slots purchased (Extra_Bank_Slot purchase).
  int get bankSlotsPurchased =>
      purchaseCount(const MelvorId('melvorD:Extra_Bank_Slot'));

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

  /// Total skill interval modifier for a skill from owned purchases.
  /// Uses the shop registry to look up which purchases affect this skill.
  int totalSkillIntervalModifier(Skill skill, ShopRegistry registry) {
    return registry.totalSkillIntervalModifier(skill, purchaseCounts);
  }

  /// Owned purchases that affect the given skill via interval modifiers.
  ///
  /// More efficient than ShopRegistry.purchasesAffectingSkill when the player
  /// owns few purchases, as it only iterates owned purchases.
  Iterable<ShopPurchase> ownedPurchasesAffectingSkill(
    Skill skill,
    ShopRegistry registry,
  ) sync* {
    for (final entry in purchaseCounts.entries) {
      if (entry.value <= 0) continue;
      final purchase = registry.byId(entry.key);
      if (purchase == null) continue;
      if (purchase.hasSkillIntervalFor(skill.id)) {
        yield purchase;
      }
    }
  }

  /// Returns the cost for the next bank slot purchase.
  int nextBankSlotCost() => calculateBankSlotCost(bankSlotsPurchased);
}

/// The initial number of free bank slots.
const int initialBankSlots = 20;

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
    required this.registries,
    this.plotStates = const {},
    this.unlockedPlots = const {},
    this.dungeonCompletions = const {},
    this.itemCharges = const {},
    this.timeAway,
    this.stunned = const StunnedState.fresh(),
    this.attackStyle = AttackStyle.stab,
  });

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
        dungeonCompletions: const {},
        itemCharges: const {},
        // Unlock all free starter plots (level 1, 0 GP cost)
        unlockedPlots: registries.farmingPlots.initialPlots(),
      );

  @visibleForTesting
  factory GlobalState.test(
    Registries registries, {
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState> skillStates = const {},
    Map<ActionId, ActionState> actionStates = const {},
    Map<MelvorId, PlotState> plotStates = const {},
    Set<MelvorId> unlockedPlots = const {},
    Map<MelvorId, int> dungeonCompletions = const {},
    Map<MelvorId, int> itemCharges = const {},
    DateTime? updatedAt,
    int gp = 0,
    Map<Currency, int>? currencies,
    TimeAway? timeAway,
    ShopState shop = const ShopState.empty(),
    HealthState health = const HealthState.full(),
    Equipment equipment = const Equipment.empty(),
    StunnedState stunned = const StunnedState.fresh(),
    AttackStyle attackStyle = AttackStyle.stab,
  }) {
    // Support both gp parameter (for existing tests) and currencies map
    final currenciesMap = currencies ?? (gp > 0 ? {Currency.gp: gp} : const {});
    return GlobalState(
      registries: registries,
      inventory: inventory ?? Inventory.empty(registries.items),
      activeAction: activeAction,
      skillStates: skillStates,
      actionStates: actionStates,
      plotStates: plotStates,
      unlockedPlots: unlockedPlots,
      dungeonCompletions: dungeonCompletions,
      itemCharges: itemCharges,
      updatedAt: updatedAt ?? DateTime.timestamp(),
      currencies: currenciesMap,
      timeAway: timeAway,
      shop: shop,
      health: health,
      equipment: equipment,
      stunned: stunned,
      attackStyle: attackStyle,
    );
  }

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
            toValue: (value) =>
                SkillState.fromJson(value as Map<String, dynamic>),
          ) ??
          const {},
      actionStates =
          maybeMap(
            json['actionStates'],
            toKey: ActionId.fromJson,
            toValue: (value) =>
                ActionState.fromJson(value as Map<String, dynamic>),
          ) ??
          const {},
      plotStates =
          maybeMap(
            json['plotStates'],
            toKey: MelvorId.fromJson,
            toValue: (value) => PlotState.fromJson(
              registries.items,
              value as Map<String, dynamic>,
            ),
          ) ??
          const {},
      unlockedPlots =
          (json['unlockedPlots'] as List<dynamic>?)
              ?.map((e) => MelvorId.fromJson(e as String))
              .toSet() ??
          const {},
      dungeonCompletions = _dungeonCompletionsFromJson(json),
      itemCharges = _itemChargesFromJson(json),
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
          const StunnedState.fresh(),
      attackStyle = json['attackStyle'] != null
          ? AttackStyle.fromJson(json['attackStyle'] as String)
          : AttackStyle.stab;

  static Map<Currency, int> _currenciesFromJson(Map<String, dynamic> json) {
    final currenciesJson = json['currencies'] as Map<String, dynamic>? ?? {};
    return currenciesJson.map((key, value) {
      final currency = Currency.fromId(key);
      return MapEntry(currency, value as int);
    });
  }

  static Map<MelvorId, int> _dungeonCompletionsFromJson(
    Map<String, dynamic> json,
  ) {
    final completionsJson =
        json['dungeonCompletions'] as Map<String, dynamic>? ?? {};
    return completionsJson.map((key, value) {
      return MapEntry(MelvorId.fromJson(key), value as int);
    });
  }

  static Map<MelvorId, int> _itemChargesFromJson(Map<String, dynamic> json) {
    final chargesJson = json['itemCharges'] as Map<String, dynamic>? ?? {};
    return chargesJson.map((key, value) {
      return MapEntry(MelvorId.fromJson(key), value as int);
    });
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
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'plotStates': plotStates.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'unlockedPlots': unlockedPlots.map((e) => e.toJson()).toList(),
      'dungeonCompletions': dungeonCompletions.map(
        (key, value) => MapEntry(key.toJson(), value),
      ),
      'itemCharges': itemCharges.map(
        (key, value) => MapEntry(key.toJson(), value),
      ),
      'currencies': currencies.map((key, value) => MapEntry(key.id, value)),
      'timeAway': timeAway?.toJson(),
      'shop': shop.toJson(),
      'health': health.toJson(),
      'equipment': equipment.toJson(),
      'stunned': stunned.toJson(),
      'attackStyle': attackStyle.toJson(),
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
  final Map<ActionId, ActionState> actionStates;

  /// The farming plot states (plot ID -> plot state).
  final Map<MelvorId, PlotState> plotStates;

  /// The set of unlocked farming plots.
  final Set<MelvorId> unlockedPlots;

  /// Map of dungeon ID to number of completions.
  final Map<MelvorId, int> dungeonCompletions;

  /// Returns how many times a dungeon has been completed.
  int dungeonCompletionCount(MelvorId dungeonId) =>
      dungeonCompletions[dungeonId] ?? 0;

  /// Map of item ID to number of charges for items with charge mechanics.
  /// Used for items like Thieving Gloves that have consumable charges.
  final Map<MelvorId, int> itemCharges;

  /// Returns the number of charges for an item.
  int itemChargeCount(MelvorId itemId) => itemCharges[itemId] ?? 0;

  /// Returns how many Township tasks have been completed.
  /// Always returns 0 since Township tasks are not yet supported.
  int get tasksCompleted => 0;

  /// Returns the game completion percentage (0.0 to 100.0).
  /// Always returns 0.0 since completion tracking is not yet supported.
  double get completionPercent => 0;

  /// Returns how many Slayer tasks have been completed in a category.
  /// Always returns 0 since Slayer task tracking is not yet supported.
  int completedSlayerTaskCount(MelvorId category) => 0;

  /// Returns how many of a Township building have been built.
  /// Always returns 0 since Township buildings are not yet supported.
  int buildingCount(MelvorId building) => 0;

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

  /// The player's combat level using Melvor Idle formula.
  ///
  /// Formula:
  /// Base = 0.25 * (Defence + Hitpoints + floor(0.5 * Prayer))
  /// Melee = Attack + Strength
  /// Ranged = floor(1.5 * Ranged)
  /// Magic = floor(1.5 * Magic)
  /// Combat Level = floor(Base + 0.325 * max(Melee, Ranged, Magic))
  int get combatLevel {
    final defenceLevel = skillState(Skill.defence).skillLevel;
    final hitpointsLevel = skillState(Skill.hitpoints).skillLevel;
    final prayerLevel = skillState(Skill.prayer).skillLevel;
    final attackLevel = skillState(Skill.attack).skillLevel;
    final strengthLevel = skillState(Skill.strength).skillLevel;
    final rangedLevel = skillState(Skill.ranged).skillLevel;
    final magicLevel = skillState(Skill.magic).skillLevel;

    final baseCombatLevel =
        0.25 * (defenceLevel + hitpointsLevel + (0.5 * prayerLevel).floor());

    final meleeCombatLevel = attackLevel + strengthLevel;
    final rangedCombatLevel = (1.5 * rangedLevel).floor();
    final magicCombatLevel = (1.5 * magicLevel).floor();

    final highestOffensive = [
      meleeCombatLevel,
      rangedCombatLevel,
      magicCombatLevel,
    ].reduce((a, b) => a > b ? a : b);

    return (baseCombatLevel + 0.325 * highestOffensive).floor();
  }

  /// The current player HP (computed from maxPlayerHp - lostHp).
  int get playerHp => (maxPlayerHp - health.lostHp).clamp(0, maxPlayerHp);

  /// The player's equipped items.
  final Equipment equipment;

  /// The player's stunned state.
  final StunnedState stunned;

  /// The player's selected attack style for combat XP distribution.
  final AttackStyle attackStyle;

  /// Whether the player is currently stunned.
  bool get isStunned => stunned.isStunned;

  /// Whether the player can perform actions
  /// (true if not stunned and combat isn't paused).
  bool get isPlayerActive => !isStunned && !isCombatPaused;

  /// Whether the current monster can perform actions
  /// (true if combat isn't paused).
  bool get isMonsterActive => !isCombatPaused;

  /// Whether combat is currently paused (e.g., waiting for monster respawn).
  bool get isCombatPaused {
    final active = activeAction;
    if (active == null) return false;
    final state = actionStates[active.id];
    if (state == null) return false;
    final combat = state.combat;
    if (combat == null) return false;
    return combat.isSpawning;
  }

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

    // Check farming plot timers
    for (final plotState in plotStates.values) {
      if (plotState.isGrowing) {
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
      final actionStateVal = actionState(action.id);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);

      // Check inputs
      for (final requirement in inputs.entries) {
        final item = registries.items.byId(requirement.key);
        final itemCount = inventory.countOfItem(item);
        if (itemCount < requirement.value) {
          return false;
        }
      }

      // Check if mining node is depleted
      if (action is MiningAction) {
        final miningState = actionStateVal.mining ?? const MiningState.empty();
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

  /// Resolves all modifiers for a skill action from all sources.
  ///
  /// Combines modifiers from:
  /// - Shop purchases (e.g., axe upgrades for woodcutting)
  /// - Mastery bonuses (based on current mastery level)
  /// - Equipped gear (e.g., Fishing Amulet for fishing)
  /// - (Future: potions, prayers, etc.)
  ///
  /// Returns a [ResolvedModifiers] containing all modifier values by name.
  /// Values are stored as raw numbers from the data (e.g., skillInterval
  /// is in percentage points like -5, flatSkillInterval is in milliseconds).
  ResolvedModifiers resolveSkillModifiers(SkillAction action) {
    return _resolveModifiers(
      skillId: action.skill.id,
      skill: action.skill,
      actionId: action.id,
    );
  }

  /// Resolves global modifiers from shop purchases that are not skill-scoped.
  ///
  /// These include modifiers like autoEat which apply to all combat situations,
  /// not to specific skills.
  ResolvedModifiers resolveGlobalModifiers() {
    return _resolveModifiers();
  }

  /// Resolves all combat-relevant modifiers from all sources.
  ///
  /// This combines:
  /// - Global shop modifiers (autoEat, etc.)
  /// - Equipment modifiers (from item.modifiers)
  /// - Equipment stats (from item.equipmentStats, converted to modifiers)
  /// - (Future: potions, prayers, etc.)
  ///
  /// Used for calculating player combat stats like max hit, accuracy, evasion.
  ResolvedModifiers resolveCombatModifiers() {
    var result = _resolveModifiers();

    // Combine equipment stats from all equipped items
    for (final item in equipment.gearSlots.values) {
      result = result.combine(item.equipmentStats.toModifiers());
    }

    return result;
  }

  /// Internal shared implementation for modifier resolution.
  ///
  /// When [skillId] is provided, only modifiers scoped to that skill are
  /// included. When [skillId] is null, only global (unscoped) modifiers are
  /// included.
  ///
  /// [skill] and [actionId] are needed for skill-scoped resolution to look up
  /// shop purchases and mastery bonuses.
  ResolvedModifiers _resolveModifiers({
    MelvorId? skillId,
    Skill? skill,
    ActionId? actionId,
  }) {
    final builder = ResolvedModifiersBuilder();

    // --- Shop modifiers ---
    if (skill != null) {
      // Skill-scoped: get purchases affecting this skill
      for (final purchase in shop.ownedPurchasesAffectingSkill(
        skill,
        registries.shop,
      )) {
        for (final mod in purchase.contains.modifiers.modifiers) {
          for (final entry in mod.entries) {
            if (entry.appliesToSkill(skillId!)) {
              builder.add(mod.name, entry.value);
            }
          }
        }
      }
    } else {
      // Global: iterate all owned purchases, include unscoped modifiers
      for (final entry in shop.purchaseCounts.entries) {
        if (entry.value <= 0) continue;
        final purchase = registries.shop.byId(entry.key);
        if (purchase == null) continue;

        for (final mod in purchase.contains.modifiers.modifiers) {
          for (final modEntry in mod.entries) {
            // Include modifiers without skill scope (global modifiers)
            if (modEntry.scope == null || modEntry.scope!.skillId == null) {
              builder.add(mod.name, modEntry.value);
            }
          }
        }
      }
    }

    // --- Mastery modifiers (only for skill-scoped resolution) ---
    if (skillId != null && actionId != null) {
      final masteryLevel = actionState(actionId).masteryLevel;
      final skillBonuses = registries.masteryBonuses.forSkill(skillId);
      if (skillBonuses != null) {
        for (final bonus in skillBonuses.bonuses) {
          final count = bonus.countAtLevel(masteryLevel);
          if (count == 0) continue;

          for (final mod in bonus.modifiers.modifiers) {
            for (final entry in mod.entries) {
              if (entry.appliesToSkill(
                skillId,
                autoScopeToAction: bonus.autoScopeToAction,
              )) {
                builder.add(mod.name, entry.value * count);
              }
            }
          }
        }
      }
    }

    // --- Equipment modifiers ---
    for (final item in equipment.gearSlots.values) {
      for (final mod in item.modifiers.modifiers) {
        for (final entry in mod.entries) {
          // For skill-scoped: only include if applies to skill
          // For global: include all (combat gear is typically unscoped)
          if (skillId == null || entry.appliesToSkill(skillId)) {
            builder.add(mod.name, entry.value);
          }
        }
      }
    }

    return builder.build();
  }

  /// Rolls duration for a skill action and applies all relevant modifiers.
  /// Percentage modifiers are applied first, then flat modifiers.
  int rollDurationWithModifiers(
    SkillAction action,
    Random random,
    ShopRegistry shopRegistry,
  ) {
    final ticks = action.rollDuration(random);
    final modifiers = resolveSkillModifiers(action);

    // skillInterval is percentage points (e.g., -5 = 5% reduction)
    final percentPoints = modifiers.skillInterval;

    // flatSkillInterval is milliseconds, convert to ticks (100ms = 1 tick)
    final flatTicks = modifiers.flatSkillInterval / 100.0;

    // Apply: percentage first, then flat adjustment
    final result = ticks * (1.0 + percentPoints / 100.0) + flatTicks;

    // Round and clamp to at least 1 tick
    return result.round().clamp(1, double.maxFinite.toInt());
  }

  GlobalState startAction(Action action, {required Random random}) {
    return _startActionImpl(
      action,
      skillDuration: (a) =>
          rollDurationWithModifiers(a, random, registries.shop),
    );
  }

  /// Starts an action using deterministic mean duration (no randomness).
  ///
  /// Used during planning/solver to get consistent state projections.
  /// For actual gameplay execution, use [startAction] instead.
  GlobalState startActionDeterministic(Action action) {
    return _startActionImpl(action, skillDuration: _meanDurationWithModifiers);
  }

  GlobalState _startActionImpl(
    Action action, {
    required int Function(SkillAction) skillDuration,
  }) {
    if (isStunned) {
      throw const StunnedException('Cannot start action while stunned');
    }

    final actionId = action.id;
    int totalTicks;

    if (action is SkillAction) {
      final actionStateVal = actionState(actionId);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);

      // Validate that all required items are available for skill actions
      for (final requirement in inputs.entries) {
        final item = registries.items.byId(requirement.key);
        final itemCount = inventory.countOfItem(item);
        if (itemCount < requirement.value) {
          throw Exception(
            'Cannot start ${action.name}: Need ${requirement.value} '
            '${requirement.key.name}, but only have $itemCount',
          );
        }
      }
      totalTicks = skillDuration(action);
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
      final pStats = computePlayerStats(this);
      totalTicks = ticksFromDuration(
        Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
      );
      // Initialize combat state with the combat action, starting with respawn
      final combatState = CombatActionState.start(action, pStats);
      final newActionStates = Map<ActionId, ActionState>.from(actionStates);
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

  /// Calculates mean duration with modifiers applied (deterministic).
  int _meanDurationWithModifiers(SkillAction action) {
    final ticks = ticksFromDuration(action.meanDuration);
    final modifiers = resolveSkillModifiers(action);

    // skillInterval is percentage points (e.g., -5 = 5% reduction)
    final percentPoints = modifiers.skillInterval;

    // flatSkillInterval is milliseconds, convert to ticks (100ms = 1 tick)
    final flatTicks = modifiers.flatSkillInterval / 100.0;

    // Apply: percentage first, then flat adjustment
    final result = ticks * (1.0 + percentPoints / 100.0) + flatTicks;

    // Round and clamp to at least 1 tick
    return result.round().clamp(1, double.maxFinite.toInt());
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
      plotStates: plotStates,
      unlockedPlots: unlockedPlots,
      dungeonCompletions: dungeonCompletions,
      itemCharges: itemCharges,
      updatedAt: DateTime.timestamp(),
      currencies: currencies,
      health: health,
      equipment: equipment,
      stunned: stunned,
      attackStyle: attackStyle,
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
      plotStates: plotStates,
      unlockedPlots: unlockedPlots,
      dungeonCompletions: dungeonCompletions,
      itemCharges: itemCharges,
      updatedAt: DateTime.timestamp(),
      currencies: currencies,
      shop: shop,
      health: health,
      equipment: equipment,
      stunned: stunned,
      attackStyle: attackStyle,
    );
  }

  SkillState skillState(Skill skill) =>
      skillStates[skill] ?? const SkillState.empty();

  // TODO(eseidel): Implement this.
  int unlockedActionsCount(Skill skill) => 1;

  ActionState actionState(ActionId action) =>
      actionStates[action] ?? const ActionState.empty();

  int activeProgress(Action action) {
    final active = activeAction;
    if (active == null || active.id != action.id) {
      return 0;
    }
    return active.progressTicks;
  }

  GlobalState updateActiveAction(
    ActionId actionId, {
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

  GlobalState addActionMasteryXp(ActionId actionId, int amount) {
    final oldState = actionState(actionId);
    final newState = oldState.copyWith(masteryXp: oldState.masteryXp + amount);
    final newActionStates = Map<ActionId, ActionState>.from(actionStates);
    newActionStates[actionId] = newState;
    return copyWith(actionStates: newActionStates);
  }

  /// Sets the selected recipe index for an action with alternative costs.
  GlobalState setRecipeIndex(ActionId actionId, int recipeIndex) {
    final oldState = actionState(actionId);
    final newState = oldState.copyWith(selectedRecipeIndex: recipeIndex);
    final newActionStates = Map<ActionId, ActionState>.from(actionStates);
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

  /// Plants a crop in a plot.
  /// Uses countdown pattern - no currentTick parameter needed.
  GlobalState plantCrop(MelvorId plotId, FarmingCrop crop) {
    // Validate plot is unlocked
    if (!unlockedPlots.contains(plotId)) {
      throw StateError('Plot $plotId is not unlocked');
    }

    // Validate plot is empty
    final currentPlotState = plotStates[plotId] ?? const PlotState.empty();
    if (!currentPlotState.isEmpty) {
      throw StateError('Plot $plotId is not empty');
    }

    // Validate player has required level
    final farmingLevel = skillState(Skill.farming).skillLevel;
    if (farmingLevel < crop.level) {
      throw StateError(
        'Farming level $farmingLevel is too low for ${crop.name} '
        '(requires ${crop.level})',
      );
    }

    // Get seed item (throws if not found)
    final seed = registries.items.byId(crop.seedId);

    // Validate player has seeds
    if (inventory.countOfItem(seed) < crop.seedCost) {
      throw StateError(
        'Not enough ${seed.name}: need ${crop.seedCost}, '
        'have ${inventory.countOfItem(seed)}',
      );
    }

    // Consume seeds from inventory
    final newInventory = inventory.removing(
      ItemStack(seed, count: crop.seedCost),
    );

    // Create new plot state with countdown timer
    // Preserve any compost that was applied before planting
    final newPlotState = PlotState(
      cropId: crop.id,
      growthTicksRemaining: crop.growthTicks,
      compostItems: currentPlotState.compostItems,
    );

    // Update plot states
    final newPlotStates = Map<MelvorId, PlotState>.from(plotStates);
    newPlotStates[plotId] = newPlotState;

    // Award XP if category says to give XP on plant
    final category = registries.farmingCategories.byId(crop.categoryId);
    var newState = copyWith(inventory: newInventory, plotStates: newPlotStates);

    if (category?.giveXPOnPlant ?? false) {
      newState = newState.addSkillXp(Skill.farming, crop.baseXP);
    }

    return newState;
  }

  /// Applies compost to an empty plot before planting.
  /// Compost can only be applied to empty plots, not to growing crops.
  GlobalState applyCompost(MelvorId plotId, Item compost) {
    // Validate compost item has compost value
    final compostValue = compost.compostValue;
    if (compostValue == null || compostValue == 0) {
      throw StateError('${compost.name} is not compost');
    }

    // Get or create empty plot state
    final plotState = plotStates[plotId] ?? const PlotState.empty();

    // Validate plot is empty (compost must be applied before planting)
    if (!plotState.isEmpty) {
      throw StateError('Compost can only be applied to empty plots');
    }

    // Validate player has compost
    if (inventory.countOfItem(compost) < 1) {
      throw StateError('Not enough ${compost.name}');
    }

    // Validate compost limit (max 50, which gives 100% success chance)
    final newCompostValue = plotState.compostApplied + compostValue;
    if (newCompostValue > 50) {
      throw StateError(
        'Cannot apply more compost: already at ${plotState.compostApplied}, '
        'max is 50',
      );
    }

    // Consume compost from inventory
    final newInventory = inventory.removing(ItemStack(compost, count: 1));

    // Add compost item to the plot's compost list
    final newPlotState = plotState.copyWith(
      compostItems: [...plotState.compostItems, compost],
    );

    final newPlotStates = Map<MelvorId, PlotState>.from(plotStates);
    newPlotStates[plotId] = newPlotState;

    return copyWith(inventory: newInventory, plotStates: newPlotStates);
  }

  /// Harvests a ready crop from a plot.
  GlobalState harvestCrop(MelvorId plotId, Random random) {
    // Validate plot has a ready crop
    final plotState = plotStates[plotId];
    if (plotState == null || !plotState.isReadyToHarvest) {
      throw StateError('Plot $plotId does not have a crop ready to harvest');
    }

    final cropId = plotState.cropId;
    if (cropId == null) {
      throw StateError('Plot $plotId has no crop planted');
    }

    // Get crop and category
    final crop = registries.farmingCrops.byId(cropId);
    if (crop == null) {
      throw StateError('Crop $cropId not found');
    }

    final category = registries.farmingCategories.byId(crop.categoryId);
    if (category == null) {
      throw StateError('Category ${crop.categoryId} not found');
    }

    // Check success chance (50% base + compost value)
    final successChance = (50 + plotState.compostApplied) / 100.0;
    final succeeded = random.nextDouble() < successChance;

    // Get product item (throws if not found)
    final product = registries.items.byId(crop.productId);

    // If failed, just clear the plot and return (no harvest, no XP)
    if (!succeeded) {
      final newPlotStates = Map<MelvorId, PlotState>.from(plotStates)
        ..remove(plotId);
      return copyWith(plotStates: newPlotStates);
    }

    // Calculate harvest quantity
    final baseQuantity = crop.baseQuantity;
    final multiplier = category.harvestMultiplier;
    // harvestBonusApplied is a percentage (e.g., 10 = +10%)
    final harvestBonus = 1.0 + (plotState.harvestBonusApplied / 100.0);
    final masteryLevel = actionState(cropId).masteryLevel;
    final masteryBonus = 1.0 + (masteryLevel * 0.002); // +0.2% per level

    final quantity = (baseQuantity * multiplier * harvestBonus * masteryBonus)
        .round();

    // Add harvested items to inventory
    var newInventory = inventory.adding(ItemStack(product, count: quantity));

    // Roll for seed return if category allows
    if (category.returnSeeds) {
      final seed = registries.items.byId(crop.seedId);
      const baseChance = 0.30; // 30% base chance
      final masteryChanceBonus = masteryLevel * 0.002; // +0.2% per level
      var seedsReturned = 0;

      for (var i = 0; i < quantity; i++) {
        if (random.nextDouble() < baseChance + masteryChanceBonus) {
          seedsReturned++;
        }
      }

      if (seedsReturned > 0) {
        newInventory = newInventory.adding(
          ItemStack(seed, count: seedsReturned),
        );
      }
    }

    // Award XP on harvest
    // - Allotments/Herbs: XP = baseXP * quantity (scaleXPWithQuantity=true)
    // - Trees: XP = baseXP (scaleXPWithQuantity=false)
    // Note: giveXPOnPlant controls additional XP when planting, not harvest XP
    var newState = copyWith(inventory: newInventory);

    final xpAmount = category.scaleXPWithQuantity
        ? crop.baseXP * quantity
        : crop.baseXP;
    newState = newState.addSkillXp(Skill.farming, xpAmount);

    // Award mastery XP
    final masteryXpAmount = crop.baseXP ~/ category.masteryXPDivider;
    newState = newState.addActionMasteryXp(cropId, masteryXpAmount);

    return newState.clearPlot(plotId);
  }

  /// Clears a farming plot, destroying any growing crop and compost.
  GlobalState clearPlot(MelvorId plotId) {
    final newPlotStates = Map<MelvorId, PlotState>.from(plotStates)
      ..remove(plotId);
    return copyWith(plotStates: newPlotStates);
  }

  GlobalState copyWith({
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState>? skillStates,
    Map<ActionId, ActionState>? actionStates,
    Map<MelvorId, PlotState>? plotStates,
    Set<MelvorId>? unlockedPlots,
    Map<MelvorId, int>? dungeonCompletions,
    Map<MelvorId, int>? itemCharges,
    Map<Currency, int>? currencies,
    TimeAway? timeAway,
    ShopState? shop,
    HealthState? health,
    Equipment? equipment,
    StunnedState? stunned,
    AttackStyle? attackStyle,
  }) {
    return GlobalState(
      registries: registries,
      inventory: inventory ?? this.inventory,
      activeAction: activeAction ?? this.activeAction,
      skillStates: skillStates ?? this.skillStates,
      actionStates: actionStates ?? this.actionStates,
      plotStates: plotStates ?? this.plotStates,
      unlockedPlots: unlockedPlots ?? this.unlockedPlots,
      dungeonCompletions: dungeonCompletions ?? this.dungeonCompletions,
      itemCharges: itemCharges ?? this.itemCharges,
      updatedAt: DateTime.timestamp(),
      currencies: currencies ?? this.currencies,
      timeAway: timeAway ?? this.timeAway,
      shop: shop ?? this.shop,
      health: health ?? this.health,
      equipment: equipment ?? this.equipment,
      stunned: stunned ?? this.stunned,
      attackStyle: attackStyle ?? this.attackStyle,
    );
  }

  /// Sets the player's attack style for combat XP distribution.
  GlobalState setAttackStyle(AttackStyle style) {
    return copyWith(attackStyle: style);
  }
}
