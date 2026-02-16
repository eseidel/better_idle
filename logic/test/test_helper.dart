import 'package:logic/logic.dart';
import 'package:logic/src/data/registries_io.dart';

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

/// Extension providing convenience methods for looking up actions by name.
/// These avoid needing to construct ActionIds in tests.
extension RegistriesTestHelpers on Registries {
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

  SkillAction woodcuttingAction(String name) =>
      _bySkillAndName(Skill.woodcutting, name) as SkillAction;

  MiningAction miningAction(String name) =>
      _bySkillAndName(Skill.mining, name) as MiningAction;

  SkillAction firemakingAction(String name) =>
      _bySkillAndName(Skill.firemaking, name) as SkillAction;

  SkillAction fishingAction(String name) =>
      _bySkillAndName(Skill.fishing, name) as SkillAction;

  CombatAction combatAction(String name) =>
      _bySkillAndName(Skill.combat, name) as CombatAction;

  ThievingAction thievingAction(String name) =>
      _bySkillAndName(Skill.thieving, name) as ThievingAction;

  SkillAction smithingAction(String name) =>
      _bySkillAndName(Skill.smithing, name) as SkillAction;

  AgilityObstacle agilityObstacle(String name) =>
      _bySkillAndName(Skill.agility, name) as AgilityObstacle;
}

/// Extension providing a short helper for the common test pattern of
/// creating a ModifierProvider with no condition context or consumesOn.
extension GlobalStateTestHelpers on GlobalState {
  /// Creates a ModifierProvider for [action] with empty condition context
  /// and no consumesOn type (synergies won't activate).
  ModifierProvider testModifiersFor(SkillAction action) =>
      createActionModifierProvider(
        action,
        conditionContext: ConditionContext.empty,
        consumesOnType: null,
      );
}
