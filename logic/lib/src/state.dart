import 'dart:math';

import 'package:logic/src/action_state.dart';
import 'package:logic/src/combat_stats.dart';
import 'package:logic/src/cooking_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/data/summoning_synergy.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/plot_state.dart';
import 'package:logic/src/summoning_state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/township_state.dart';
import 'package:logic/src/types/equipment.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/health.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/modifier_provider.dart';
import 'package:logic/src/types/open_result.dart';
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

  /// Returns the valid attack styles for this combat type.
  List<AttackStyle> get attackStyles {
    return switch (this) {
      CombatType.melee => [
        AttackStyle.stab,
        AttackStyle.slash,
        AttackStyle.block,
      ],
      CombatType.ranged => [
        AttackStyle.accurate,
        AttackStyle.rapid,
        AttackStyle.longRange,
      ],
      CombatType.magic => [AttackStyle.standard, AttackStyle.defensive],
    };
  }

  /// Returns the skills relevant to this combat type.
  ///
  /// Used to determine which familiars are relevant when fighting with
  /// this combat type.
  Set<Skill> get skills {
    return switch (this) {
      CombatType.melee => {Skill.attack, Skill.strength, Skill.defence},
      CombatType.ranged => {Skill.ranged},
      CombatType.magic => {Skill.magic},
    };
  }
}

/// The player's selected melee attack style for combat XP distribution.
///
/// Each style determines which combat skill receives XP from damage dealt:
/// - [stab]: Attack XP (4 XP per damage)
/// - [slash]: Strength XP (4 XP per damage)
/// - [block]: Defence XP (4 XP per damage)
///
/// Hitpoints always receives XP regardless of style (1.33 XP per damage).
enum AttackStyle {
  // Melee styles
  stab,
  slash,
  block,

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
      stab || slash || block => CombatType.melee,
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
    this.selectedPotions = const {},
    this.potionChargesUsed = const {},
    this.timeAway,
    this.stunned = const StunnedState.fresh(),
    this.attackStyle = AttackStyle.stab,
    this.cooking = const CookingState.empty(),
    this.summoning = const SummoningState.empty(),
    this.township = const TownshipState.empty(),
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
        selectedPotions: const {},
        potionChargesUsed: const {},
        // Unlock all free starter plots (level 1, 0 GP cost)
        unlockedPlots: registries.farmingPlots.initialPlots(),
        // Initialize township resources with starting amounts
        township: TownshipState.initial(registries.township),
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
    Map<MelvorId, MelvorId> selectedPotions = const {},
    Map<MelvorId, int> potionChargesUsed = const {},
    DateTime? updatedAt,
    int gp = 0,
    Map<Currency, int>? currencies,
    TimeAway? timeAway,
    ShopState shop = const ShopState.empty(),
    HealthState health = const HealthState.full(),
    Equipment equipment = const Equipment.empty(),
    StunnedState stunned = const StunnedState.fresh(),
    AttackStyle attackStyle = AttackStyle.stab,
    SummoningState summoning = const SummoningState.empty(),
    TownshipState? township,
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
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      updatedAt: updatedAt ?? DateTime.timestamp(),
      currencies: currenciesMap,
      timeAway: timeAway,
      shop: shop,
      health: health,
      equipment: equipment,
      stunned: stunned,
      attackStyle: attackStyle,
      summoning: summoning,
      township: township ?? TownshipState.initial(registries.township),
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
      selectedPotions = _selectedPotionsFromJson(json),
      potionChargesUsed = _potionChargesUsedFromJson(json),
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
          : AttackStyle.stab,
      cooking =
          CookingState.maybeFromJson(json['cooking']) ??
          const CookingState.empty(),
      summoning =
          SummoningState.maybeFromJson(json['summoning']) ??
          const SummoningState.empty(),
      township =
          TownshipState.maybeFromJson(registries.township, json['township']) ??
          TownshipState.initial(registries.township);

