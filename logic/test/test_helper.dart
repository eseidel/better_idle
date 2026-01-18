import 'package:logic/logic.dart';

/// Standard registries for tests. Must call [loadTestRegistries] first.
late Registries testRegistries;

/// A stub ModifierProvider for testing that returns values from a Map.
/// Use this when you need to test code that takes a ModifierProvider
/// but don't need the full modifier resolution logic.
class StubModifierProvider with ModifierAccessors {
  StubModifierProvider([this.values = const {}]);

  /// Modifier values by name. Access is not scope-aware.
  final Map<String, num> values;

  @override
  num getModifier(
    String name, {
    MelvorId? skillId,
    MelvorId? actionId,
    MelvorId? itemId,
    MelvorId? categoryId,
  }) {
    return values[name] ?? 0;
  }
}

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
DropsRegistry get testDrops => testRegistries.drops;
EquipmentSlotRegistry get testSlots => testRegistries.equipmentSlots;
List<FishingArea> get testFishingAreas => testRegistries.fishingAreas;
MasteryBonusRegistry get testMasteryBonuses => testRegistries.masteryBonuses;

/// Get the index of an equipment slot in the enum. Used for death penalty tests
/// that need to mock a specific slot being rolled.
int slotIndex(EquipmentSlot slot) => EquipmentSlot.values.indexOf(slot);
