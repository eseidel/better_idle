import 'dart:io';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_data.dart';

class Registries {
  Registries(
    this.items,
    this.actions,
    this.drops,
    this.fishingAreas,
    this.smithingCategories,
    this.fletchingCategories,
    this.thievingAreas,
    this.combatAreas,
  );

  final ItemRegistry items;
  final ActionRegistry actions;
  final DropsRegistry drops;
  final FishingAreaRegistry fishingAreas;
  final SmithingCategoryRegistry smithingCategories;
  final FletchingCategoryRegistry fletchingCategories;
  final ThievingAreaRegistry thievingAreas;
  final CombatAreaRegistry combatAreas;
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
    DropsRegistry(skillDrops, globalDrops),
    melvorData.fishingAreas,
    melvorData.smithingCategories,
    melvorData.fletchingCategories,
    melvorData.thievingAreas,
    melvorData.combatAreas,
  );
}
