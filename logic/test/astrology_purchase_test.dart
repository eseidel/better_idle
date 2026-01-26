import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  // IDs for stardust and golden stardust
  const stardustId = MelvorId('melvorF:Stardust');
  const goldenStardustId = MelvorId('melvorF:Golden_Stardust');

  late Item stardust;
  late Item goldenStardust;
  late AstrologyAction constellation;

  setUpAll(() async {
    await loadTestRegistries();
    stardust = testItems.byId(stardustId);
    goldenStardust = testItems.byId(goldenStardustId);
    // Get a real constellation from the registry
    constellation = testRegistries.astrology.actions.first;
  });

  group('canPurchaseAstrologyModifier', () {
    test('returns true when has enough currency and meets requirements', () {
      // Find a standard modifier that requires low mastery level
      final modifier = constellation.standardModifiers.first;
      final cost = modifier.costs[0];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: cost),
        ]),
        // Set mastery level high enough to unlock the modifier
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      expect(
        state.canPurchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        isTrue,
      );
    });

    test('returns false when constellation not found', () {
      const invalidId = MelvorId('test:NonExistent');
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: 1000),
        ]),
      );

      expect(
        state.canPurchaseAstrologyModifier(
          constellationId: invalidId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        isFalse,
      );
    });

    test('returns false when modifier index is invalid', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: 1000),
        ]),
      );

      expect(
        state.canPurchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 999, // Invalid index
        ),
        isFalse,
      );
    });

    test('returns false when already at max level', () {
      final modifier = constellation.standardModifiers.first;

      // Give enough currency
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: 10000),
        ]),
        astrology: AstrologyState(
          constellationStates: {
            constellation.id.localId: ConstellationModifierState(
              standardLevels: [modifier.maxCount], // Already maxed
            ),
          },
        ),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      expect(
        state.canPurchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        isFalse,
      );
    });

    test('returns false when mastery level requirement not met', () {
      // Find a modifier that requires higher mastery level
      final modifiers = constellation.standardModifiers;
      AstrologyModifier? highMasteryModifier;
      var modifierIndex = 0;
      for (var i = 0; i < modifiers.length; i++) {
        if (modifiers[i].unlockMasteryLevel > 1) {
          highMasteryModifier = modifiers[i];
          modifierIndex = i;
          break;
        }
      }

      if (highMasteryModifier == null) {
        // All modifiers unlock at level 1, skip this test
        return;
      }

      final cost = highMasteryModifier.costs[0];
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: cost),
        ]),
        // Mastery level 1, but modifier requires higher
        actionStates: {constellation.id: const ActionState(masteryXp: 0)},
      );

      expect(
        state.canPurchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: modifierIndex,
        ),
        isFalse,
      );
    });

    test('returns false when not enough stardust', () {
      final modifier = constellation.standardModifiers.first;
      final cost = modifier.costs[0];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: cost - 1), // Not enough
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      expect(
        state.canPurchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        isFalse,
      );
    });

    test('returns false when not enough golden stardust for unique', () {
      if (constellation.uniqueModifiers.isEmpty) {
        // No unique modifiers to test
        return;
      }

      final modifier = constellation.uniqueModifiers.first;
      final cost = modifier.costs[0];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(goldenStardust, count: cost - 1), // Not enough
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      expect(
        state.canPurchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.unique,
          modifierIndex: 0,
        ),
        isFalse,
      );
    });

    test('checks correct currency type for each modifier type', () {
      final standardModifier = constellation.standardModifiers.first;
      final standardCost = standardModifier.costs[0];

      // Has stardust but not golden stardust
      final stateWithStardust = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: standardCost),
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(standardModifier.unlockMasteryLevel),
          ),
        },
      );

      // Should be able to buy standard modifier
      expect(
        stateWithStardust.canPurchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        isTrue,
      );

      // Should NOT be able to buy unique modifier (no golden stardust)
      if (constellation.uniqueModifiers.isNotEmpty) {
        expect(
          stateWithStardust.canPurchaseAstrologyModifier(
            constellationId: constellation.id.localId,
            modifierType: AstrologyModifierType.unique,
            modifierIndex: 0,
          ),
          isFalse,
        );
      }
    });
  });

  group('purchaseAstrologyModifier', () {
    test('successfully purchases standard modifier and deducts stardust', () {
      final modifier = constellation.standardModifiers.first;
      final cost = modifier.costs[0];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: cost + 100),
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      final newState = state.purchaseAstrologyModifier(
        constellationId: constellation.id.localId,
        modifierType: AstrologyModifierType.standard,
        modifierIndex: 0,
      );

      // Stardust should be deducted
      expect(newState.inventory.countOfItem(stardust), 100);

      // Modifier level should be incremented
      final modState = newState.astrology.stateFor(constellation.id.localId);
      expect(modState.levelFor(AstrologyModifierType.standard, 0), 1);
    });

    test('successfully purchases unique modifier and deducts golden', () {
      if (constellation.uniqueModifiers.isEmpty) {
        return;
      }

      final modifier = constellation.uniqueModifiers.first;
      final cost = modifier.costs[0];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(goldenStardust, count: cost + 50),
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      final newState = state.purchaseAstrologyModifier(
        constellationId: constellation.id.localId,
        modifierType: AstrologyModifierType.unique,
        modifierIndex: 0,
      );

      // Golden stardust should be deducted
      expect(newState.inventory.countOfItem(goldenStardust), 50);

      // Modifier level should be incremented
      final modState = newState.astrology.stateFor(constellation.id.localId);
      expect(modState.levelFor(AstrologyModifierType.unique, 0), 1);
    });

    test('increments modifier level correctly on multiple purchases', () {
      final modifier = constellation.standardModifiers.first;
      // Total cost for 3 levels
      final totalCost =
          modifier.costs[0] + modifier.costs[1] + modifier.costs[2];

      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: totalCost),
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      // Purchase 3 times
      for (var i = 0; i < 3; i++) {
        state = state.purchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        );
      }

      // Modifier level should be 3
      final modState = state.astrology.stateFor(constellation.id.localId);
      expect(modState.levelFor(AstrologyModifierType.standard, 0), 3);

      // All stardust should be consumed
      expect(state.inventory.countOfItem(stardust), 0);
    });

    test('throws when constellation not found', () {
      const invalidId = MelvorId('test:NonExistent');
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: 1000),
        ]),
      );

      expect(
        () => state.purchaseAstrologyModifier(
          constellationId: invalidId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        throwsStateError,
      );
    });

    test('throws when modifier index is invalid', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: 1000),
        ]),
      );

      expect(
        () => state.purchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 999,
        ),
        throwsStateError,
      );
    });

    test('throws when already at max level', () {
      final modifier = constellation.standardModifiers.first;

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: 10000),
        ]),
        astrology: AstrologyState(
          constellationStates: {
            constellation.id.localId: ConstellationModifierState(
              standardLevels: [modifier.maxCount],
            ),
          },
        ),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      expect(
        () => state.purchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        throwsStateError,
      );
    });

    test('throws when not enough currency', () {
      final modifier = constellation.standardModifiers.first;
      final cost = modifier.costs[0];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: cost - 1),
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      expect(
        () => state.purchaseAstrologyModifier(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
        throwsStateError,
      );
    });

    test('cost increases with level', () {
      final modifier = constellation.standardModifiers.first;
      final firstCost = modifier.costs[0];
      final secondCost = modifier.costs[1];

      // Start with no levels purchased
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: firstCost + secondCost),
        ]),
        actionStates: {
          constellation.id: ActionState(
            masteryXp: startXpForLevel(modifier.unlockMasteryLevel),
          ),
        },
      );

      // First purchase costs firstCost
      state = state.purchaseAstrologyModifier(
        constellationId: constellation.id.localId,
        modifierType: AstrologyModifierType.standard,
        modifierIndex: 0,
      );
      expect(state.inventory.countOfItem(stardust), secondCost);

      // Second purchase costs secondCost
      state = state.purchaseAstrologyModifier(
        constellationId: constellation.id.localId,
        modifierType: AstrologyModifierType.standard,
        modifierIndex: 0,
      );
      expect(state.inventory.countOfItem(stardust), 0);
    });

    test('preserves other constellation states when purchasing', () {
      // Get two different constellations
      final constellations = testRegistries.astrology.actions;
      if (constellations.length < 2) {
        return;
      }

      final constellation1 = constellations[0];
      final constellation2 = constellations[1];
      final modifier1 = constellation1.standardModifiers.first;

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(stardust, count: 10000),
        ]),
        astrology: AstrologyState(
          constellationStates: {
            // Pre-existing state for constellation2
            constellation2.id.localId: const ConstellationModifierState(
              standardLevels: [2, 1],
            ),
          },
        ),
        actionStates: {
          constellation1.id: ActionState(
            masteryXp: startXpForLevel(modifier1.unlockMasteryLevel),
          ),
        },
      );

      final newState = state.purchaseAstrologyModifier(
        constellationId: constellation1.id.localId,
        modifierType: AstrologyModifierType.standard,
        modifierIndex: 0,
      );

      // constellation1 should have new purchase
      final mod1State = newState.astrology.stateFor(constellation1.id.localId);
      expect(mod1State.levelFor(AstrologyModifierType.standard, 0), 1);

      // constellation2 should be unchanged
      final mod2State = newState.astrology.stateFor(constellation2.id.localId);
      expect(mod2State.levelFor(AstrologyModifierType.standard, 0), 2);
      expect(mod2State.levelFor(AstrologyModifierType.standard, 1), 1);
    });
  });
}
