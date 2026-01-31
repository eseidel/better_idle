import 'dart:io';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/cache.dart';
import 'package:logic/src/data/item_upgrades.dart';
import 'package:logic/src/data/melvor_data.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/data/slayer.dart';
import 'package:logic/src/data/summoning_synergy.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/mastery.dart';
import 'package:logic/src/types/mastery_pool_bonus.dart';
import 'package:logic/src/types/mastery_unlock.dart';
import 'package:logic/src/types/modifier_metadata.dart';
import 'package:meta/meta.dart';

/// Compares two values by their index in a sort map.
/// Items in the map come before items not in it.
/// Items not in the map maintain stable relative ordering (returns 0).
int compareByIndex<K>(Map<K, int> sortIndex, K a, K b) {
  final indexA = sortIndex[a];
  final indexB = sortIndex[b];
  if (indexA == null && indexB == null) return 0;
  if (indexA == null) return 1;
  if (indexB == null) return -1;
  return indexA.compareTo(indexB);
}

@immutable
class Registries {
  Registries({
    required this.items,
    required this.drops,
    required this.equipmentSlots,
    required this.woodcutting,
    required this.mining,
    required this.firemaking,
    required this.fishing,
    required this.cooking,
    required this.smithing,
    required this.fletching,
    required this.crafting,
    required this.herblore,
    required this.runecrafting,
    required this.thieving,
    required this.agility,
    required this.farming,
    required this.summoning,
    required this.astrology,
    required this.altMagic,
    required this.combat,
    required this.shop,
    required this.masteryBonuses,
    required this.masteryUnlocks,
    required this.masteryPoolBonuses,
    required this.summoningSynergies,
    required this.township,
    required this.modifierMetadata,
    required this.itemUpgrades,
    required this.slayer,
    required Map<MelvorId, int> bankSortIndex,
  }) : _bankSortIndex = bankSortIndex,
       _testActions = null;

  factory Registries.test({
    List<Item> items = const [],
    List<Action> actions = const [],
    ShopRegistry? shop,
    MasteryBonusRegistry? masteryBonuses,
    MasteryUnlockRegistry? masteryUnlocks,
    MasteryPoolBonusRegistry? masteryPoolBonuses,
    SummoningSynergyRegistry? summoningSynergies,
    TownshipRegistry? township,
    AgilityRegistry? agility,
    AstrologyRegistry? astrology,
    SlayerRegistry? slayer,
    CombatRegistry? combat,
    Map<MelvorId, int>? bankSortIndex,
  }) {
    // For tests, we store actions in a separate list that overrides
    // the allActions getter. This allows tests to use generic SkillAction
    // instances without needing skill-specific subclasses.
    return Registries._test(
      items: ItemRegistry(items),
      drops: DropsRegistry(
        {},
        miningGems: const Drop(MelvorId('test:Gem'), rate: 0),
      ),
      equipmentSlots: const EquipmentSlotRegistry.empty(),
      shop: shop ?? ShopRegistry(const [], const []),
      masteryBonuses: masteryBonuses ?? MasteryBonusRegistry([]),
      masteryUnlocks: masteryUnlocks ?? MasteryUnlockRegistry(const []),
      masteryPoolBonuses:
          masteryPoolBonuses ?? MasteryPoolBonusRegistry(const []),
      summoningSynergies:
          summoningSynergies ?? const SummoningSynergyRegistry([]),
      township: township ?? const TownshipRegistry.empty(),
      agility:
          agility ??
          AgilityRegistry(
            obstacles: const [],
            courses: const [],
            pillars: const [],
          ),
      astrology: astrology ?? const AstrologyRegistry([]),
      modifierMetadata: const ModifierMetadataRegistry.empty(),
      slayer:
          slayer ??
          SlayerRegistry(
            taskCategories: SlayerTaskCategoryRegistry(const []),
            areas: SlayerAreaRegistry(const []),
          ),
      bankSortIndex: bankSortIndex ?? {},
      testActions: actions,
      combat: combat,
    );
  }

  /// Internal constructor for test fixtures that stores actions directly.
  Registries._test({
    required this.items,
    required this.drops,
    required this.equipmentSlots,
    required this.shop,
    required this.masteryBonuses,
    required this.masteryUnlocks,
    required this.masteryPoolBonuses,
    required this.summoningSynergies,
    required this.township,
    required this.agility,
    required this.astrology,
    required this.modifierMetadata,
    required this.slayer,
    required Map<MelvorId, int> bankSortIndex,
    required List<Action> testActions,
    CombatRegistry? combat,
  }) : _bankSortIndex = bankSortIndex,
       _testActions = testActions,
       woodcutting = const WoodcuttingRegistry([]),
       mining = const MiningRegistry([]),
       firemaking = const FiremakingRegistry([]),
       fishing = FishingRegistry(actions: const [], areas: const []),
       cooking = CookingRegistry(actions: const [], categories: const []),
       smithing = SmithingRegistry(actions: const [], categories: const []),
       fletching = FletchingRegistry(actions: const [], categories: const []),
       crafting = CraftingRegistry(actions: const [], categories: const []),
       herblore = HerbloreRegistry(actions: const [], categories: const []),
       runecrafting = RunecraftingRegistry(
         actions: const [],
         categories: const [],
       ),
       thieving = ThievingRegistry(actions: const [], areas: const []),
       farming = FarmingRegistry(
         crops: const [],
         categories: const [],
         plots: const [],
       ),
       summoning = SummoningRegistry(const []),
       altMagic = const AltMagicRegistry([]),
       itemUpgrades = ItemUpgradeRegistry.empty,
       combat =
           combat ??
           CombatRegistry(
             monsters: const [],
             areas: CombatAreaRegistry(const []),
             dungeons: DungeonRegistry(const []),
           );

