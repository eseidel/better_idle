import 'dart:io';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/cache.dart';
import 'package:logic/src/data/melvor_data.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/types/mastery.dart';
import 'package:logic/src/types/mastery_unlock.dart';

class Registries {
  Registries(
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
    this.agilityCourses,
    this.agilityPillars,
    this.farmingCrops,
    this.farmingCategories,
    this.farmingPlots,
    this.shop,
    this.masteryBonuses,
    this.masteryUnlocks,
  );

  static Registries test({
    ShopRegistry? shop,
    MasteryBonusRegistry? masteryBonuses,
    MasteryUnlockRegistry? masteryUnlocks,
  }) {
    return Registries(
      ItemRegistry([]),
      ActionRegistry([]),
      DropsRegistry({}),
      FishingAreaRegistry([]),
      SmithingCategoryRegistry([]),
      FletchingCategoryRegistry([]),
      CraftingCategoryRegistry([]),
      HerbloreCategoryRegistry([]),
      RunecraftingCategoryRegistry([]),
      ThievingAreaRegistry([]),
      CombatAreaRegistry([]),
      AgilityCourseRegistry([]),
      AgilityPillarRegistry([]),
      FarmingCropRegistry([]),
      FarmingCategoryRegistry([]),
      FarmingPlotRegistry([]),
      shop ?? ShopRegistry([], []),
      masteryBonuses ?? MasteryBonusRegistry([]),
      masteryUnlocks ?? MasteryUnlockRegistry([]),
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
  final AgilityCourseRegistry agilityCourses;
  final AgilityPillarRegistry agilityPillars;
  final FarmingCropRegistry farmingCrops;
  final FarmingCategoryRegistry farmingCategories;
  final FarmingPlotRegistry farmingPlots;
  final ShopRegistry shop;
  final MasteryBonusRegistry masteryBonuses;
  final MasteryUnlockRegistry masteryUnlocks;
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
    melvorData.agilityCourses,
    melvorData.agilityPillars,
    melvorData.farmingCrops,
    melvorData.farmingCategories,
    melvorData.farmingPlots,
    melvorData.shop,
    melvorData.masteryBonuses,
    melvorData.masteryUnlocks,
  );
}
