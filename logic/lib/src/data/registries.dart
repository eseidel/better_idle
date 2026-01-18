import 'dart:io';

import 'package:logic/src/data/action_id.dart';
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
    this._woodcuttingActions,
    this._miningActions,
    this._firemakingActions,
    this._fishingActions,
    this._cookingActions,
    this._smithingActions,
    this._fletchingActions,
    this._craftingActions,
    this._herbloreActions,
    this._runecraftingActions,
    this._thievingActions,
    this._agilityObstacles,
    this._summoningActions,
    this._astrologyActions,
    this._altMagicActions,
    this._combatActions,
  ) : _testActions = null;

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
    // For tests, we store actions in a separate list that overrides
    // the allActions getter. This allows tests to use generic SkillAction
    // instances without needing skill-specific subclasses.
    return Registries._test(
      ItemRegistry(items),
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
      actions,
    );
  }

  /// Internal constructor for test fixtures that stores actions directly.
  Registries._test(
    this.items,
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
    this._testActions,
  ) : _woodcuttingActions = const [],
      _miningActions = const [],
      _firemakingActions = const [],
      _fishingActions = const [],
      _cookingActions = const [],
      _smithingActions = const [],
      _fletchingActions = const [],
      _craftingActions = const [],
      _herbloreActions = const [],
      _runecraftingActions = const [],
      _thievingActions = const [],
      _agilityObstacles = const [],
      _summoningActions = const [],
      _astrologyActions = const [],
      _altMagicActions = const [],
      _combatActions = const [];

  final ItemRegistry items;
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

  // Action lists passed from constructor (used to build specialized registries)
  final List<WoodcuttingTree> _woodcuttingActions;
  final List<MiningAction> _miningActions;
  final List<FiremakingAction> _firemakingActions;
  final List<FishingAction> _fishingActions;
  final List<CookingAction> _cookingActions;
  final List<SmithingAction> _smithingActions;
  final List<FletchingAction> _fletchingActions;
  final List<CraftingAction> _craftingActions;
  final List<HerbloreAction> _herbloreActions;
  final List<RunecraftingAction> _runecraftingActions;
  final List<ThievingAction> _thievingActions;
  final List<AgilityObstacle> _agilityObstacles;
  final List<SummoningAction> _summoningActions;
  final List<AstrologyAction> _astrologyActions;
  final List<AltMagicAction> _altMagicActions;
  final List<CombatAction> _combatActions;

  // For test fixtures: stores generic actions directly instead of using
  // specialized registries. Null for production registries.
  final List<Action>? _testActions;

  /// Woodcutting skill registry.
  late final WoodcuttingRegistry woodcutting = WoodcuttingRegistry(
    _woodcuttingActions,
  ).withCache();

  /// Mining skill registry.
  late final MiningRegistry mining = MiningRegistry(_miningActions).withCache();

  /// Firemaking skill registry.
  late final FiremakingRegistry firemaking = FiremakingRegistry(
    _firemakingActions,
  ).withCache();

  /// Combat registry (monsters, areas, dungeons).
  late final CombatRegistry combat = CombatRegistry(
    monsters: _combatActions,
    areas: combatAreas,
    dungeons: dungeons,
  );

  /// Fishing skill registry.
  late final FishingRegistry fishing = FishingRegistry(
    actions: _fishingActions,
    areas: fishingAreas,
  );

  /// Cooking skill registry.
  late final CookingRegistry cooking = CookingRegistry(
    actions: _cookingActions,
    categories: cookingCategories,
  );

  /// Smithing skill registry.
  late final SmithingRegistry smithing = SmithingRegistry(
    actions: _smithingActions,
    categories: smithingCategories,
  );

  /// Fletching skill registry.
  late final FletchingRegistry fletching = FletchingRegistry(
    actions: _fletchingActions,
    categories: fletchingCategories,
  );

  /// Crafting skill registry.
  late final CraftingRegistry crafting = CraftingRegistry(
    actions: _craftingActions,
    categories: craftingCategories,
  );

  /// Herblore skill registry.
  late final HerbloreRegistry herblore = HerbloreRegistry(
    actions: _herbloreActions,
    categories: herbloreCategories,
  );

  /// Runecrafting skill registry.
  late final RunecraftingRegistry runecrafting = RunecraftingRegistry(
    actions: _runecraftingActions,
    categories: runecraftingCategories,
  );

  /// Thieving skill registry.
  late final ThievingRegistry thieving = ThievingRegistry(
    actions: _thievingActions,
    areas: thievingAreas,
  );

  /// Agility skill registry.
  late final AgilityRegistry agility = AgilityRegistry(
    obstacles: _agilityObstacles,
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
  late final SummoningRegistry summoning = SummoningRegistry(_summoningActions);

  /// Astrology skill registry.
  late final AstrologyRegistry astrology = AstrologyRegistry(
    _astrologyActions,
  ).withCache();

  /// Alt Magic skill registry.
  late final AltMagicRegistry altMagic = AltMagicRegistry(
    _altMagicActions,
  ).withCache();

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

  // Test helper methods for looking up actions by name.
  // These are used in tests to avoid needing to construct ActionIds.

  Action _bySkillAndName(Skill skill, String name) {
    final matches = allActions.where(
      (action) => action.id.skillId == skill.id && action.name == name,
    );
    if (matches.isEmpty) {
      final available = allActions
          .where((a) => a.id.skillId == skill.id)
          .map((a) => a.name)
          .join(', ');
      throw StateError(
        'Missing action with skill: $skill and name: $name. '
        'Available: $available',
      );
    }
    return matches.first;
  }

  @visibleForTesting
  SkillAction woodcuttingAction(String name) =>
      _bySkillAndName(Skill.woodcutting, name) as SkillAction;

  @visibleForTesting
  MiningAction miningAction(String name) =>
      _bySkillAndName(Skill.mining, name) as MiningAction;

  @visibleForTesting
  SkillAction firemakingAction(String name) =>
      _bySkillAndName(Skill.firemaking, name) as SkillAction;

  @visibleForTesting
  SkillAction fishingAction(String name) =>
      _bySkillAndName(Skill.fishing, name) as SkillAction;

  @visibleForTesting
  CombatAction combatAction(String name) =>
      _bySkillAndName(Skill.combat, name) as CombatAction;

  @visibleForTesting
  ThievingAction thievingAction(String name) =>
      _bySkillAndName(Skill.thieving, name) as ThievingAction;

  @visibleForTesting
  SkillAction smithingAction(String name) =>
      _bySkillAndName(Skill.smithing, name) as SkillAction;
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
    melvorData.woodcuttingActions,
    melvorData.miningActions,
    melvorData.firemakingActions,
    melvorData.fishingActions,
    melvorData.cookingActions,
    melvorData.smithingActions,
    melvorData.fletchingActions,
    melvorData.craftingActions,
    melvorData.herbloreActions,
    melvorData.runecraftingActions,
    melvorData.thievingActions,
    melvorData.agilityObstacles,
    melvorData.summoningActions,
    melvorData.astrologyActions,
    melvorData.altMagicActions,
    melvorData.combatActions,
  );
}