  static Map<Currency, int> _currenciesFromJson(Map<String, dynamic> json) {
    final currenciesJson = json['currencies'] as Map<String, dynamic>? ?? {};
    return currenciesJson.map((key, value) {
      final currency = Currency.fromIdString(key);
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

  static Map<MelvorId, MelvorId> _selectedPotionsFromJson(
    Map<String, dynamic> json,
  ) {
    final potionsJson = json['selectedPotions'] as Map<String, dynamic>? ?? {};
    return potionsJson.map((key, value) {
      return MapEntry(
        MelvorId.fromJson(key),
        MelvorId.fromJson(value as String),
      );
    });
  }

  static Map<MelvorId, int> _potionChargesUsedFromJson(
    Map<String, dynamic> json,
  ) {
    final chargesJson =
        json['potionChargesUsed'] as Map<String, dynamic>? ?? {};
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
      'selectedPotions': selectedPotions.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'potionChargesUsed': potionChargesUsed.map(
        (key, value) => MapEntry(key.toJson(), value),
      ),
      'currencies': currencies.map(
        (key, value) => MapEntry(key.id.toJson(), value),
      ),
      'timeAway': timeAway?.toJson(),
      'shop': shop.toJson(),
      'health': health.toJson(),
      'equipment': equipment.toJson(),
      'stunned': stunned.toJson(),
      'attackStyle': attackStyle.toJson(),
      'cooking': cooking.toJson(),
      'summoning': summoning.toJson(),
      'township': township.toJson(),
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

  /// Selected potion per skill.
  /// Key is skill MelvorId (e.g. melvorD:Woodcutting), value is potion item
  /// MelvorId (e.g. melvorF:Bird_Nest_Potion_I). Potions remain in inventory
  /// and are consumed from there.
  final Map<MelvorId, MelvorId> selectedPotions;

  /// Charges consumed from current potion per skill. Key is skill MelvorId.
  /// When this reaches potion.potionCharges, one potion is removed from
  /// inventory and this resets to 0.
  final Map<MelvorId, int> potionChargesUsed;

  /// Returns the game completion percentage (0.0 to 100.0).
  /// Always returns 0.0 since completion tracking is not yet supported.
  double get completionPercent => 0;

  /// Returns how many Slayer tasks have been completed in a category.
  /// Always returns 0 since Slayer task tracking is not yet supported.
  int completedSlayerTaskCount(MelvorId category) => 0;

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

  /// The cooking state (tracks all 3 cooking areas).
  final CookingState cooking;

  /// The summoning state (tracks discovered marks per familiar).
  final SummoningState summoning;

  /// The township state (town management skill).
  final TownshipState township;

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

  /// The current prayer points.
  // TODO(eseidel): Implement prayer points system.
  int get prayerPoints => 0;

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

    // Township timers are active once a deity is chosen
    if (township.worshipId != null) {
      return true;
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

      // Check if summoning action requires marks
      if (action is SummoningAction) {
        if (!summoning.canCraftTablet(action.productId)) {
          return false; // Need at least 1 mark to craft tablets
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

  // ---------------------------------------------------------------------------
  // Shop upgrade level convenience methods
  // ---------------------------------------------------------------------------

  /// Returns the number of axe upgrades owned (woodcutting).
  int get axeLevel => registries.shop.axeLevel(shop.purchaseCounts);

  /// Returns the number of fishing rod upgrades owned.
  int get fishingRodLevel =>
      registries.shop.fishingRodLevel(shop.purchaseCounts);

  /// Returns the number of pickaxe upgrades owned (mining).
  int get pickaxeLevel => registries.shop.pickaxeLevel(shop.purchaseCounts);

  /// Returns the ID of the highest owned cooking fire, or null if none owned.
  MelvorId? get highestCookingFireId =>
      registries.shop.highestCookingFireId(shop.purchaseCounts);

  /// Returns the ID of the highest owned cooking furnace, or null if none.
  MelvorId? get highestCookingFurnaceId =>
      registries.shop.highestCookingFurnaceId(shop.purchaseCounts);

  /// Returns the ID of the highest owned cooking pot, or null if none owned.
  MelvorId? get highestCookingPotId =>
      registries.shop.highestCookingPotId(shop.purchaseCounts);

  /// Creates a ModifierProvider for a skill action.
  ///
  /// Use this when processing skill actions (woodcutting, fishing, etc.)
  /// where mastery bonuses need to be resolved for the specific action.
  ModifierProvider createActionModifierProvider(SkillAction action) {
    return ModifierProvider(
      registries: registries,
      equipment: equipment,
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      inventory: inventory,
      summoning: summoning,
      shopPurchases: shop,
      actionStateGetter: actionState,
      activeSynergy: _getActiveSynergy(),
      currentActionId: action.id,
    );
  }

  /// Creates a ModifierProvider for combat.
  ///
  /// Filters summoning familiar modifiers by combat type relevance
  /// (melee familiars only apply during melee combat, etc.).
  ModifierProvider createCombatModifierProvider() {
    return ModifierProvider(
      registries: registries,
      equipment: equipment,
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      inventory: inventory,
      summoning: summoning,
      shopPurchases: shop,
      actionStateGetter: actionState,
      activeSynergy: _getActiveSynergy(),
      combatTypeSkills: attackStyle.combatType.skills,
    );
  }

  /// Creates a ModifierProvider for global modifiers (auto-eat, etc.).
  ///
  /// Use this when querying modifiers that don't depend on a specific
  /// action or combat context.
  ModifierProvider createGlobalModifierProvider() {
    return ModifierProvider(
      registries: registries,
      equipment: equipment,
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      inventory: inventory,
      summoning: summoning,
      shopPurchases: shop,
      actionStateGetter: actionState,
      activeSynergy: _getActiveSynergy(),
    );
  }

  /// Returns the active synergy if both summon slots have tablets equipped,
  /// both familiars have mark level >= 3, and a synergy exists for the pair.
  ///
  /// Returns null if:
  /// - Either summon slot is empty
  /// - Either item is not a summoning tablet
  /// - Either familiar has mark level < 3
  /// - No synergy exists for the pair of familiars
  SummoningSynergy? getActiveSynergy() => _getActiveSynergy();

  SummoningSynergy? _getActiveSynergy() {
    final tablet1 = equipment.gearInSlot(EquipmentSlot.summon1);
    final tablet2 = equipment.gearInSlot(EquipmentSlot.summon2);

    // Both slots must have tablets
    if (tablet1 == null || tablet2 == null) return null;
    if (!tablet1.isSummonTablet || !tablet2.isSummonTablet) return null;

    // Get the summoning actions for each tablet
    final action1 = registries.actions.summoningActionForTablet(tablet1.id);
    final action2 = registries.actions.summoningActionForTablet(tablet2.id);
    if (action1 == null || action2 == null) return null;

    // Both familiars must have mark level >= 3
    if (summoning.markLevel(action1.productId) < 3) return null;
    if (summoning.markLevel(action2.productId) < 3) return null;

    // Look up synergy for this pair
    return registries.summoningSynergies.findSynergy(
      action1.summonId,
      action2.summonId,
    );
  }

  /// Rolls duration for a skill action and applies all relevant modifiers.
  /// Percentage modifiers are applied first, then flat modifiers.
  int rollDurationWithModifiers(
    SkillAction action,
    Random random,
    ShopRegistry shopRegistry,
  ) {
    final ticks = action.rollDuration(random);
    final modifiers = createActionModifierProvider(action);

    // skillInterval is percentage points (e.g., -5 = 5% reduction)
    final percentPoints = modifiers.skillInterval(
      skillId: action.skill.id,
      actionId: action.id.localId,
    );

    // flatSkillInterval is milliseconds, convert to ticks (100ms = 1 tick)
    final flatTicks =
        modifiers.flatSkillInterval(
          skillId: action.skill.id,
          actionId: action.id.localId,
        ) /
        100.0;

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

    // Check if we're switching away from cooking to a non-cooking action.
    // If so, reset all cooking area progress (recipes remain assigned).
    // Use skill ID directly to avoid looking up actions that may not exist
    // (e.g., in test scenarios with ActionId.test()).
    var updatedCooking = cooking;
    final currentActionId = activeAction?.id;
    final isSwitchingFromCooking = currentActionId?.skillId == Skill.cooking.id;
    final isSwitchingToCooking = action is CookingAction;
    if (isSwitchingFromCooking && !isSwitchingToCooking) {
      updatedCooking = cooking.withAllProgressCleared();
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
        cooking: updatedCooking,
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
        cooking: updatedCooking,
      );
    } else {
      throw Exception('Unknown action type: ${action.runtimeType}');
    }
  }

  /// Calculates mean duration with modifiers applied (deterministic).
  int _meanDurationWithModifiers(SkillAction action) {
    final ticks = ticksFromDuration(action.meanDuration);
    final modifiers = createActionModifierProvider(action);

    // skillInterval is percentage points (e.g., -5 = 5% reduction)
    final percentPoints = modifiers.skillInterval(
      skillId: action.skill.id,
      actionId: action.id.localId,
    );

    // flatSkillInterval is milliseconds, convert to ticks (100ms = 1 tick)
    final flatTicks =
        modifiers.flatSkillInterval(
          skillId: action.skill.id,
          actionId: action.id.localId,
        ) /
        100.0;

    // Apply: percentage first, then flat adjustment
    final result = ticks * (1.0 + percentPoints / 100.0) + flatTicks;

    // Round and clamp to at least 1 tick
    return result.round().clamp(1, double.maxFinite.toInt());
  }

  GlobalState clearAction() {
    if (isStunned) {
      throw const StunnedException('Cannot stop action while stunned');
    }

    // If we're clearing a cooking action, reset all cooking area progress.
    // Check the skill ID directly to avoid looking up actions that may not
    // exist (e.g., in test scenarios with ActionId.test()).
    var updatedCooking = cooking;
    final currentActionId = activeAction?.id;
    if (currentActionId?.skillId == Skill.cooking.id) {
      updatedCooking = cooking.withAllProgressCleared();
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
      cooking: updatedCooking,
      summoning: summoning,
      township: township,
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
      summoning: summoning,
      township: township,
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

  // ---------------------------------------------------------------------------
  // Township Methods
  // ---------------------------------------------------------------------------

  /// Checks if a Township building can be built in a biome.
  /// Returns null if valid, or an error message if not.
  String? canBuildTownshipBuilding(MelvorId biomeId, MelvorId buildingId) {
    final building = registries.township.buildingById(buildingId);
    if (building == null) return 'Unknown building: $buildingId';

    final biome = registries.township.biomeById(biomeId);
    if (biome == null) return 'Unknown biome: $biomeId';

    // Check if building is valid for this biome
    if (!building.canBuildInBiome(biomeId)) {
      return '${building.name} cannot be built in ${biome.name}';
    }

    // Get biome-specific data
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) {
      return '${building.name} has no data for ${biome.name}';
    }

    // Check level requirement (tier 1 = level 1, tier 2 = level 30, etc.)
    final townshipLevel = skillState(Skill.town).skillLevel;
    final levelRequired = TownshipRegistry.tierToLevel(building.tier);
    if (townshipLevel < levelRequired) {
      return 'Requires Township level $levelRequired';
    }

    // Check resource costs (including GP) with deity modifier applied
    final costs = township.buildingCostsWithModifier(biomeData.costs);
    for (final entry in costs.entries) {
      final resourceId = entry.key;
      final required = entry.value;

      // GP is a special case - check against player currencies
      if (Currency.isGpId(resourceId)) {
        if (gp < required) {
          return 'Not enough GP (need $required)';
        }
      } else {
        final available = township.resourceAmount(resourceId);
        if (available < required) {
          final resource = registries.township.resourceById(resourceId);
          return 'Not enough ${resource.name} '
              '(need $required, have $available)';
        }
      }
    }

    return null; // All checks passed
  }

  /// Builds a Township building in a biome.
  /// Throws StateError if validation fails.
  GlobalState buildTownshipBuilding(MelvorId biomeId, MelvorId buildingId) {
    final error = canBuildTownshipBuilding(biomeId, buildingId);
    if (error != null) throw StateError(error);

    final building = registries.township.buildingById(buildingId)!;
    final biomeData = building.dataForBiome(biomeId)!;

    // Deduct costs (GP and township resources) with deity modifier applied
    var state = this;
    var newTownship = township;

    final costs = township.buildingCostsWithModifier(biomeData.costs);
    for (final entry in costs.entries) {
      final resourceId = entry.key;
      final cost = entry.value;

      if (Currency.isGpId(resourceId)) {
        // Deduct GP from player currencies
        state = state.addCurrency(Currency.gp, -cost);
      } else {
        // Deduct township resources
        newTownship = newTownship.removeResource(resourceId, cost);
      }
    }

    // Increment building count
    final biomeState = newTownship.biomeState(biomeId);
    final buildingState = biomeState.buildingState(buildingId);
    final newBuildingState = buildingState.copyWith(
      count: buildingState.count + 1,
    );
    final newBiomeState = biomeState.withBuildingState(
      buildingId,
      newBuildingState,
    );
    newTownship = newTownship.withBiomeState(biomeId, newBiomeState);

    return state.copyWith(township: newTownship);
  }

  // ---------------------------------------------------------------------------
  // Township Trading Methods
  // ---------------------------------------------------------------------------

  /// Checks if a Township trade can be executed.
  /// Returns null if valid, or an error message if not.
  String? canExecuteTownshipTrade(MelvorId tradeId, {int quantity = 1}) {
    final trade = registries.township.tradeById(tradeId);
    if (trade == null) return 'Unknown trade: $tradeId';

    if (quantity < 1) return 'Quantity must be at least 1';

    // Get Trading Post count for discount calculation
    // TODO(eseidel): Use actual Trading Post building ID from data.
    const tradingPostId = MelvorId('melvorF:Trading_Post');
    final tradingPostCount = township.totalBuildingCount(tradingPostId);

    // Calculate costs with discount
    final costs = trade.costsWithDiscount(tradingPostCount);

    // Check if player has enough township resources
    for (final entry in costs.entries) {
      final resourceId = entry.key;
      final required = entry.value * quantity;
      final available = township.resourceAmount(resourceId);
      if (available < required) {
        final resource = registries.township.resourceById(resourceId);
        return 'Not enough ${resource.name} '
            '(need $required, have $available)';
      }
    }

    // Check if inventory has space for the item
    final item = registries.items.byId(trade.itemId);
    if (!inventory.canAdd(item, capacity: inventoryCapacity)) {
      return 'Inventory is full';
    }

    return null; // All checks passed
  }

  /// Executes a Township trade, converting resources to items.
  /// Throws StateError if validation fails.
  GlobalState executeTownshipTrade(MelvorId tradeId, {int quantity = 1}) {
    final error = canExecuteTownshipTrade(tradeId, quantity: quantity);
    if (error != null) throw StateError(error);

    final trade = registries.township.tradeById(tradeId)!;

    // Get Trading Post count for discount
    const tradingPostId = MelvorId('melvorF:Trading_Post');
    final tradingPostCount = township.totalBuildingCount(tradingPostId);
    final costs = trade.costsWithDiscount(tradingPostCount);

    // Deduct township resources
    var newTownship = township;
    for (final entry in costs.entries) {
      newTownship = newTownship.removeResource(
        entry.key,
        entry.value * quantity,
      );
    }

    // Add items to inventory
    final item = registries.items.byId(trade.itemId);
    final totalQuantity = trade.itemQuantity * quantity;
    final newInventory = inventory.adding(
      ItemStack(item, count: totalQuantity),
    );

    return copyWith(township: newTownship, inventory: newInventory);
  }

  // ---------------------------------------------------------------------------
  // Township Task Methods
  // ---------------------------------------------------------------------------

  /// Checks if a task goal is satisfied.
  bool isTaskGoalMet(MelvorId taskId, TaskGoal goal) {
    switch (goal.type) {
      case TaskGoalType.items:
        // Check if player has the required items in inventory
        final item = registries.items.byId(goal.id);
        return inventory.countOfItem(item) >= goal.quantity;
      case TaskGoalType.skillXP:
      case TaskGoalType.monsters:
        // Check progress tracked in township state
        return township.getGoalProgress(taskId, goal) >= goal.quantity;
    }
  }

  /// Checks if all goals for a task are met.
  bool isTaskComplete(MelvorId taskId) {
    final task = registries.township.taskById(taskId);

    // Check if already completed
    if (township.completedMainTasks.contains(taskId)) {
      return false; // Already claimed
    }

    // Check all goals are met
    return task.goals.every((goal) => isTaskGoalMet(taskId, goal));
  }

  /// Claims rewards for a completed task, returning new state and changes.
  /// The changes can be used by the UI to display a toast.
  /// Throws StateError if task is not complete or already claimed.
  (GlobalState, Changes) claimTaskRewardWithChanges(MelvorId taskId) {
    final task = registries.township.taskById(taskId);

    if (!isTaskComplete(taskId)) {
      throw StateError('Task requirements not met');
    }

    var state = this;

    // Consume required items for item goals
    for (final goal in task.goals) {
      if (goal.type == TaskGoalType.items) {
        final item = registries.items.byId(goal.id);
        state = state.copyWith(
          inventory: state.inventory.removing(
            ItemStack(item, count: goal.quantity),
          ),
        );
      }
    }

    // Grant rewards
    for (final reward in task.rewards) {
      switch (reward.type) {
        case TaskRewardType.skillXP:
          // Map skill ID to Skill enum
          final skill = Skill.fromId(reward.id);
          state = state.addSkillXp(skill, reward.quantity);
        case TaskRewardType.currency:
          final currency = Currency.fromIdString(reward.id.fullId);
          state = state.addCurrency(currency, reward.quantity);
        case TaskRewardType.item:
          final item = registries.items.byId(reward.id);
          state = state.copyWith(
            inventory: state.inventory.adding(
              ItemStack(item, count: reward.quantity),
            ),
          );
        case TaskRewardType.townshipResource:
          state = state.copyWith(
            township: state.township.addResource(reward.id, reward.quantity),
          );
      }
    }

    // Mark task as completed (all main tasks go to completedMainTasks)
    final newCompleted = Set<MelvorId>.from(township.completedMainTasks)
      ..add(taskId);
    final newState = state.copyWith(
      township: state.township.copyWith(completedMainTasks: newCompleted),
    );

    // Get changes for the UI to display
    final changes = task.rewardsToChanges(registries.items);

    return (newState, changes);
  }

  // ---------------------------------------------------------------------------
  // Township Worship Methods
  // ---------------------------------------------------------------------------

  /// Selects a deity for worship.
  /// Resets worship points if changing to a different deity.
  GlobalState selectWorship(MelvorId deityId) =>
      copyWith(township: township.selectWorship(deityId));

  /// Clears worship selection.
  GlobalState clearWorship() => copyWith(township: township.clearWorship());

  /// Repairs a Township building in a biome, restoring efficiency to 100%.
  /// Cost formula: (Base Cost / 3) × Buildings Built × (1 - Efficiency%)
  /// Throws StateError if building doesn't exist, doesn't need repair,
  /// or player can't afford the repair costs.
  GlobalState repairTownshipBuilding(MelvorId biomeId, MelvorId buildingId) {
    final building = registries.township.buildingById(buildingId);
    if (building == null) throw StateError('Unknown building: $buildingId');

    final biomeState = township.biomeState(biomeId);
    final buildingState = biomeState.buildingState(buildingId);

    if (buildingState.count == 0) {
      throw StateError('No ${building.name} to repair');
    }

    if (buildingState.efficiency >= 100) {
      throw StateError('${building.name} is already at full efficiency');
    }

    // Get repair costs and deduct them
    final repairCosts = township.repairCosts(biomeId, buildingId);
    var state = this;
    var newTownship = township;

    for (final entry in repairCosts.entries) {
      final resourceId = entry.key;
      final cost = entry.value;

      if (resourceId.localId == 'GP') {
        if (gp < cost) {
          throw StateError('Not enough GP');
        }
      } else {
        if (newTownship.resourceAmount(resourceId) < cost) {
          throw StateError('Not enough resources');
        }
      }
    }

    // Deduct costs
    for (final entry in repairCosts.entries) {
      final resourceId = entry.key;
      final cost = entry.value;

      if (Currency.isGpId(resourceId)) {
        state = state.addCurrency(Currency.gp, -cost);
      } else {
        newTownship = newTownship.removeResource(resourceId, cost);
      }
    }

    // Restore efficiency to 100%
    final newBuildingState = buildingState.copyWith(efficiency: 100);
    final newBiomeState = biomeState.withBuildingState(
      buildingId,
      newBuildingState,
    );
    newTownship = newTownship.withBiomeState(biomeId, newBiomeState);

    return state.copyWith(township: newTownship);
  }

  /// Returns true if the player can afford the given costs
  /// (GP + township resources).
  bool canAffordTownshipCosts(Map<MelvorId, int> costs) {
    for (final entry in costs.entries) {
      if (Currency.isGpId(entry.key)) {
        if (gp < entry.value) return false;
      } else {
        if (township.resourceAmount(entry.key) < entry.value) return false;
      }
    }
    return true;
  }

  /// Returns true if the player can afford all repair costs for a building.
  bool canAffordTownshipRepair(MelvorId biomeId, MelvorId buildingId) =>
      canAffordTownshipCosts(township.repairCosts(biomeId, buildingId));

  /// Returns true if the player can afford the building costs (ignoring level
  /// requirements). Returns false if building/biome data is invalid.
  bool canAffordTownshipBuildingCosts(MelvorId biomeId, MelvorId buildingId) {
    final building = registries.township.buildingById(buildingId);
    if (building == null) return false;

    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) return false;

    final costs = township.buildingCostsWithModifier(biomeData.costs);
    return canAffordTownshipCosts(costs);
  }

  /// Returns true if the player can afford all repair costs for all buildings.
  bool canAffordAllTownshipRepairs() =>
      canAffordTownshipCosts(township.totalRepairCosts);

  /// Repairs all Township buildings across all biomes, restoring efficiency
  /// to 100%. Throws if no buildings need repair or player can't afford costs.
  GlobalState repairAllTownshipBuildings() {
    if (!township.hasAnyBuildingNeedingRepair) {
      throw StateError('No buildings need repair');
    }
    final totalCosts = township.totalRepairCosts;
    if (!canAffordTownshipCosts(totalCosts)) {
      throw StateError('Cannot afford repair costs');
    }

    // Deduct all costs
    var state = this;
    var newTownship = township;

    for (final entry in totalCosts.entries) {
      final resourceId = entry.key;
      final cost = entry.value;

      if (Currency.isGpId(resourceId)) {
        state = state.addCurrency(Currency.gp, -cost);
      } else {
        newTownship = newTownship.removeResource(resourceId, cost);
      }
    }

    // Restore all buildings to 100% efficiency
    final newBiomes = <MelvorId, BiomeState>{};
    for (final biomeEntry in newTownship.biomes.entries) {
      final biomeId = biomeEntry.key;
      final biomeState = biomeEntry.value;

      final newBuildings = <MelvorId, BuildingState>{};
      for (final buildingEntry in biomeState.buildings.entries) {
        final buildingState = buildingEntry.value;
        newBuildings[buildingEntry.key] = buildingState.copyWith(
          efficiency: 100,
        );
      }

      newBiomes[biomeId] = biomeState.copyWith(buildings: newBuildings);
    }

    newTownship = newTownship.copyWith(biomes: newBiomes);
    return state.copyWith(township: newTownship);
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

  /// Returns true if the player meets all requirements to equip the item.
  bool canEquipGear(Item item) {
    return item.equipRequirements.every((req) => req.isMet(this));
  }

  /// Returns the list of equipment requirements not met by the player.
  /// Returns an empty list if all requirements are met.
  List<ShopRequirement> unmetEquipRequirements(Item item) {
    return item.equipRequirements.where((req) => !req.isMet(this)).toList();
  }

  /// Equips a gear item from inventory to a specific equipment slot.
  /// For summoning tablets, equips the entire stack from inventory.
  /// For other items, removes one item from inventory and equips it.
  /// If there was an item in that slot, it's returned to inventory.
  /// Throws StateError if player doesn't have the item, doesn't meet
  /// requirements, or inventory is full when swapping.
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
    if (!canEquipGear(item)) {
      throw StateError('Cannot equip ${item.name}: requirements not met');
    }
    final itemCount = inventory.countOfItem(item);
    if (itemCount < 1) {
      throw StateError('Cannot equip ${item.name}: not in inventory');
    }

    // For stack slots (summon tablets, ammo), equip the entire stack
    if (slot.isStackSlot) {
      final previousItem = equipment.gearInSlot(slot);

      // If same item is already equipped, add to the existing stack
      if (previousItem == item) {
        final newInventory = inventory.removing(
          ItemStack(item, count: itemCount),
        );
        final newEquipment = equipment.addToStackedItem(item, slot, itemCount);
        return copyWith(inventory: newInventory, equipment: newEquipment);
      }

      // Different item - check if we have room for a swap
      if (previousItem != null) {
        if (!inventory.canAdd(previousItem, capacity: inventoryCapacity)) {
          throw StateError(
            'Inventory is full, cannot swap ${previousItem.name} for '
            '${item.name}',
          );
        }
      }

      // Remove the entire stack from inventory
      var newInventory = inventory.removing(ItemStack(item, count: itemCount));

      // Equip the item with its full count
      final (newEquipment, previousStack) = equipment.equipStackedItem(
        item,
        slot,
        itemCount,
      );

      // Add previous item stack back to inventory if there was one
      if (previousStack != null) {
        newInventory = newInventory.adding(previousStack);
      }

      return copyWith(inventory: newInventory, equipment: newEquipment);
    }

    // Regular equipment: remove one item
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
  /// For stack slots (summon tablets, ammo), returns the full stack.
  /// Throws StateError if inventory is full.
  /// Returns null if the slot is empty.
  GlobalState? unequipGear(EquipmentSlot slot) {
    // For stack slots, use unequipStackedItem to get the full stack
    if (slot.isStackSlot) {
      final result = equipment.unequipStackedItem(slot);
      if (result == null) return null;

      final (stack, newEquipment) = result;
      if (!inventory.canAdd(stack.item, capacity: inventoryCapacity)) {
        throw StateError(
          'Inventory is full, cannot unequip ${stack.item.name}',
        );
      }
      final newInventory = inventory.adding(stack);
      return copyWith(inventory: newInventory, equipment: newEquipment);
    }

    // Regular equipment: unequip single item
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

  // =========================================================================
  // Shop Purchases
  // =========================================================================

  /// Purchases a shop item, validating all requirements and costs.
  /// Throws [StateError] if:
  /// - The purchase ID is unknown
  /// - The buy limit has been reached
  /// - Unlock requirements are not met
  /// - Purchase requirements are not met
  /// - Not enough inventory space for granted items
  /// - Not enough currency or items to pay the cost
  GlobalState purchaseShopItem(MelvorId purchaseId) {
    final shopRegistry = registries.shop;
    final purchase = shopRegistry.byId(purchaseId);

    if (purchase == null) {
      throw StateError('Unknown shop purchase: $purchaseId');
    }

    // Check buy limit
    final currentCount = shop.purchaseCount(purchaseId);
    if (!purchase.isUnlimited && currentCount >= purchase.buyLimit) {
      throw StateError('Already purchased maximum of ${purchase.name}');
    }

    // Check unlock requirements
    for (final req in purchase.unlockRequirements) {
      if (!req.isMet(this)) {
        throw StateError('Unlock requirement not met for ${purchase.name}');
      }
    }

    // Check purchase requirements
    for (final req in purchase.purchaseRequirements) {
      if (!req.isMet(this)) {
        throw StateError('Purchase requirement not met for ${purchase.name}');
      }
    }

    // Check inventory space for granted items before processing
    final grantedItems = purchase.contains.items;
    if (grantedItems.isNotEmpty) {
      final capacity = inventoryCapacity;
      for (final grantedItem in grantedItems) {
        final item = registries.items.byId(grantedItem.itemId);
        if (!inventory.canAdd(item, capacity: capacity)) {
          throw StateError('Not enough bank space for ${item.name}');
        }
      }
    }

    // Calculate and apply currency costs
    var newState = this;
    final currencyCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: shop.bankSlotsPurchased,
    );
    for (final (currency, amount) in currencyCosts) {
      final balance = newState.currency(currency);
      if (balance < amount) {
        throw StateError(
          'Not enough ${currency.abbreviation}. '
          'Need $amount, have $balance',
        );
      }
      newState = newState.addCurrency(currency, -amount);
    }

    // Check and apply item costs
    final itemCosts = purchase.cost.items;
    var newInventory = newState.inventory;
    for (final itemCost in itemCosts) {
      final item = registries.items.byId(itemCost.itemId);
      final count = newInventory.countOfItem(item);
      if (count < itemCost.quantity) {
        throw StateError(
          'Not enough ${item.name}. Need ${itemCost.quantity}, have $count',
        );
      }
      newInventory = newInventory.removing(
        ItemStack(item, count: itemCost.quantity),
      );
    }

    // Add items granted by the purchase
    for (final grantedItem in purchase.contains.items) {
      final item = registries.items.byId(grantedItem.itemId);
      newInventory = newInventory.adding(
        ItemStack(item, count: grantedItem.quantity),
      );
    }

    // Handle itemCharges purchases
    var newItemCharges = newState.itemCharges;
    final itemCharges = purchase.contains.itemCharges;
    if (itemCharges != null) {
      // Get the item to receive charges
      final chargeItem = registries.items.byId(itemCharges.itemId);

      // If player doesn't have the item, add it to inventory first
      if (newInventory.countOfItem(chargeItem) == 0) {
        newInventory = newInventory.adding(ItemStack(chargeItem, count: 1));
      }

      // Add charges to the item
      newItemCharges = Map<MelvorId, int>.from(newItemCharges);
      newItemCharges[itemCharges.itemId] =
          (newItemCharges[itemCharges.itemId] ?? 0) + itemCharges.quantity;
    }

    // Apply purchase
    return newState.copyWith(
      inventory: newInventory,
      itemCharges: newItemCharges,
      shop: newState.shop.withPurchase(purchaseId),
    );
  }

  // =========================================================================
  // Farming Plot Unlocking
  // =========================================================================

  /// Unlocks a farming plot, deducting the required costs.
  /// Returns null if:
  /// - The plot ID is unknown
  /// - The player doesn't meet the level requirement
  /// - The player can't afford the currency costs
  GlobalState? unlockPlot(MelvorId plotId) {
    final plot = registries.farmingPlots.byId(plotId);
    if (plot == null) {
      return null;
    }

    // Check level requirement
    final farmingLevel = skillState(Skill.farming).skillLevel;
    if (farmingLevel < plot.level) {
      return null;
    }

    // Check currency costs
    for (final cost in plot.currencyCosts.costs) {
      if (currency(cost.currency) < cost.amount) {
        return null;
      }
    }

    // Deduct costs and unlock plot
    var newState = this;
    for (final cost in plot.currencyCosts.costs) {
      newState = newState.addCurrency(cost.currency, -cost.amount);
    }

    final newUnlockedPlots = Set<MelvorId>.from(newState.unlockedPlots)
      ..add(plotId);

    return newState.copyWith(unlockedPlots: newUnlockedPlots);
  }

  // =========================================================================
  // Batch Operations
  // =========================================================================

  /// Sells multiple item stacks at once.
  GlobalState sellItems(List<ItemStack> stacks) {
    var newState = this;
    for (final stack in stacks) {
      newState = newState.sellItem(stack);
    }
    return newState;
  }

  /// Sorts the inventory by bank sort order.
  GlobalState sortInventory() {
    return copyWith(inventory: inventory.sorted(registries.compareBankItems));
  }

  // =========================================================================
  // Cooking
  // =========================================================================

  /// Starts cooking in a specific area.
  /// Returns null if:
  /// - The player is stunned
  /// - No recipe is assigned to the area
  GlobalState? startCookingInArea(CookingArea area, {required Random random}) {
    // If stunned, do nothing
    if (isStunned) {
      return null;
    }

    // Get the recipe assigned to this area
    final areaState = cooking.areaState(area);
    if (areaState.recipeId == null) {
      return null; // No recipe assigned
    }

    // Find the cooking action
    final recipe = registries.actions
        .forSkill(Skill.cooking)
        .whereType<CookingAction>()
        .firstWhere(
          (a) => a.id == areaState.recipeId,
          orElse: () => throw StateError('Recipe not found'),
        );

    // Start the cooking action
    return startAction(recipe, random: random);
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
    Map<MelvorId, MelvorId>? selectedPotions,
    Map<MelvorId, int>? potionChargesUsed,
    Map<Currency, int>? currencies,
    TimeAway? timeAway,
    ShopState? shop,
    HealthState? health,
    Equipment? equipment,
    StunnedState? stunned,
    AttackStyle? attackStyle,
    CookingState? cooking,
    SummoningState? summoning,
    TownshipState? township,
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
      selectedPotions: selectedPotions ?? this.selectedPotions,
      potionChargesUsed: potionChargesUsed ?? this.potionChargesUsed,
      updatedAt: DateTime.timestamp(),
      currencies: currencies ?? this.currencies,
      timeAway: timeAway ?? this.timeAway,
      shop: shop ?? this.shop,
      health: health ?? this.health,
      equipment: equipment ?? this.equipment,
      stunned: stunned ?? this.stunned,
      attackStyle: attackStyle ?? this.attackStyle,
      cooking: cooking ?? this.cooking,
      summoning: summoning ?? this.summoning,
      township: township ?? this.township,
    );
  }

  /// Sets the player's attack style for combat XP distribution.
  GlobalState setAttackStyle(AttackStyle style) {
    return copyWith(attackStyle: style);
  }

  // =========================================================================
  // Potion Selection
  // =========================================================================

  /// Returns the selected potion for a skill, or null if none selected.
  Item? selectedPotionForSkill(MelvorId skillId) {
    final potionId = selectedPotions[skillId];
    if (potionId == null) return null;
    return registries.items.byId(potionId);
  }

  /// Returns the number of charges used on the current potion for a skill.
  int potionChargesUsedForSkill(MelvorId skillId) {
    return potionChargesUsed[skillId] ?? 0;
  }

  /// Selects a potion for a skill. The potion must be in inventory.
  GlobalState selectPotion(MelvorId skillId, MelvorId potionId) {
    final newSelectedPotions = Map<MelvorId, MelvorId>.from(selectedPotions)
      ..[skillId] = potionId;
    // Reset charges used when selecting a new potion
    final newChargesUsed = Map<MelvorId, int>.from(potionChargesUsed)
      ..remove(skillId);
    return copyWith(
      selectedPotions: newSelectedPotions,
      potionChargesUsed: newChargesUsed,
    );
  }

  /// Clears the potion selection for a skill.
  GlobalState clearSelectedPotion(MelvorId skillId) {
    final newSelectedPotions = Map<MelvorId, MelvorId>.from(selectedPotions)
      ..remove(skillId);
    final newChargesUsed = Map<MelvorId, int>.from(potionChargesUsed)
      ..remove(skillId);
    return copyWith(
      selectedPotions: newSelectedPotions,
      potionChargesUsed: newChargesUsed,
    );
  }

  /// Returns the total remaining uses for a potion (charges left on current
  /// potion plus inventory count times charges per potion).
  int potionUsesRemaining(MelvorId skillId) {
    final potionId = selectedPotions[skillId];
    if (potionId == null) return 0;

    final potion = registries.items.byId(potionId);
    final chargesPerPotion = potion.potionCharges ?? 1;
    final chargesUsed = potionChargesUsedForSkill(skillId);
    final chargesLeft = chargesPerPotion - chargesUsed;
    final inventoryCount = inventory.countById(potionId);

    // Current potion charges + remaining inventory potions worth of charges
    return chargesLeft + (inventoryCount - 1) * chargesPerPotion;
  }
}
