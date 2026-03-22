import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item potionI;
  late Item potionII;
  late Item potionIII;
  late Item potionIV;
  late HerbloreAction herbloreAction;

  setUpAll(() async {
    await loadTestRegistries();
    potionI = testItems.byName('Bird Nest Potion I');
    potionII = testItems.byName('Bird Nest Potion II');
    potionIII = testItems.byName('Bird Nest Potion III');
    potionIV = testItems.byName('Bird Nest Potion IV');

    final recipeId = testRegistries.herblore.recipeIdForPotionItem(potionI.id)!;
    herbloreAction = testRegistries.herblore.byId(recipeId)!;
  });

  group('HerbloreAction.tierIndexForMasteryLevel', () {
    test('returns tier 0 for mastery levels 1-19', () {
      expect(HerbloreAction.tierIndexForMasteryLevel(1), 0);
      expect(HerbloreAction.tierIndexForMasteryLevel(10), 0);
      expect(HerbloreAction.tierIndexForMasteryLevel(19), 0);
    });

    test('returns tier 1 for mastery levels 20-49', () {
      expect(HerbloreAction.tierIndexForMasteryLevel(20), 1);
      expect(HerbloreAction.tierIndexForMasteryLevel(35), 1);
      expect(HerbloreAction.tierIndexForMasteryLevel(49), 1);
    });

    test('returns tier 2 for mastery levels 50-89', () {
      expect(HerbloreAction.tierIndexForMasteryLevel(50), 2);
      expect(HerbloreAction.tierIndexForMasteryLevel(70), 2);
      expect(HerbloreAction.tierIndexForMasteryLevel(89), 2);
    });

    test('returns tier 3 for mastery levels 90+', () {
      expect(HerbloreAction.tierIndexForMasteryLevel(90), 3);
      expect(HerbloreAction.tierIndexForMasteryLevel(99), 3);
    });
  });

  group('HerbloreAction.productIdForMasteryLevel', () {
    test('returns tier I potion at low mastery', () {
      expect(herbloreAction.productIdForMasteryLevel(1), potionI.id);
    });

    test('returns tier II potion at mastery 20', () {
      expect(herbloreAction.productIdForMasteryLevel(20), potionII.id);
    });

    test('returns tier III potion at mastery 50', () {
      expect(herbloreAction.productIdForMasteryLevel(50), potionIII.id);
    });

    test('returns tier IV potion at mastery 90', () {
      expect(herbloreAction.productIdForMasteryLevel(90), potionIV.id);
    });
  });

  group('Herblore production uses mastery tier', () {
    /// Creates a state with the given mastery level for the herblore action
    /// and enough inputs to brew.
    GlobalState stateWithMastery(int masteryLevel) {
      // Get the inputs needed for the recipe
      final inputs = herbloreAction.inputs;
      final inventoryItems = <ItemStack>[
        for (final entry in inputs.entries)
          ItemStack(testItems.byId(entry.key), count: entry.value * 10),
      ];

      return GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, inventoryItems),
        actionStates: {
          herbloreAction.id: ActionState(
            masteryXp: startXpForLevel(masteryLevel),
          ),
        },
        skillStates: {
          Skill.herblore: SkillState(xp: startXpForLevel(99), masteryPoolXp: 0),
        },
      );
    }

    test('produces tier I potion at mastery level 1', () {
      final state = stateWithMastery(1);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, herbloreAction, random: random);
      final newState = builder.build();

      expect(newState.inventory.countOfItem(potionI), greaterThan(0));
      expect(newState.inventory.countOfItem(potionII), 0);
    });

    test('produces tier II potion at mastery level 20', () {
      final state = stateWithMastery(20);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, herbloreAction, random: random);
      final newState = builder.build();

      expect(newState.inventory.countOfItem(potionI), 0);
      expect(newState.inventory.countOfItem(potionII), greaterThan(0));
    });

    test('produces tier III potion at mastery level 50', () {
      final state = stateWithMastery(50);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, herbloreAction, random: random);
      final newState = builder.build();

      expect(newState.inventory.countOfItem(potionIII), greaterThan(0));
    });

    test('produces tier IV potion at mastery level 90', () {
      final state = stateWithMastery(90);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, herbloreAction, random: random);
      final newState = builder.build();

      expect(newState.inventory.countOfItem(potionIV), greaterThan(0));
    });

    test('action does not stop when tier changes mid-crafting', () {
      // Start at mastery 19 (tier I). We simulate enough XP to cross
      // the tier II threshold at mastery 20 while the action continues.
      //
      // The key assertion: completeAction returns true (canRepeat) even
      // though the product changes.
      final state = stateWithMastery(19);
      final random = Random(42);

      // First completion at tier I
      final builder1 = StateUpdateBuilder(state);
      final canRepeat1 = completeAction(
        builder1,
        herbloreAction,
        random: random,
      );
      expect(canRepeat1, isTrue, reason: 'should be able to repeat at tier I');

      // Now simulate mastery level crossing to 20 (tier II)
      final stateAtTier2 = stateWithMastery(20);
      final builder2 = StateUpdateBuilder(stateAtTier2);
      final canRepeat2 = completeAction(
        builder2,
        herbloreAction,
        random: Random(42),
      );
      expect(
        canRepeat2,
        isTrue,
        reason: 'action should continue when tier changes',
      );

      // Verify it now produces tier II
      final newState = builder2.build();
      expect(newState.inventory.countOfItem(potionII), greaterThan(0));
    });

    test('produces correct tier across multiple completions', () {
      // Verify the same action can produce different tiers at different
      // mastery levels without needing to restart the action.
      final random1 = Random(42);
      final random2 = Random(42);

      // Complete at mastery 19 → tier I
      final state1 = stateWithMastery(19);
      final builder1 = StateUpdateBuilder(state1);
      completeAction(builder1, herbloreAction, random: random1);
      expect(builder1.build().inventory.countOfItem(potionI), greaterThan(0));

      // Complete at mastery 20 → tier II (same action, different mastery)
      final state2 = stateWithMastery(20);
      final builder2 = StateUpdateBuilder(state2);
      completeAction(builder2, herbloreAction, random: random2);
      expect(builder2.build().inventory.countOfItem(potionII), greaterThan(0));
    });
  });
}