  final ItemRegistry items;
  final DropsRegistry drops;
  final EquipmentSlotRegistry equipmentSlots;
  final ShopRegistry shop;
  final MasteryBonusRegistry masteryBonuses;
  final MasteryUnlockRegistry masteryUnlocks;
  final MasteryPoolBonusRegistry masteryPoolBonuses;
  final SummoningSynergyRegistry summoningSynergies;
  final TownshipRegistry township;
  final ModifierMetadataRegistry modifierMetadata;
  final ItemUpgradeRegistry itemUpgrades;
  final SlayerRegistry slayer;
  final Map<MelvorId, int> _bankSortIndex;

  // Skill registries
  final WoodcuttingRegistry woodcutting;
  final MiningRegistry mining;
  final FiremakingRegistry firemaking;
  final FishingRegistry fishing;
  final CookingRegistry cooking;
  final SmithingRegistry smithing;
  final FletchingRegistry fletching;
  final CraftingRegistry crafting;
  final HerbloreRegistry herblore;
  final RunecraftingRegistry runecrafting;
  final ThievingRegistry thieving;
  final AgilityRegistry agility;
  final FarmingRegistry farming;
  final SummoningRegistry summoning;
  final AstrologyRegistry astrology;
  final AltMagicRegistry altMagic;
  final CombatRegistry combat;

  // Convenience getters that delegate to specialized registries.
  List<FishingArea> get fishingAreas => fishing.areas;
  List<FarmingCrop> get farmingCrops => farming.crops;
  List<FarmingCategory> get farmingCategories => farming.categories;
  List<FarmingPlot> get farmingPlots => farming.plots;
  CombatAreaRegistry get combatAreas => combat.areas;
  DungeonRegistry get dungeons => combat.dungeons;

  // For test fixtures: stores generic actions directly instead of using
  // specialized registries. Null for production registries.
  final List<Action>? _testActions;

  /// Returns all actions across all skill registries.
  /// For test fixtures, returns the directly-stored test actions instead.
  late final List<Action> allActions =
      _testActions ??
      [
        ...woodcutting.actions,
        ...mining.actions,
        ...firemaking.actions,
        ...fishing.actions,
        ...cooking.actions,
        ...smithing.actions,
        ...fletching.actions,
        ...crafting.actions,
        ...herblore.actions,
        ...runecrafting.actions,
        ...thieving.actions,
        ...agility.obstacles,
        ...farming.crops,
        ...summoning.actions,
        ...astrology.actions,
        ...altMagic.actions,
        ...combat.monsters,
      ];

  /// Map from ActionId to Action for quick lookup.
  late final Map<ActionId, Action> _actionById = {
    for (final action in allActions) action.id: action,
  };

  /// Returns an action by its ActionId.
  ///
  /// Throws StateError if the action is not found.
  Action actionById(ActionId id) {
    final action = _actionById[id];
    if (action == null) {
      throw StateError('Missing action with id: $id');
    }
    return action;
  }

  /// Returns all skill actions for a given skill.
  List<SkillAction> actionsForSkill(Skill skill) {
    return allActions
        .whereType<SkillAction>()
        .where((action) => action.skill == skill)
        .toList();
  }

  /// Comparator for sorting items according to bank sort order.
  int compareBankItems(Item a, Item b) =>
      compareByIndex(_bankSortIndex, a.id, b.id);
}

/// Ensures the registries are initialized.
///
/// This should be called during app startup or in setUpAll() for tests.
/// It's safe to call multiple times; subsequent calls are no-ops.
Future<Registries> loadRegistries({Directory? cacheDir}) async {
  final cache = Cache(cacheDir: cacheDir ?? defaultCacheDir);
  try {
    return await loadRegistriesFromCache(cache);
  } finally {
    cache.close();
  }
}

/// Loads registries from an existing cache instance.
///
/// Use this when you have a Cache instance that you want to reuse
/// (e.g., for both loading registries and caching images).
Future<Registries> loadRegistriesFromCache(Cache cache) async {
  final melvorData = await MelvorData.loadFromCache(cache);
  return melvorData.toRegistries();
}
