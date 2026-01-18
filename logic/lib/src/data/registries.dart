import 'dart:io';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/cache.dart';
import 'package:logic/src/data/melvor_data.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/data/summoning_synergy.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/mastery.dart';
import 'package:logic/src/types/mastery_unlock.dart';
import 'package:meta/meta.dart';

@immutable
class Registries {
  Registries(
    this.items,
    this.actions,
    this.drops,
    this.equipmentSlots,
    this._cookingCategories,
    this._fishingAreas,
    this._smithingCategories,
    this._fletchingCategories,
    this._craftingCategories,
    this._herbloreCategories,
    this._runecraftingCategories,
    this._thievingAreas,
    this.combatAreas,
    this.dungeons,
    this._agilityCourses,
    this._agilityPillars,
    this._farmingCrops,
    this._farmingCategories,
    this._farmingPlots,
    this.shop,
    this.masteryBonuses,
    this.masteryUnlocks,
    this.summoningSynergies,
    this.township,
    this._bankSortIndex,
  );

  factory Registries.test({
    List<Item> items = const [],
    List<Action> actions = const [],
    ShopRegistry? shop,
    MasteryBonusRegistry? masteryBonuses,
    MasteryUnlockRegistry? masteryUnlocks,
    SummoningSynergyRegistry? summoningSynergies,
    TownshipRegistry? township,
    Map<MelvorId, int>? bankSortIndex,
  }) {
    return Registries(
      ItemRegistry(items),
      ActionRegistry(actions),
      DropsRegistry({}),
      const EquipmentSlotRegistry.empty(),
      const <CookingCategory>[],
      const [],
      const <SmithingCategory>[],
      const <FletchingCategory>[],
      const <CraftingCategory>[],
      const <HerbloreCategory>[],
      const <RunecraftingCategory>[],
      const [],
      CombatAreaRegistry(const []),
      DungeonRegistry(const []),
      const [],
      const [],
      const <FarmingCrop>[],
      const <FarmingCategory>[],
      const <FarmingPlot>[],
      shop ?? ShopRegistry(const [], const []),
      masteryBonuses ?? MasteryBonusRegistry([]),
      masteryUnlocks ?? MasteryUnlockRegistry(const []),
      summoningSynergies ?? const SummoningSynergyRegistry([]),
      township ?? const TownshipRegistry.empty(),
      bankSortIndex ?? {},
    );
  }

  final ItemRegistry items;
  final ActionRegistry actions;
  final DropsRegistry drops;
  final EquipmentSlotRegistry equipmentSlots;
  final List<CookingCategory> _cookingCategories;
  final List<FishingArea> _fishingAreas;
  final List<SmithingCategory> _smithingCategories;

  /// Returns all smithing categories.
  List<SmithingCategory> get smithingCategories => _smithingCategories;

  /// Returns all cooking categories.
  List<CookingCategory> get cookingCategories => _cookingCategories;

  /// Returns all fishing areas.
  List<FishingArea> get fishingAreas => _fishingAreas;
  final List<FletchingCategory> _fletchingCategories;
  final List<CraftingCategory> _craftingCategories;
  final List<HerbloreCategory> _herbloreCategories;
  final List<RunecraftingCategory> _runecraftingCategories;
  final List<ThievingArea> _thievingAreas;

  /// Returns all fletching categories.
  List<FletchingCategory> get fletchingCategories => _fletchingCategories;

  /// Returns all crafting categories.
  List<CraftingCategory> get craftingCategories => _craftingCategories;

  /// Returns all herblore categories.
  List<HerbloreCategory> get herbloreCategories => _herbloreCategories;

  /// Returns all runecrafting categories.
  List<RunecraftingCategory> get runecraftingCategories =>
      _runecraftingCategories;
  final CombatAreaRegistry combatAreas;

  /// Returns all thieving areas.
  List<ThievingArea> get thievingAreas => _thievingAreas;
  final DungeonRegistry dungeons;
  final List<AgilityCourse> _agilityCourses;
  final List<AgilityPillar> _agilityPillars;
  final List<FarmingCrop> _farmingCrops;
  final List<FarmingCategory> _farmingCategories;
  final List<FarmingPlot> _farmingPlots;

  /// Returns all agility courses.
  List<AgilityCourse> get agilityCourses => _agilityCourses;

  /// Returns all agility pillars.
  List<AgilityPillar> get agilityPillars => _agilityPillars;

  /// Returns all farming crops.
  List<FarmingCrop> get farmingCrops => _farmingCrops;

  /// Returns all farming categories.
  List<FarmingCategory> get farmingCategories => _farmingCategories;

  /// Returns all farming plots.
  List<FarmingPlot> get farmingPlots => _farmingPlots;
  final ShopRegistry shop;
  final MasteryBonusRegistry masteryBonuses;
  final MasteryUnlockRegistry masteryUnlocks;
  final SummoningSynergyRegistry summoningSynergies;
  final TownshipRegistry township;
  final Map<MelvorId, int> _bankSortIndex;

