import 'dart:io';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/cache.dart';
import 'package:logic/src/data/melvor_data.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/types/mastery.dart';
import 'package:logic/src/types/mastery_unlock.dart';
import 'package:meta/meta.dart';

@immutable
class Registries {
  const Registries(
    this.items,
    this.actions,
    this.drops,
    this.fishingAreas,
    this.smithingCategories,
    this.fletchingCategories,
    this.craftingCategories,
    this.herbloreCategories,
    this.runecraftingCategories,
    this.thievingAreas,
    this.combatAreas,
    this.dungeons,
    this.agilityCourses,
    this.agilityPillars,
    this.farmingCrops,
    this.farmingCategories,
    this.farmingPlots,
    this.shop,
    this.masteryBonuses,
    this.masteryUnlocks,
    this._bankSortIndex,
  );

  factory Registries.test({
    List<Item> items = const [],
    List<Action> actions = const [],
    ShopRegistry? shop,
    MasteryBonusRegistry? masteryBonuses,
    MasteryUnlockRegistry? masteryUnlocks,
    Map<MelvorId, int>? bankSortIndex,
  }) {
    return Registries(
      ItemRegistry(items),
      ActionRegistry(actions),
      DropsRegistry({}),
      FishingAreaRegistry(const []),
      SmithingCategoryRegistry(const []),
      FletchingCategoryRegistry(const []),
      CraftingCategoryRegistry(const []),
      HerbloreCategoryRegistry(const []),
      RunecraftingCategoryRegistry(const []),
      const ThievingAreaRegistry([]),
      CombatAreaRegistry(const []),
      DungeonRegistry(const []),
      AgilityCourseRegistry([]),
      AgilityPillarRegistry([]),
      FarmingCropRegistry([]),
      FarmingCategoryRegistry(const []),
      FarmingPlotRegistry([]),
      shop ?? ShopRegistry(const [], const []),
      masteryBonuses ?? MasteryBonusRegistry([]),
      masteryUnlocks ?? MasteryUnlockRegistry(const []),
      bankSortIndex ?? {},
    );
  }

  final ItemRegistry items;
  final ActionRegistry actions;
  final DropsRegistry drops;
  final FishingAreaRegistry fishingAreas;
  final SmithingCategoryRegistry smithingCategories;
  final FletchingCategoryRegistry fletchingCategories;
  final CraftingCategoryRegistry craftingCategories;
  final HerbloreCategoryRegistry herbloreCategories;
  final RunecraftingCategoryRegistry runecraftingCategories;
  final ThievingAreaRegistry thievingAreas;
  final CombatAreaRegistry combatAreas;
  final DungeonRegistry dungeons;
  final AgilityCourseRegistry agilityCourses;
  final AgilityPillarRegistry agilityPillars;
  final FarmingCropRegistry farmingCrops;
  final FarmingCategoryRegistry farmingCategories;
  final FarmingPlotRegistry farmingPlots;
  final ShopRegistry shop;
  final MasteryBonusRegistry masteryBonuses;
  final MasteryUnlockRegistry masteryUnlocks;
  final Map<MelvorId, int> _bankSortIndex;

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
    DropsRegistry(skillDrops),
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
    melvorData.bankSortIndex,
  );
}
