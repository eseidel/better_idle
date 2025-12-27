import 'package:logic/logic.dart';

/// Standard registries for tests. Must call [loadTestRegistries] first.
late Registries testRegistries;

/// Creates a test compost item with the given compost value and optional
/// harvest bonus. Use this when tests need to create PlotState with compost.
Item testCompost({required int compostValue, int harvestBonus = 0}) {
  return Item.test(
    'Test Compost $compostValue',
    gp: 100,
    compostValue: compostValue,
    harvestBonus: harvestBonus,
  );
}

/// Loads the test registries. Call this in setUpAll().
Future<void> loadTestRegistries() async {
  testRegistries = await loadRegistries();
}

/// Shorthand accessors for test registries.
ItemRegistry get testItems => testRegistries.items;
ActionRegistry get testActions => testRegistries.actions;
DropsRegistry get testDrops => testRegistries.drops;
FishingAreaRegistry get testFishingAreas => testRegistries.fishingAreas;
MasteryBonusRegistry get testMasteryBonuses => testRegistries.masteryBonuses;