  /// Woodcutting skill registry.
  late final WoodcuttingRegistry woodcutting = WoodcuttingRegistry(
    actions.forSkill(Skill.woodcutting).cast<WoodcuttingTree>().toList(),
  ).withCache();

  /// Mining skill registry.
  late final MiningRegistry mining = MiningRegistry(
    actions.forSkill(Skill.mining).cast<MiningAction>().toList(),
  ).withCache();

  /// Firemaking skill registry.
  late final FiremakingRegistry firemaking = FiremakingRegistry(
    actions.forSkill(Skill.firemaking).cast<FiremakingAction>().toList(),
  ).withCache();

  /// Combat registry (monsters, areas, dungeons).
  late final CombatRegistry combat = CombatRegistry(
    monsters: actions.all.whereType<CombatAction>().toList(),
    areas: combatAreas,
    dungeons: dungeons,
  );

  /// Fishing skill registry.
  late final FishingRegistry fishing = FishingRegistry(
    actions: actions.forSkill(Skill.fishing).cast<FishingAction>().toList(),
    areas: fishingAreas,
  );

  /// Cooking skill registry.
  late final CookingRegistry cooking = CookingRegistry(
    actions: actions.forSkill(Skill.cooking).cast<CookingAction>().toList(),
    categories: cookingCategories,
  );

  /// Smithing skill registry.
  late final SmithingRegistry smithing = SmithingRegistry(
    actions: actions.forSkill(Skill.smithing).cast<SmithingAction>().toList(),
    categories: smithingCategories,
  );

  /// Fletching skill registry.
  late final FletchingRegistry fletching = FletchingRegistry(
    actions: actions.forSkill(Skill.fletching).cast<FletchingAction>().toList(),
    categories: fletchingCategories,
  );

  /// Crafting skill registry.
  late final CraftingRegistry crafting = CraftingRegistry(
    actions: actions.forSkill(Skill.crafting).cast<CraftingAction>().toList(),
    categories: craftingCategories,
  );

  /// Herblore skill registry.
  late final HerbloreRegistry herblore = HerbloreRegistry(
    actions: actions.forSkill(Skill.herblore).cast<HerbloreAction>().toList(),
    categories: herbloreCategories,
  );

  /// Runecrafting skill registry.
  late final RunecraftingRegistry runecrafting = RunecraftingRegistry(
    actions: actions
        .forSkill(Skill.runecrafting)
        .cast<RunecraftingAction>()
        .toList(),
    categories: runecraftingCategories,
  );

  /// Thieving skill registry.
  late final ThievingRegistry thieving = ThievingRegistry(
    actions: actions.forSkill(Skill.thieving).cast<ThievingAction>().toList(),
    areas: thievingAreas,
  );

  /// Agility skill registry.
  late final AgilityRegistry agility = AgilityRegistry(
    obstacles: actions.forSkill(Skill.agility).cast<AgilityObstacle>().toList(),
    courses: agilityCourses,
    pillars: agilityPillars,
  );

  /// Farming skill registry.
  late final FarmingRegistry farming = FarmingRegistry(
    crops: farmingCrops,
    categories: farmingCategories,
    plots: farmingPlots,
  );

  /// Summoning skill registry.
  late final SummoningRegistry summoning = SummoningRegistry(
    actions.forSkill(Skill.summoning).cast<SummoningAction>().toList(),
  );

  /// Returns all skill actions for a given skill.
  ///
  /// This method provides a unified way to get actions for any skill.
  /// Uses the global action registry for now to support test fixtures
  /// that may use generic SkillAction instances rather than skill-specific
  /// subclasses like WoodcuttingTree.
  List<SkillAction> actionsForSkill(Skill skill) {
    return actions.forSkill(skill).toList();
  }

  /// Comparator for sorting items according to bank sort order.
  /// Items in sort order come before items not in sort order.
  /// Items not in sort order maintain stable relative ordering.
  int compareBankItems(Item a, Item b) {
    final indexA = _bankSortIndex[a.id];
    final indexB = _bankSortIndex[b.id];

    // Both not in sort order - maintain original order (return 0)
    if (indexA == null && indexB == null) return 0;
    // Items in sort order come before items not in sort order
    if (indexA == null) return 1;
    if (indexB == null) return -1;

    return indexA.compareTo(indexB);
  }
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
  return Registries(
    melvorData.items,
    melvorData.actions,
    melvorData.drops,
    melvorData.equipmentSlots,
    melvorData.cookingCategories,
    melvorData.fishingAreas,
    melvorData.smithingCategories,
    melvorData.fletchingCategories,
    melvorData.craftingCategories,
    melvorData.herbloreCategories,
    melvorData.runecraftingCategories,
    melvorData.thievingAreas,
    melvorData.combatAreas,
    melvorData.dungeons,
    melvorData.agilityCourses,
    melvorData.agilityPillars,
    melvorData.farmingCrops,
    melvorData.farmingCategories,
    melvorData.farmingPlots,
    melvorData.shop,
    melvorData.masteryBonuses,
    melvorData.masteryUnlocks,
    melvorData.summoningSynergies,
    melvorData.township,
    melvorData.bankSortIndex,
  );
}
