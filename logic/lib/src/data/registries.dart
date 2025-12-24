import 'dart:io';

import 'package:logic/src/data/actions.dart';
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
    this.thievingAreas,
    this.combatAreas,
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
      ThievingAreaRegistry([]),
      CombatAreaRegistry([]),
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
  final ThievingAreaRegistry thievingAreas;
  final CombatAreaRegistry combatAreas;
  final ShopRegistry shop;
  final MasteryBonusRegistry masteryBonuses;
  final MasteryUnlockRegistry masteryUnlocks;
}

/// Ensures the registries are initialized.
///
/// This should be called during app startup or in setUpAll() for tests.
/// It's safe to call multiple times; subsequent calls are no-ops.
Future<Registries> loadRegistries({Directory? cacheDir}) async {
  final melvorData = await MelvorData.load(cacheDir: cacheDir);
  return Registries(
    melvorData.items,
    melvorData.actions,
    DropsRegistry(skillDrops),
    melvorData.fishingAreas,
    melvorData.smithingCategories,
    melvorData.fletchingCategories,
    melvorData.craftingCategories,
    melvorData.herbloreCategories,
    melvorData.thievingAreas,
    melvorData.combatAreas,
    melvorData.shop,
    melvorData.masteryBonuses,
    melvorData.masteryUnlocks,
  );
}
