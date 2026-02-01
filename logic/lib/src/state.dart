import 'dart:math';

import 'package:logic/src/action_state.dart';
import 'package:logic/src/activity/active_activity.dart';
import 'package:logic/src/activity/combat_context.dart';
import 'package:logic/src/activity/mining_persistent_state.dart';
import 'package:logic/src/agility_state.dart';
import 'package:logic/src/astrology_state.dart';
import 'package:logic/src/bonfire_state.dart';
import 'package:logic/src/combat_stats.dart';
import 'package:logic/src/cooking_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/item_upgrades.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/data/slayer.dart';
import 'package:logic/src/data/summoning_synergy.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/plot_state.dart';
import 'package:logic/src/summoning_state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/township_state.dart';
import 'package:logic/src/types/drop.dart' show MasteryTokenDrop;
import 'package:logic/src/types/equipment.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/health.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/loot_state.dart';
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

  /// Returns the mastery pool percentage (0-100) for this skill.
  ///
  /// Requires registries to calculate max pool XP (based on action count).
  double masteryPoolPercent(Registries registries, Skill skill) {
    final maxPoolXp = maxMasteryPoolXpForSkill(registries, skill);
    if (maxPoolXp <= 0) return 0;
    return (masteryPoolXp / maxPoolXp) * 100;
  }

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
    required this.activeActivity,
    required this.skillStates,
    required this.actionStates,
    required this.updatedAt,
    required this.currencies,
    required this.shop,
    required this.health,
    required this.equipment,
    required this.registries,
    this.miningState = const MiningPersistentState.empty(),
    this.plotStates = const {},
    this.unlockedPlots = const {},
    this.dungeonCompletions = const {},
    this.strongholdCompletions = const {},
    this.slayerTaskCompletions = const {},
    this.itemCharges = const {},
    this.selectedPotions = const {},
    this.potionChargesUsed = const {},
    this.timeAway,
    this.stunned = const StunnedState.fresh(),
    this.attackStyle = AttackStyle.stab,
    this.agility = const AgilityState.empty(),
    this.cooking = const CookingState.empty(),
    this.summoning = const SummoningState.empty(),
    this.township = const TownshipState.empty(),
    this.bonfire = const BonfireState.empty(),
    this.loot = const LootState.empty(),
    this.astrology = const AstrologyState.empty(),
    this.selectedSkillActions = const {},
  });

  GlobalState.empty(Registries registries)
    : this(
        inventory: Inventory.empty(registries.items),
        activeActivity: null,
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
        strongholdCompletions: const {},
        itemCharges: const {},
        selectedPotions: const {},
        potionChargesUsed: const {},
        // Unlock all free starter plots (level 1, 0 GP cost)
        unlockedPlots: registries.farming.initialPlots(),
        // Initialize township resources with starting amounts
        township: TownshipState.initial(registries.township),
        selectedSkillActions: const {},
      );

  @visibleForTesting
  factory GlobalState.test(
    Registries registries, {
    Inventory? inventory,
    ActiveActivity? activeActivity,
    Map<Skill, SkillState> skillStates = const {},
    Map<ActionId, ActionState> actionStates = const {},
    MiningPersistentState miningState = const MiningPersistentState.empty(),
    Map<MelvorId, PlotState> plotStates = const {},
    Set<MelvorId> unlockedPlots = const {},
    Map<MelvorId, int> dungeonCompletions = const {},
    Map<MelvorId, int> strongholdCompletions = const {},
    Map<MelvorId, int> slayerTaskCompletions = const {},
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
    BonfireState bonfire = const BonfireState.empty(),
    LootState loot = const LootState.empty(),
    AstrologyState astrology = const AstrologyState.empty(),
    Map<Skill, MelvorId> selectedSkillActions = const {},
  }) {
    // Support both gp parameter (for existing tests) and currencies map
    final currenciesMap = currencies ?? (gp > 0 ? {Currency.gp: gp} : const {});

    return GlobalState(
      registries: registries,
      inventory: inventory ?? Inventory.empty(registries.items),
      activeActivity: activeActivity,
      skillStates: skillStates,
      actionStates: actionStates,
      miningState: miningState,
      plotStates: plotStates,
      unlockedPlots: unlockedPlots,
      dungeonCompletions: dungeonCompletions,
      strongholdCompletions: strongholdCompletions,
      slayerTaskCompletions: slayerTaskCompletions,
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
      bonfire: bonfire,
      loot: loot,
      astrology: astrology,
      selectedSkillActions: selectedSkillActions,
    );
  }

  GlobalState.fromJson(this.registries, Map<String, dynamic> json)
    : updatedAt = DateTime.parse(json['updatedAt'] as String),
      inventory = Inventory.fromJson(
        registries.items,
        json['inventory'] as Map<String, dynamic>,
      ),
      // Read new format first, fall back to old format for backward compat
      activeActivity = _parseActiveActivity(json),
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
      miningState = _parseMiningState(json),
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
      strongholdCompletions = _strongholdCompletionsFromJson(json),
      slayerTaskCompletions = _slayerTaskCompletionsFromJson(json),
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
      agility =
          AgilityState.maybeFromJson(json['agility']) ??
          const AgilityState.empty(),
      cooking =
          CookingState.maybeFromJson(json['cooking']) ??
          const CookingState.empty(),
      summoning =
          SummoningState.maybeFromJson(json['summoning']) ??
          const SummoningState.empty(),
      township =
          TownshipState.maybeFromJson(registries.township, json['township']) ??
          TownshipState.initial(registries.township),
      bonfire =
          BonfireState.maybeFromJson(json['bonfire']) ??
          const BonfireState.empty(),
      loot =
          LootState.maybeFromJson(registries.items, json['loot']) ??
          const LootState.empty(),
      astrology =
          _astrologyFromJson(json['astrology']) ?? const AstrologyState.empty(),
      selectedSkillActions = _selectedSkillActionsFromJson(json);

  /// Parses activeActivity from JSON.
  static ActiveActivity? _parseActiveActivity(Map<String, dynamic> json) {
    final activityJson = json['activeActivity'] as Map<String, dynamic>?;
    if (activityJson == null) return null;
    return ActiveActivity.fromJson(activityJson);
  }

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

  static Map<MelvorId, int> _strongholdCompletionsFromJson(
    Map<String, dynamic> json,
  ) {
    final completionsJson =
        json['strongholdCompletions'] as Map<String, dynamic>? ?? {};
    return completionsJson.map((key, value) {
      return MapEntry(MelvorId.fromJson(key), value as int);
    });
  }

  static Map<MelvorId, int> _slayerTaskCompletionsFromJson(
    Map<String, dynamic> json,
  ) {
    final completionsJson =
        json['slayerTaskCompletions'] as Map<String, dynamic>? ?? {};
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

  /// Parses mining state from JSON.
  static MiningPersistentState _parseMiningState(Map<String, dynamic> json) {
    final miningJson = json['miningState'] as Map<String, dynamic>?;
    if (miningJson != null) {
      return MiningPersistentState.fromJson(miningJson);
    }
    return const MiningPersistentState.empty();
  }

  /// Parses astrology state from JSON.
  static AstrologyState? _astrologyFromJson(dynamic json) {
    if (json == null) return null;
    return AstrologyState.fromJson(json as Map<String, dynamic>);
  }

  static Map<Skill, MelvorId> _selectedSkillActionsFromJson(
    Map<String, dynamic> json,
  ) {
    final actionsJson =
        json['selectedSkillActions'] as Map<String, dynamic>? ?? {};
    return actionsJson.map((key, value) {
      return MapEntry(Skill.fromName(key), MelvorId.fromJson(value as String));
    });
  }

  bool validate() {
    // Confirm that the active action id is a valid action.
    final actionId = currentActionId;
    if (actionId != null) {
      // This will throw a StateError if the action is missing.
      registries.actionById(actionId);
    }
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'inventory': inventory.toJson(),
      'activeActivity': activeActivity?.toJson(),
      'skillStates': skillStates.map(
        (key, value) => MapEntry(key.name, value.toJson()),
      ),
      'actionStates': actionStates.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'miningState': miningState.toJson(),
      'plotStates': plotStates.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
      'unlockedPlots': unlockedPlots.map((e) => e.toJson()).toList(),
      'dungeonCompletions': dungeonCompletions.map(
        (key, value) => MapEntry(key.toJson(), value),
      ),
      'strongholdCompletions': strongholdCompletions.map(
        (key, value) => MapEntry(key.toJson(), value),
      ),
      'slayerTaskCompletions': slayerTaskCompletions.map(
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
      'agility': agility.toJson(),
      'cooking': cooking.toJson(),
      'summoning': summoning.toJson(),
      'township': township.toJson(),
      'bonfire': bonfire.toJson(),
      'loot': loot.toJson(),
      'astrology': astrology.toJson(),
      'selectedSkillActions': selectedSkillActions.map(
        (key, value) => MapEntry(key.name, value.toJson()),
      ),
    };
  }

  /// The last time the state was updated (created since it's immutable).
  final DateTime updatedAt;

  /// The inventory of items.
  final Inventory inventory;

  /// The active activity (primary stored field).
  final ActiveActivity? activeActivity;

  /// Returns the ActionId of the currently active action, or null if none.
  ActionId? get currentActionId {
    final activity = activeActivity;
    if (activity == null) return null;
    return switch (activity) {
      SkillActivity(:final skill, :final actionId) => ActionId(
        skill.id,
        actionId,
      ),
      CookingActivity(:final activeRecipeId) => activeRecipeId,
      CombatActivity(:final context) => ActionId(
        Skill.combat.id,
        context.currentMonsterId,
      ),
      AgilityActivity(:final currentObstacleId) => currentObstacleId,
    };
  }

  /// Returns true if the given action is currently active.
  bool isActionActive(Action action) => currentActionId == action.id;

  /// The accumulated skill states.
  final Map<Skill, SkillState> skillStates;

  /// The accumulated action states.
  final Map<ActionId, ActionState> actionStates;

  /// Persistent mining rock state (HP, respawn timers).
  final MiningPersistentState miningState;

  /// The farming plot states (plot ID -> plot state).
  final Map<MelvorId, PlotState> plotStates;

  /// The set of unlocked farming plots.
  final Set<MelvorId> unlockedPlots;

  /// Map of dungeon ID to number of completions.
  final Map<MelvorId, int> dungeonCompletions;

  /// Returns how many times a dungeon has been completed.
  int dungeonCompletionCount(MelvorId dungeonId) =>
      dungeonCompletions[dungeonId] ?? 0;

  /// Map of stronghold ID to number of completions.
  final Map<MelvorId, int> strongholdCompletions;

  /// Map of slayer task category ID to number of completions.
  final Map<MelvorId, int> slayerTaskCompletions;

  /// Returns true if the given equipment slot is unlocked.
  /// Most slots are always unlocked. The Passive slot requires completing
  /// the "Into the Mist" dungeon.
  bool isSlotUnlocked(EquipmentSlot slot) {
    final slotDef = registries.equipmentSlots[slot];
    if (slotDef == null || !slotDef.requiresUnlock) return true;
    return dungeonCompletionCount(slotDef.unlockDungeonId!) >= 1;
  }

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

  /// Returns how many Slayer tasks have been completed in a category or higher.
  /// Checks all categories at or above the given category tier.
  int completedSlayerTaskCount(MelvorId category) {
    var count = slayerTaskCompletions[category] ?? 0;
    // Also count tasks from higher tiers
    // In Melvor, completing higher tier tasks counts toward lower tier counts
    final categories = registries.slayer.taskCategories.all;
    final categoryIndex = categories.indexWhere((c) => c.id == category);
    if (categoryIndex >= 0) {
      for (var i = categoryIndex + 1; i < categories.length; i++) {
        count += slayerTaskCompletions[categories[i].id] ?? 0;
      }
    }
    return count;
  }

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

  /// The agility state (tracks built obstacles in course slots).
  final AgilityState agility;

  /// The cooking state (tracks all 3 cooking areas).
  final CookingState cooking;

  /// The summoning state (tracks discovered marks per familiar).
  final SummoningState summoning;

  /// The township state (town management skill).
  final TownshipState township;

  /// The bonfire state (active bonfire for firemaking XP bonus).
  final BonfireState bonfire;

  /// The combat loot container (items dropped but not yet collected).
  final LootState loot;

  /// The astrology modifier purchase state.
  final AstrologyState astrology;

  /// The last selected action per skill for UI navigation.
  /// Used to remember which action (e.g., which log type in firemaking) the
  /// player was viewing when they navigate away and back to a skill screen.
  final Map<Skill, MelvorId> selectedSkillActions;

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
    final activity = activeActivity;
    if (activity is CombatActivity) {
      return activity.progress.isSpawning;
    }
    return false;
  }

  int get inventoryCapacity => shop.bankSlotsPurchased + initialBankSlots;

  bool get isActive => activeActivity != null;

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
    for (final mining in miningState.rockStates.values) {
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

    // Check bonfire timer
    if (bonfire.isActive) {
      return true;
    }

    return false;
  }

  /// Returns true if the game loop should be running.
  bool get shouldTick => isActive || hasActiveBackgroundTimers;

  Skill? activeSkill() {
    final activity = activeActivity;
    return switch (activity) {
      null => null,
      SkillActivity(:final skill) => skill,
      CookingActivity() => Skill.cooking,
      CombatActivity() => Skill.combat,
      AgilityActivity() => Skill.agility,
    };
  }

  /// Returns the number of unique item types (slots) used in inventory.
  int get inventoryUsed => inventory.items.length;

  /// Returns the number of available inventory slots remaining.
  int get inventoryRemaining => inventoryCapacity - inventoryUsed;

  /// Returns true if the inventory is at capacity (no more slots available).
  bool get isInventoryFull => inventoryUsed >= inventoryCapacity;

  /// Returns true if there is loot waiting to be collected.
  bool get hasLoot => loot.isNotEmpty;

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
        final rockState = miningState.rockState(action.id.localId);
        if (rockState.isDepleted) {
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
  ///
  /// [conditionContext] is required - pass [ConditionContext.empty] if no
  /// conditional modifiers need to be evaluated, or a populated context
  /// for combat/HP-based conditions.
  ModifierProvider createActionModifierProvider(
    SkillAction action, {
    required ConditionContext conditionContext,
  }) {
    return ModifierProvider(
      registries: registries,
      equipment: equipment,
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      inventory: inventory,
      summoning: summoning,
      shopPurchases: shop,
      actionStateGetter: actionState,
      skillStateGetter: skillState,
      activeSynergy: _getActiveSynergy(),
      agility: agility,
      astrology: astrology,
      currentActionId: action.id,
      conditionContext: _withActivePotions(conditionContext),
    );
  }

  /// Creates a ModifierProvider for combat.
  ///
  /// Filters summoning familiar modifiers by combat type relevance
  /// (melee familiars only apply during melee combat, etc.).
  ///
  /// [conditionContext] is required - pass [ConditionContext.empty] if no
  /// conditional modifiers need to be evaluated, or a populated context
  /// for combat/HP-based conditions.
  ModifierProvider createCombatModifierProvider({
    required ConditionContext conditionContext,
  }) {
    return ModifierProvider(
      registries: registries,
      equipment: equipment,
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      inventory: inventory,
      summoning: summoning,
      shopPurchases: shop,
      actionStateGetter: actionState,
      skillStateGetter: skillState,
      activeSynergy: _getActiveSynergy(),
      agility: agility,
      astrology: astrology,
      combatTypeSkills: attackStyle.combatType.skills,
      conditionContext: _withActivePotions(conditionContext),
    );
  }

  /// Creates a ModifierProvider for global modifiers (auto-eat, etc.).
  ///
  /// Use this when querying modifiers that don't depend on a specific
  /// action or combat context.
  ///
  /// [conditionContext] is required - pass [ConditionContext.empty] if no
  /// conditional modifiers need to be evaluated, or a populated context
  /// for combat/HP-based conditions.
  ModifierProvider createGlobalModifierProvider({
    required ConditionContext conditionContext,
  }) {
    return ModifierProvider(
      registries: registries,
      equipment: equipment,
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      inventory: inventory,
      summoning: summoning,
      shopPurchases: shop,
      actionStateGetter: actionState,
      skillStateGetter: skillState,
      activeSynergy: _getActiveSynergy(),
      agility: agility,
      astrology: astrology,
      conditionContext: _withActivePotions(conditionContext),
    );
  }

  /// Computes the set of active herblore recipe IDs from selected potions.
  Set<MelvorId> _activePotionRecipeIds() {
    final result = <MelvorId>{};
    for (final potionItemId in selectedPotions.values) {
      final recipeId = registries.herblore.recipeIdForPotionItem(potionItemId);
      if (recipeId != null) result.add(recipeId);
    }
    return result;
  }

  /// Merges active potion recipes into a condition context.
  ConditionContext _withActivePotions(ConditionContext context) {
    final recipes = _activePotionRecipeIds();
    if (recipes.isEmpty) return context;
    return ConditionContext(
      playerHpPercent: context.playerHpPercent,
      enemyHpPercent: context.enemyHpPercent,
      itemCharges: context.itemCharges,
      bankItemCounts: context.bankItemCounts,
      activePotionRecipes: recipes,
      activeEffectGroups: context.activeEffectGroups,
      isFightingSlayerTask: context.isFightingSlayerTask,
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
    final action1 = registries.summoning.actionForTablet(tablet1.id);
    final action2 = registries.summoning.actionForTablet(tablet2.id);
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
    final modifiers = createActionModifierProvider(
      action,
      conditionContext: ConditionContext.empty,
    );

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

  /// Cleans up state when leaving the current activity.
  ///
  /// This is the single point of control for all activity transition cleanup.
  /// Called before starting any new activity to ensure proper state cleanup.
  ///
  /// With [CookingActivity], cooking progress is stored in the activity itself,
  /// so it's automatically cleared when the activity is replaced.
  /// Recipe assignments remain in [CookingState] and are preserved.
  GlobalState _prepareForActivitySwitch({required bool stayingInCooking}) {
    // Currently a no-op. With CookingActivity, progress is stored in the
    // activity itself. When we switch away, the CookingActivity is replaced
    // and progress is automatically lost. No explicit cleanup needed.
    //
    // This method exists as the central point for future activity-specific
    // cleanup if needed.
    // ignore: avoid_returning_this
    return this;
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

    // Prepare state for activity switch (handles cooking cleanup, etc.)
    final stayingInCooking = action is CookingAction;
    final prepared = _prepareForActivitySwitch(
      stayingInCooking: stayingInCooking,
    );

    final actionId = action.id;
    int totalTicks;

    if (action is CookingAction) {
      // Cooking uses CookingActivity for multi-area progress tracking
      final actionStateVal = prepared.actionState(actionId);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);

      // Validate that all required items are available
      for (final requirement in inputs.entries) {
        final item = registries.items.byId(requirement.key);
        final itemCount = prepared.inventory.countOfItem(item);
        if (itemCount < requirement.value) {
          throw Exception(
            'Cannot start ${action.name}: Need ${requirement.value} '
            '${requirement.key.name}, but only have $itemCount',
          );
        }
      }

      totalTicks = skillDuration(action);
      final activeArea = CookingArea.fromCategoryId(action.categoryId)!;

      // Build area progress from CookingState recipe assignments.
      // Each area with a recipe gets initialized with full countdown.
      final areaProgress = <CookingArea, CookingAreaProgress>{};
      for (final (area, areaState) in prepared.cooking.allAreas) {
        final recipeId = areaState.recipeId;
        if (recipeId == null) continue;

        // Get duration for this area's recipe
        final recipe = registries.cooking.byId(recipeId.localId);
        if (recipe == null) continue;
        final areaTicks = skillDuration(recipe);

        areaProgress[area] = CookingAreaProgress(
          recipeId: recipeId,
          ticksRemaining: areaTicks,
          totalTicks: areaTicks,
        );
      }

      return prepared.copyWith(
        activeActivity: CookingActivity(
          activeArea: activeArea,
          activeRecipeId: actionId,
          areaProgress: areaProgress,
          progressTicks: 0,
          totalTicks: totalTicks,
          selectedRecipeIndex: actionStateVal.selectedRecipeIndex,
        ),
      );
    } else if (action is SkillAction) {
      final actionStateVal = prepared.actionState(actionId);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);

      // Validate that all required items are available for skill actions
      for (final requirement in inputs.entries) {
        final item = registries.items.byId(requirement.key);
        final itemCount = prepared.inventory.countOfItem(item);
        if (itemCount < requirement.value) {
          throw Exception(
            'Cannot start ${action.name}: Need ${requirement.value} '
            '${requirement.key.name}, but only have $itemCount',
          );
        }
      }
      totalTicks = skillDuration(action);
      return prepared.copyWith(
        activeActivity: SkillActivity(
          skill: action.skill,
          actionId: actionId.localId,
          progressTicks: 0,
          totalTicks: totalTicks,
          selectedRecipeIndex: actionStateVal.selectedRecipeIndex,
        ),
      );
    } else if (action is CombatAction) {
      // Combat actions don't have inputs or duration-based completion.
      // The tick represents the time until the first player attack.
      final pStats = computePlayerStats(prepared);
      totalTicks = ticksFromDuration(
        Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
      );
      // Calculate spawn ticks with modifiers (e.g., Monster Hunter Scroll)
      final modifiers = prepared.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );
      final spawnTicks = calculateMonsterSpawnTicks(
        modifiers.flatMonsterRespawnInterval,
      );
      // Initialize combat state with the combat action, starting with respawn
      final combatState = CombatActionState.start(
        action,
        pStats,
        spawnTicks: spawnTicks,
      );
      final newActionStates = Map<ActionId, ActionState>.from(
        prepared.actionStates,
      );
      final existingState = prepared.actionState(actionId);
      newActionStates[actionId] = existingState.copyWith(combat: combatState);
      return prepared.copyWith(
        activeActivity: CombatActivity(
          context: MonsterCombatContext(monsterId: action.id.localId),
          progress: CombatProgressState(
            monsterHp: combatState.monsterHp,
            playerAttackTicksRemaining: combatState.playerAttackTicksRemaining,
            monsterAttackTicksRemaining:
                combatState.monsterAttackTicksRemaining,
            spawnTicksRemaining: combatState.spawnTicksRemaining,
          ),
          progressTicks: 0,
          totalTicks: totalTicks,
        ),
        actionStates: newActionStates,
      );
    } else {
      throw Exception('Unknown action type: ${action.runtimeType}');
    }
  }

  /// Starts a dungeon run, fighting monsters in order.
  GlobalState startDungeon(Dungeon dungeon) => _startSequence(
    type: SequenceType.dungeon,
    id: dungeon.id,
    monsterIds: dungeon.monsterIds,
  );

  /// Starts a stronghold run, fighting monsters in order.
  GlobalState startStronghold(Stronghold stronghold) => _startSequence(
    type: SequenceType.stronghold,
    id: stronghold.id,
    monsterIds: stronghold.monsterIds,
  );

  GlobalState _startSequence({
    required SequenceType type,
    required MelvorId id,
    required List<MelvorId> monsterIds,
  }) {
    if (isStunned) {
      throw StunnedException('Cannot start ${type.name} while stunned');
    }
    if (monsterIds.isEmpty) {
      throw ArgumentError('${type.name} has no monsters: $id');
    }

    final prepared = _prepareForActivitySwitch(stayingInCooking: false);

    final firstMonster = registries.combat.monsterById(monsterIds.first);
    final actionId = firstMonster.id;

    final pStats = computePlayerStats(prepared);
    final totalTicks = ticksFromDuration(
      Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
    );

    final modifiers = prepared.createCombatModifierProvider(
      conditionContext: ConditionContext.empty,
    );
    final spawnTicks = calculateMonsterSpawnTicks(
      modifiers.flatMonsterRespawnInterval,
    );

    final combatState = CombatActionState.startDungeon(
      firstMonster,
      pStats,
      id,
      spawnTicks: spawnTicks,
    );
    final newActionStates = Map<ActionId, ActionState>.from(
      prepared.actionStates,
    );
    final existingState = prepared.actionState(actionId);
    newActionStates[actionId] = existingState.copyWith(combat: combatState);

    return prepared.copyWith(
      activeActivity: CombatActivity(
        context: SequenceCombatContext(
          sequenceType: type,
          sequenceId: id,
          currentMonsterIndex: 0,
          monsterIds: monsterIds,
        ),
        progress: CombatProgressState(
          monsterHp: combatState.monsterHp,
          playerAttackTicksRemaining: combatState.playerAttackTicksRemaining,
          monsterAttackTicksRemaining: combatState.monsterAttackTicksRemaining,
          spawnTicksRemaining: combatState.spawnTicksRemaining,
        ),
        progressTicks: 0,
        totalTicks: totalTicks,
      ),
      actionStates: newActionStates,
    );
  }

  /// Starts a slayer task for the given category.
  ///
  /// This rolls a random monster based on the category's selection criteria
  /// and a random number of kills required.
  GlobalState startSlayerTask({
    required SlayerTaskCategory category,
    required Random random,
  }) {
    if (isStunned) {
      throw const StunnedException('Cannot start slayer task while stunned');
    }

    // Check slayer level requirement
    final slayerLevel = skillState(Skill.slayer).skillLevel;
    if (slayerLevel < category.level) {
      throw ArgumentError(
        'Slayer level ${category.level} required for ${category.name} tasks',
      );
    }

    // Check currency cost
    for (final cost in category.rollCost.costs) {
      if (currency(cost.currency) < cost.amount) {
        throw ArgumentError(
          'Not enough ${cost.currency.abbreviation} to roll slayer task',
        );
      }
    }

    // Find eligible monsters based on selection criteria
    final selection = category.monsterSelection;
    final eligibleMonsters = <CombatAction>[];

    if (selection is CombatLevelSelection) {
      for (final monster in registries.combat.monsters) {
        if (monster.combatLevel >= selection.minLevel &&
            monster.combatLevel <= selection.maxLevel &&
            monster.canSlayer) {
          eligibleMonsters.add(monster);
        }
      }
    }

    if (eligibleMonsters.isEmpty) {
      throw StateError('No eligible monsters for ${category.name} slayer task');
    }

    // Pick a random monster
    final monster = eligibleMonsters[random.nextInt(eligibleMonsters.length)];

    // Calculate kills required (base length +/- some variance)
    final baseKills = category.baseTaskLength;
    final variance = (baseKills * 0.2).toInt().clamp(1, 100);
    final killsRequired =
        baseKills + random.nextInt(variance * 2 + 1) - variance;

    // Deduct currency cost
    var prepared = _prepareForActivitySwitch(stayingInCooking: false);
    final newCurrencies = Map<Currency, int>.from(prepared.currencies);
    for (final cost in category.rollCost.costs) {
      newCurrencies[cost.currency] =
          (newCurrencies[cost.currency] ?? 0) - cost.amount;
    }
    prepared = prepared.copyWith(currencies: newCurrencies);

    // Start combat with the slayer task context
    final pStats = computePlayerStats(prepared);
    final totalTicks = ticksFromDuration(
      Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
    );

    final modifiers = prepared.createCombatModifierProvider(
      conditionContext: ConditionContext.empty,
    );
    final spawnTicks = calculateMonsterSpawnTicks(
      modifiers.flatMonsterRespawnInterval,
    );

    final combatState = CombatActionState.start(
      monster,
      pStats,
      spawnTicks: spawnTicks,
    );

    final newActionStates = Map<ActionId, ActionState>.from(
      prepared.actionStates,
    );
    final existingState = prepared.actionState(monster.id);
    newActionStates[monster.id] = existingState.copyWith(combat: combatState);

    return prepared.copyWith(
      activeActivity: CombatActivity(
        context: SlayerTaskContext(
          categoryId: category.id,
          monsterId: monster.id.localId,
          killsRequired: killsRequired,
          killsCompleted: 0,
        ),
        progress: CombatProgressState(
          monsterHp: combatState.monsterHp,
          playerAttackTicksRemaining: combatState.playerAttackTicksRemaining,
          monsterAttackTicksRemaining: combatState.monsterAttackTicksRemaining,
          spawnTicksRemaining: combatState.spawnTicksRemaining,
        ),
        progressTicks: 0,
        totalTicks: totalTicks,
      ),
      actionStates: newActionStates,
    );
  }

  /// Checks whether the player meets all requirements for a slayer area.
  bool meetsSlayerAreaRequirements(SlayerArea area) {
    return unmetSlayerAreaRequirements(area).isEmpty;
  }

  /// Returns the list of unmet requirements for entering a slayer area.
  List<SlayerAreaRequirement> unmetSlayerAreaRequirements(SlayerArea area) {
    return area.entryRequirements.where((req) {
      return switch (req) {
        SlayerLevelRequirement(:final level) =>
          skillState(Skill.slayer).skillLevel < level,
        SlayerItemRequirement(:final itemId) => !equipment.gearSlots.values.any(
          (item) => item.id == itemId,
        ),
        SlayerDungeonRequirement(:final dungeonId, :final count) =>
          (dungeonCompletions[dungeonId] ?? 0) < count,
        SlayerShopPurchaseRequirement(:final purchaseId, :final count) =>
          shop.purchaseCount(purchaseId) < count,
      };
    }).toList();
  }

  /// Returns the active slayer area ID if the player is in one, or null.
  MelvorId? get activeSlayerAreaId {
    if (activeActivity case CombatActivity(
      :final context,
    ) when context is SlayerAreaCombatContext) {
      return context.slayerAreaId;
    }
    return null;
  }

  /// Starts combat with a monster in a slayer area.
  GlobalState startSlayerAreaCombat({
    required SlayerArea area,
    required CombatAction monster,
    required Random random,
  }) {
    if (isStunned) {
      throw const StunnedException(
        'Cannot start slayer area combat while stunned',
      );
    }
    if (!meetsSlayerAreaRequirements(area)) {
      throw StateError('Cannot enter ${area.name}: requirements not met');
    }
    if (!area.monsterIds.contains(monster.id.localId)) {
      throw ArgumentError('${monster.name} is not in slayer area ${area.name}');
    }

    final prepared = _prepareForActivitySwitch(stayingInCooking: false);

    final pStats = computePlayerStats(prepared);
    final totalTicks = ticksFromDuration(
      Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
    );

    final modifiers = prepared.createCombatModifierProvider(
      conditionContext: ConditionContext.empty,
    );
    final spawnTicks = calculateMonsterSpawnTicks(
      modifiers.flatMonsterRespawnInterval,
    );

    final combatState = CombatActionState.start(
      monster,
      pStats,
      spawnTicks: spawnTicks,
    );

    final newActionStates = Map<ActionId, ActionState>.from(
      prepared.actionStates,
    );
    final existingState = prepared.actionState(monster.id);
    newActionStates[monster.id] = existingState.copyWith(combat: combatState);

    return prepared.copyWith(
      activeActivity: CombatActivity(
        context: SlayerAreaCombatContext(
          slayerAreaId: area.id,
          monsterId: monster.id.localId,
        ),
        progress: CombatProgressState(
          monsterHp: combatState.monsterHp,
          playerAttackTicksRemaining: combatState.playerAttackTicksRemaining,
          monsterAttackTicksRemaining: combatState.monsterAttackTicksRemaining,
          spawnTicksRemaining: combatState.spawnTicksRemaining,
        ),
        progressTicks: 0,
        totalTicks: totalTicks,
      ),
      actionStates: newActionStates,
    );
  }

  /// Starts running an agility course, completing obstacles in sequence.
  ///
  /// The first built obstacle starts immediately. After each obstacle
  /// completes, the next one starts automatically. When the last obstacle
  /// completes, the course restarts from the first obstacle.
  ///
  /// Returns null if no obstacles are built in the course.
  GlobalState? startAgilityCourse({required Random random}) {
    if (isStunned) {
      throw const StunnedException('Cannot start course while stunned');
    }

    // Get the list of built obstacles in slot order
    final obstacleIds = agility.builtObstacles;
    if (obstacleIds.isEmpty) {
      return null;
    }

    // Prepare state for activity switch (handles cooking cleanup, etc.)
    final prepared = _prepareForActivitySwitch(stayingInCooking: false);

    // Get the first obstacle
    final firstObstacleId = obstacleIds.first;
    final firstObstacle = registries.agility.byId(firstObstacleId.localId)!;
    final totalTicks = rollDurationWithModifiers(
      firstObstacle,
      random,
      registries.shop,
    );

    return prepared.copyWith(
      activeActivity: AgilityActivity(
        obstacleIds: obstacleIds,
        currentObstacleIndex: 0,
        progressTicks: 0,
        totalTicks: totalTicks,
      ),
    );
  }

  /// Calculates mean duration with modifiers applied (deterministic).
  int _meanDurationWithModifiers(SkillAction action) {
    final ticks = ticksFromDuration(action.meanDuration);
    final modifiers = createActionModifierProvider(
      action,
      conditionContext: ConditionContext.empty,
    );

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

    // Prepare state for activity switch (handles cooking cleanup, etc.)
    final prepared = _prepareForActivitySwitch(stayingInCooking: false);

    return prepared._copyWithNullable(clearActiveActivity: true);
  }

  GlobalState clearTimeAway() {
    return _copyWithNullable(clearTimeAway: true);
  }

  /// Like [copyWith] but allows explicitly setting fields to null.
  /// Fields not specified retain their current values.
  GlobalState _copyWithNullable({
    AgilityState? agility,
    CookingState? cooking,
    bool clearActiveActivity = false,
    bool clearTimeAway = false,
  }) {
    return GlobalState(
      registries: registries,
      inventory: inventory,
      activeActivity: clearActiveActivity ? null : activeActivity,
      skillStates: skillStates,
      actionStates: actionStates,
      miningState: miningState,
      plotStates: plotStates,
      unlockedPlots: unlockedPlots,
      dungeonCompletions: dungeonCompletions,
      itemCharges: itemCharges,
      selectedPotions: selectedPotions,
      potionChargesUsed: potionChargesUsed,
      updatedAt: DateTime.timestamp(),
      currencies: currencies,
      timeAway: clearTimeAway ? null : timeAway,
      shop: shop,
      health: health,
      equipment: equipment,
      stunned: stunned,
      attackStyle: attackStyle,
      agility: agility ?? this.agility,
      cooking: cooking ?? this.cooking,
      summoning: summoning,
      township: township,
      bonfire: bonfire,
      loot: loot,
      slayerTaskCompletions: slayerTaskCompletions,
    );
  }

  SkillState skillState(Skill skill) =>
      skillStates[skill] ?? const SkillState.empty();

  /// Returns the number of actions unlocked for a skill based on skill level.
  int unlockedActionsCount(Skill skill) {
    final level = skillState(skill).skillLevel;
    return registries
        .actionsForSkill(skill)
        .where((action) => action.unlockLevel <= level)
        .length;
  }

  ActionState actionState(ActionId action) =>
      actionStates[action] ?? const ActionState.empty();

  int activeProgress(Action action) {
    final activity = activeActivity;
    if (activity == null || currentActionId != action.id) {
      return 0;
    }
    return activity.progressTicks;
  }

  GlobalState updateActiveActivity(
    ActionId actionId, {
    required int remainingTicks,
  }) {
    final activity = activeActivity;
    if (activity == null || currentActionId != actionId) {
      throw Exception('Active action is not $actionId');
    }
    // Calculate new progress ticks from remaining ticks
    final newProgressTicks = activity.totalTicks - remainingTicks;
    final newActivity = activity.withProgress(progressTicks: newProgressTicks);
    return copyWith(activeActivity: newActivity);
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

  /// Spends mastery pool XP to raise an action's mastery to the next level.
  ///
  /// Returns the new state, or null if insufficient pool XP or already at max.
  GlobalState? spendMasteryPoolXp(Skill skill, ActionId actionId) {
    final action = actionState(actionId);
    final currentLevel = action.masteryLevel;
    if (currentLevel >= 99) return null;

    final currentXp = action.masteryXp;
    final nextLevelXp = startXpForLevel(currentLevel + 1);
    final xpNeeded = nextLevelXp - currentXp;
    if (xpNeeded <= 0) return null;

    final pool = skillState(skill).masteryPoolXp;
    if (pool < xpNeeded) return null;

    // Deduct from pool and add to action mastery.
    return addSkillMasteryXp(
      skill,
      -xpNeeded,
    ).addActionMasteryXp(actionId, xpNeeded);
  }

  /// Returns the XP cost to raise an action's mastery to the next level,
  /// or null if already at max mastery (99).
  int? masteryLevelUpCost(ActionId actionId) {
    final action = actionState(actionId);
    final currentLevel = action.masteryLevel;
    if (currentLevel >= 99) return null;
    return startXpForLevel(currentLevel + 1) - action.masteryXp;
  }

  /// Returns which mastery pool checkpoint would be crossed if [xpCost] were
  /// spent from the pool for [skill]. Returns null if no checkpoint is crossed.
  int? masteryPoolCheckpointCrossed(Skill skill, int xpCost) {
    final pool = skillState(skill).masteryPoolXp;
    final maxPoolXp = maxMasteryPoolXpForSkill(registries, skill);
    if (maxPoolXp <= 0) return null;

    final currentPercent = (pool / maxPoolXp) * 100;
    final afterPercent = ((pool - xpCost) / maxPoolXp) * 100;

    final bonuses = registries.masteryPoolBonuses.forSkill(skill.id);
    if (bonuses == null) return null;

    // Check from highest to lowest checkpoint.
    for (final bonus in bonuses.bonuses.reversed) {
      if (currentPercent >= bonus.percent && afterPercent < bonus.percent) {
        return bonus.percent;
      }
    }
    return null;
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

  /// Returns the XP added per mastery token claim for [skill] (0.1% of max).
  int masteryTokenXpPerClaim(Skill skill) {
    final maxPoolXp = maxMasteryPoolXpForSkill(registries, skill);
    return (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);
  }

  /// Returns how many mastery tokens can be claimed without exceeding the pool
  /// cap, or 0 if the pool is already full or no tokens are held.
  int claimableMasteryTokenCount(Skill skill) {
    if (!MasteryTokenDrop.skillHasMasteryToken(skill)) return 0;

    final tokenId = MasteryTokenDrop(skill: skill).itemId;
    final token = registries.items.byId(tokenId);
    final held = inventory.countOfItem(token);
    if (held < 1) return 0;

    final maxPoolXp = maxMasteryPoolXpForSkill(registries, skill);
    final currentPoolXp = skillState(skill).masteryPoolXp;
    final remaining = maxPoolXp - currentPoolXp;
    if (remaining <= 0) return 0;

    final xpPerToken = masteryTokenXpPerClaim(skill);
    final maxClaimable = remaining ~/ xpPerToken;
    // Allow at least 1 if there's any remaining room.
    final claimable = maxClaimable < 1 && remaining > 0 ? 1 : maxClaimable;
    return claimable.clamp(0, held);
  }

  /// Claims a mastery token for a skill, adding 0.1% of max mastery pool XP.
  ///
  /// Removes one mastery token from inventory and adds 0.1% of the skill's
  /// max mastery pool XP to the mastery pool. The XP added is capped so the
  /// pool does not exceed its maximum.
  ///
  /// Throws StateError if:
  /// - The skill doesn't have mastery tokens (combat skills, Township, etc.)
  /// - Player doesn't have the mastery token in inventory
  /// - Claiming would waste XP (pool is already full)
  GlobalState claimMasteryToken(Skill skill) {
    if (!MasteryTokenDrop.skillHasMasteryToken(skill)) {
      throw StateError('Skill $skill does not have mastery tokens');
    }

    final tokenId = MasteryTokenDrop(skill: skill).itemId;
    final token = registries.items.byId(tokenId);
    final tokenCount = inventory.countOfItem(token);

    if (tokenCount < 1) {
      throw StateError('No mastery tokens for ${skill.name} in inventory');
    }

    final maxPoolXp = maxMasteryPoolXpForSkill(registries, skill);
    final currentPoolXp = skillState(skill).masteryPoolXp;
    if (currentPoolXp >= maxPoolXp) {
      throw StateError('Mastery pool for ${skill.name} is already full');
    }

    // Calculate 0.1% of max mastery pool XP, capped to remaining space.
    final xpPerToken = masteryTokenXpPerClaim(skill);
    final remaining = maxPoolXp - currentPoolXp;
    final xpToAdd = xpPerToken.clamp(1, remaining);

    // Remove token from inventory
    final newInventory = inventory.removing(ItemStack(token, count: 1));

    // Add mastery pool XP
    return copyWith(inventory: newInventory).addSkillMasteryXp(skill, xpToAdd);
  }

  /// Claims mastery tokens for a skill, only as many as fit without exceeding
  /// the pool cap.
  ///
  /// Returns the new state after claiming tokens, or this state if
  /// there are no tokens to claim or the pool is full.
  GlobalState claimAllMasteryTokens(Skill skill) {
    if (!MasteryTokenDrop.skillHasMasteryToken(skill)) {
      return this;
    }

    final tokenId = MasteryTokenDrop(skill: skill).itemId;
    final token = registries.items.byId(tokenId);

    final claimable = claimableMasteryTokenCount(skill);
    if (claimable < 1) return this;

    final maxPoolXp = maxMasteryPoolXpForSkill(registries, skill);
    final currentPoolXp = skillState(skill).masteryPoolXp;
    final remaining = maxPoolXp - currentPoolXp;
    final xpPerToken = masteryTokenXpPerClaim(skill);
    final totalXp = (xpPerToken * claimable).clamp(0, remaining);

    // Remove only the claimable tokens from inventory
    final tokenStack = ItemStack(token, count: claimable);
    final newInventory = inventory.removing(tokenStack);

    // Add mastery pool XP
    return copyWith(inventory: newInventory).addSkillMasteryXp(skill, totalXp);
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
  /// Returns an error message if removing [item] from equipment would violate
  /// the current slayer area's item requirements, or null if the change is OK.
  String? slayerAreaGearChangeError(Item item) {
    final areaId = activeSlayerAreaId;
    if (areaId == null) return null;
    final area = registries.slayer.areas.byId(areaId);
    if (area == null) return null;
    for (final req in area.entryRequirements) {
      if (req is SlayerItemRequirement && req.itemId == item.id) {
        return 'Cannot remove ${item.name}: required by ${area.name}';
      }
    }
    return null;
  }

  GlobalState equipGear(Item item, EquipmentSlot slot) {
    if (!item.isEquippable) {
      throw StateError('Cannot equip ${item.name}: not equippable');
    }
    if (!item.canEquipInSlot(slot)) {
      throw StateError(
        'Cannot equip ${item.name} in $slot slot. '
        'Valid slots: ${item.validSlots.map((s) => s.jsonName).join(', ')}',
      );
    }
    if (!isSlotUnlocked(slot)) {
      throw StateError('Cannot equip in $slot: slot is locked');
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
    final category = registries.farming.categoryById(crop.categoryId);
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
    final crop = registries.farming.cropById(cropId);
    if (crop == null) {
      throw StateError('Crop $cropId not found');
    }

    final category = registries.farming.categoryById(crop.categoryId);
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
    final plot = registries.farming.plotById(plotId);
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

  /// Upgrades items using an upgrade recipe.
  /// Returns null if requirements not met (insufficient items/currency).
  GlobalState? upgradeItem(ItemUpgrade upgrade, int count) {
    // Check we have all required items
    for (final cost in upgrade.itemCosts) {
      final required = cost.quantity * count;
      if (inventory.countById(cost.itemId) < required) return null;
    }

    // Check we have currency
    final gpCost = upgrade.currencyCosts.gpCost * count;
    if (gp < gpCost) return null;

    // Remove input items
    var newInventory = inventory;
    for (final cost in upgrade.itemCosts) {
      final item = registries.items.byId(cost.itemId);
      newInventory = newInventory.removing(
        ItemStack(item, count: cost.quantity * count),
      );
    }

    // Remove currency
    var newState = copyWith(inventory: newInventory);
    if (gpCost > 0) {
      newState = newState.addCurrency(Currency.gp, -gpCost);
    }

    // Add output item
    final outputItem = registries.items.byId(upgrade.upgradedItemId);
    return newState.copyWith(
      inventory: newState.inventory.adding(ItemStack(outputItem, count: count)),
    );
  }

  /// Calculates max upgrades affordable for a given upgrade.
  int maxAffordableUpgrades(ItemUpgrade upgrade) {
    var maxCount = 999999;

    // Check item costs
    for (final cost in upgrade.itemCosts) {
      final available = inventory.countById(cost.itemId);
      maxCount = min(maxCount, available ~/ cost.quantity);
    }

    // Check currency costs
    final gpCost = upgrade.currencyCosts.gpCost;
    if (gpCost > 0) {
      maxCount = min(maxCount, gp ~/ gpCost);
    }

    return maxCount;
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
    final recipe = registries
        .actionsForSkill(Skill.cooking)
        .whereType<CookingAction>()
        .firstWhere(
          (a) => a.id == areaState.recipeId,
          orElse: () => throw StateError('Recipe not found'),
        );

    // Start the cooking action
    return startAction(recipe, random: random);
  }

  /// Stops the agility course if it is currently running.
  /// Returns this state unchanged if the course is not running.
  GlobalState _stopAgilityIfActive() {
    if (activeActivity is! AgilityActivity) {
      return this;
    }
    // Progress is tracked in AgilityActivity, which is cleared here.
    // No need to update AgilityState.
    return _copyWithNullable(clearActiveActivity: true);
  }

  /// Builds an obstacle in the specified agility course slot.
  ///
  /// Deducts the build costs (GP and items) and adds the obstacle to the slot.
  /// Increments the slot's purchase count for cost discount tracking.
  /// Stops the agility course if it is currently running.
  GlobalState buildAgilityObstacle(int slot, ActionId obstacleId) {
    final obstacle = registries.agility.byId(obstacleId.localId);
    if (obstacle == null) {
      throw StateError('Unknown agility obstacle: $obstacleId');
    }

    var newState = _stopAgilityIfActive();

    // Get current slot state for discount calculation
    final slotState = newState.agility.slotState(slot);
    final discount = slotState.costDiscount;

    // Check and deduct GP cost
    final gpCost = obstacle.currencyCosts.gpCost;
    if (gpCost > 0) {
      final discountedGp = (gpCost * (1 - discount)).round();
      final balance = currency(Currency.gp);
      if (balance < discountedGp) {
        throw StateError('Not enough GP. Need $discountedGp, have $balance');
      }
      newState = newState.addCurrency(Currency.gp, -discountedGp);
    }

    // Check and deduct item costs
    for (final entry in obstacle.inputs.entries) {
      final discountedQty = (entry.value * (1 - discount)).ceil();
      final available = newState.inventory.countById(entry.key);
      if (available < discountedQty) {
        final item = registries.items.byId(entry.key);
        throw StateError(
          'Not enough ${item.name}. Need $discountedQty, have $available',
        );
      }
      final item = registries.items.byId(entry.key);
      newState = newState.copyWith(
        inventory: newState.inventory.removing(
          ItemStack(item, count: discountedQty),
        ),
      );
    }

    // Update agility state with the new obstacle
    final newAgility = newState.agility.withObstacle(slot, obstacleId);
    return newState.copyWith(agility: newAgility);
  }

  /// Destroys the obstacle in the specified agility course slot.
  ///
  /// Does not refund any resources. Keeps purchase count for discount tracking.
  /// Stops the agility course if it is currently running.
  GlobalState destroyAgilityObstacle(int slot) {
    final newState = _stopAgilityIfActive();
    final newAgility = newState.agility.withObstacleDestroyed(slot);
    return newState.copyWith(agility: newAgility);
  }

  /// Creates a copy of this state with the given fields replaced.
  GlobalState copyWith({
    Inventory? inventory,
    ActiveActivity? activeActivity,
    Map<Skill, SkillState>? skillStates,
    Map<ActionId, ActionState>? actionStates,
    MiningPersistentState? miningState,
    Map<MelvorId, PlotState>? plotStates,
    Set<MelvorId>? unlockedPlots,
    Map<MelvorId, int>? dungeonCompletions,
    Map<MelvorId, int>? strongholdCompletions,
    Map<MelvorId, int>? slayerTaskCompletions,
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
    AgilityState? agility,
    CookingState? cooking,
    SummoningState? summoning,
    TownshipState? township,
    BonfireState? bonfire,
    LootState? loot,
    AstrologyState? astrology,
    Map<Skill, MelvorId>? selectedSkillActions,
  }) {
    return GlobalState(
      registries: registries,
      inventory: inventory ?? this.inventory,
      activeActivity: activeActivity ?? this.activeActivity,
      skillStates: skillStates ?? this.skillStates,
      actionStates: actionStates ?? this.actionStates,
      miningState: miningState ?? this.miningState,
      plotStates: plotStates ?? this.plotStates,
      unlockedPlots: unlockedPlots ?? this.unlockedPlots,
      dungeonCompletions: dungeonCompletions ?? this.dungeonCompletions,
      strongholdCompletions:
          strongholdCompletions ?? this.strongholdCompletions,
      slayerTaskCompletions:
          slayerTaskCompletions ?? this.slayerTaskCompletions,
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
      agility: agility ?? this.agility,
      cooking: cooking ?? this.cooking,
      summoning: summoning ?? this.summoning,
      township: township ?? this.township,
      bonfire: bonfire ?? this.bonfire,
      loot: loot ?? this.loot,
      astrology: astrology ?? this.astrology,
      selectedSkillActions: selectedSkillActions ?? this.selectedSkillActions,
    );
  }

  /// Sets the player's attack style for combat XP distribution.
  GlobalState setAttackStyle(AttackStyle style) {
    return copyWith(attackStyle: style);
  }

  /// Sets the last selected action for a skill.
  ///
  /// Used to remember which action the player was viewing in a skill screen.
  GlobalState setSelectedSkillAction(Skill skill, MelvorId actionId) {
    final newSelectedActions = Map<Skill, MelvorId>.from(selectedSkillActions);
    newSelectedActions[skill] = actionId;
    return copyWith(selectedSkillActions: newSelectedActions);
  }

  /// Gets the last selected action ID for a skill, or null if none.
  MelvorId? selectedSkillAction(Skill skill) => selectedSkillActions[skill];

  // =========================================================================
  // Astrology
  // =========================================================================

  /// Purchases one level of an astrology modifier for a constellation.
  ///
  /// Consumes stardust (for standard) or golden stardust (for unique) from
  /// inventory and increments the modifier level.
  ///
  /// Returns the new state, or throws if insufficient currency.
  GlobalState purchaseAstrologyModifier({
    required MelvorId constellationId,
    required AstrologyModifierType modifierType,
    required int modifierIndex,
  }) {
    // Get the constellation and modifier
    final constellation = registries.astrology.byId(constellationId);
    if (constellation == null) {
      throw StateError('Constellation not found: $constellationId');
    }

    final modifiers = modifierType == AstrologyModifierType.standard
        ? constellation.standardModifiers
        : constellation.uniqueModifiers;

    if (modifierIndex >= modifiers.length) {
      throw StateError('Invalid modifier index: $modifierIndex');
    }

    final modifier = modifiers[modifierIndex];

    // Get current level and check if maxed
    final currentState = astrology.stateFor(constellationId);
    final currentLevel = currentState.levelFor(modifierType, modifierIndex);

    if (currentLevel >= modifier.maxCount) {
      throw StateError('Modifier already at max level');
    }

    // Get the cost and check inventory
    final cost = modifier.costs[currentLevel];
    final currencyItem = registries.items.byId(modifierType.currencyItemId);
    final currencyCount = inventory.countOfItem(currencyItem);

    if (currencyCount < cost) {
      throw StateError(
        'Insufficient ${currencyItem.name}: have $currencyCount, need $cost',
      );
    }

    // Deduct the currency
    final newInventory = inventory.removing(
      ItemStack(currencyItem, count: cost),
    );

    // Increment the modifier level
    final newConstellationState = currentState.withIncrementedLevel(
      modifierType,
      modifierIndex,
    );
    final newAstrology = astrology.withConstellationState(
      constellationId,
      newConstellationState,
    );

    return copyWith(inventory: newInventory, astrology: newAstrology);
  }

  /// Returns true if the player can purchase the specified modifier.
  bool canPurchaseAstrologyModifier({
    required MelvorId constellationId,
    required AstrologyModifierType modifierType,
    required int modifierIndex,
  }) {
    final constellation = registries.astrology.byId(constellationId);
    if (constellation == null) return false;

    final modifiers = modifierType == AstrologyModifierType.standard
        ? constellation.standardModifiers
        : constellation.uniqueModifiers;

    if (modifierIndex >= modifiers.length) return false;

    final modifier = modifiers[modifierIndex];
    final currentState = astrology.stateFor(constellationId);
    final currentLevel = currentState.levelFor(modifierType, modifierIndex);

    // Check if maxed
    if (currentLevel >= modifier.maxCount) return false;

    // Check mastery level requirement
    final actionState = this.actionState(constellation.id);
    final masteryLevel = actionState.masteryLevel;
    if (masteryLevel < modifier.unlockMasteryLevel) return false;

    // Check currency
    final cost = modifier.costs[currentLevel];
    final currencyItem = registries.items.byId(modifierType.currencyItemId);
    final currencyCount = inventory.countOfItem(currencyItem);

    return currencyCount >= cost;
  }

  // =========================================================================
  // Bonfire
  // =========================================================================

  /// Starts a bonfire from a firemaking action.
  ///
  /// Consumes 10 logs from inventory and starts the bonfire timer.
  /// The bonfire provides an XP bonus to firemaking while active.
  static const int bonfireLogCost = 10;

  GlobalState startBonfire(FiremakingAction action) {
    // Check that we have enough logs
    final logItem = registries.items.byId(action.logId);
    final logCount = inventory.countOfItem(logItem);
    if (logCount < bonfireLogCost) {
      throw Exception(
        'Cannot start bonfire: need $bonfireLogCost ${action.logId.name}, '
        'have $logCount',
      );
    }

    // Consume logs
    final newInventory = inventory.removing(
      ItemStack(logItem, count: bonfireLogCost),
    );

    // Start the bonfire
    final bonfireTicks = ticksFromDuration(action.bonfireInterval);
    final newBonfire = BonfireState(
      actionId: action.id,
      ticksRemaining: bonfireTicks,
      totalTicks: bonfireTicks,
      xpBonus: action.bonfireXPBonus,
    );

    return copyWith(inventory: newInventory, bonfire: newBonfire);
  }

  /// Stops the current bonfire, clearing the timer.
  GlobalState stopBonfire() {
    return copyWith(bonfire: const BonfireState.empty());
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
