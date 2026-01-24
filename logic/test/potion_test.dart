import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item birdNestPotionI;
  late Item birdNestPotionII;
  late Item normalLogs;
  late Action normalTree;

  setUpAll(() async {
    await loadTestRegistries();
    birdNestPotionI = testItems.byName('Bird Nest Potion I');
    birdNestPotionII = testItems.byName('Bird Nest Potion II');
    normalLogs = testItems.byName('Normal Logs');
    normalTree = testRegistries.woodcuttingAction('Normal Tree');
  });

  group('Item potion properties', () {
    test('potion items have correct properties', () {
      expect(birdNestPotionI.isPotion, isTrue);
      expect(birdNestPotionI.potionCharges, isNotNull);
      expect(birdNestPotionI.potionCharges, greaterThan(0));
      expect(birdNestPotionI.potionTier, 0); // Tier I = 0
      expect(birdNestPotionI.potionAction, Skill.woodcutting.id);
    });

    test('higher tier potions have correct tier values', () {
      // Tier I = 0, Tier II = 1
      expect(birdNestPotionI.potionTier, 0);
      expect(birdNestPotionII.potionTier, 1);
      // Note: Tiers I-III often have the same charges, IV has more
      expect(birdNestPotionII.potionCharges, isNotNull);
    });

    test('non-potion items have null potion properties', () {
      expect(normalLogs.isPotion, isFalse);
      expect(normalLogs.potionCharges, isNull);
      expect(normalLogs.potionTier, isNull);
      expect(normalLogs.potionAction, isNull);
    });
  });

  group('Potion selection state', () {
    test('selectPotion adds potion to selectedPotions', () {
      final state = GlobalState.test(testRegistries);
      final newState = state.selectPotion(
        Skill.woodcutting.id,
        birdNestPotionI.id,
      );

      expect(
        newState.selectedPotions[Skill.woodcutting.id],
        birdNestPotionI.id,
      );
    });

    test('clearSelectedPotion removes potion from selectedPotions', () {
      final state = GlobalState.test(
        testRegistries,
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);
      expect(state.selectedPotions[Skill.woodcutting.id], isNotNull);

      final newState = state.clearSelectedPotion(Skill.woodcutting.id);
      expect(newState.selectedPotions[Skill.woodcutting.id], isNull);
    });

    test('selectedPotionForSkill returns correct potion', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 1),
        ]),
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      final potion = state.selectedPotionForSkill(Skill.woodcutting.id);
      expect(potion, birdNestPotionI);
    });

    test('selectedPotionForSkill returns null when no potion selected', () {
      final state = GlobalState.test(testRegistries);
      final potion = state.selectedPotionForSkill(Skill.woodcutting.id);
      expect(potion, isNull);
    });
  });

  group('Potion uses remaining', () {
    test('potionUsesRemaining counts inventory correctly', () {
      final charges = birdNestPotionI.potionCharges!;
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 2),
        ]),
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      expect(state.potionUsesRemaining(Skill.woodcutting.id), charges * 2);
    });

    test('potionUsesRemaining accounts for used charges', () {
      final charges = birdNestPotionI.potionCharges!;
      // Set selectedPotions directly to avoid selectPotion resetting charges
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 2),
        ]),
        selectedPotions: {Skill.woodcutting.id: birdNestPotionI.id},
        potionChargesUsed: {Skill.woodcutting.id: 5},
      );

      // 2 potions * charges - 5 used
      expect(state.potionUsesRemaining(Skill.woodcutting.id), charges * 2 - 5);
    });

    test('potionUsesRemaining returns 0 when no potion selected', () {
      final state = GlobalState.test(testRegistries);
      expect(state.potionUsesRemaining(Skill.woodcutting.id), 0);
    });
  });

  group('Potion state serialization', () {
    test('selectedPotions round-trips through JSON', () {
      final state = GlobalState.test(
        testRegistries,
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      final json = state.toJson();
      final loaded = GlobalState.fromJson(testRegistries, json);

      expect(loaded.selectedPotions[Skill.woodcutting.id], birdNestPotionI.id);
    });

    test('potionChargesUsed round-trips through JSON', () {
      final state = GlobalState.test(
        testRegistries,
        potionChargesUsed: {Skill.woodcutting.id: 10},
      );

      final json = state.toJson();
      final loaded = GlobalState.fromJson(testRegistries, json);

      expect(loaded.potionChargesUsed[Skill.woodcutting.id], 10);
    });
  });

  group('Potion charge consumption', () {
    test('consumePotionCharge increments charges used', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 2),
        ]),
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      final random = Random(42);
      final builder = StateUpdateBuilder(state)
        ..consumePotionCharge(normalTree as SkillAction, random);
      final newState = builder.build();

      expect(newState.potionChargesUsed[Skill.woodcutting.id], 1);
    });

    test(
      'consumePotionCharge consumes from inventory when charges depleted',
      () {
        final charges = birdNestPotionI.potionCharges!;
        // Set selectedPotions directly to avoid selectPotion resetting charges
        final state = GlobalState.test(
          testRegistries,
          inventory: Inventory.fromItems(testItems, [
            ItemStack(birdNestPotionI, count: 2),
          ]),
          selectedPotions: {Skill.woodcutting.id: birdNestPotionI.id},
          potionChargesUsed: {Skill.woodcutting.id: charges - 1},
        );

        final random = Random(42);
        final builder = StateUpdateBuilder(state)
          ..consumePotionCharge(normalTree as SkillAction, random);
        final newState = builder.build();

        // One potion consumed, charges reset
        expect(newState.inventory.countOfItem(birdNestPotionI), 1);
        expect(newState.potionChargesUsed[Skill.woodcutting.id], isNull);
      },
    );

    test('consumePotionCharge clears selection when last potion consumed', () {
      final charges = birdNestPotionI.potionCharges!;
      // Set selectedPotions directly to avoid selectPotion resetting charges
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 1),
        ]),
        selectedPotions: {Skill.woodcutting.id: birdNestPotionI.id},
        potionChargesUsed: {Skill.woodcutting.id: charges - 1},
      );

      final random = Random(42);
      final builder = StateUpdateBuilder(state)
        ..consumePotionCharge(normalTree as SkillAction, random);
      final newState = builder.build();

      // Last potion consumed, selection cleared
      expect(newState.inventory.countOfItem(birdNestPotionI), 0);
      expect(newState.selectedPotions[Skill.woodcutting.id], isNull);
    });

    test('consumePotionCharge does nothing when no potion selected', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 2),
        ]),
      );

      final random = Random(42);
      final builder = StateUpdateBuilder(state)
        ..consumePotionCharge(normalTree as SkillAction, random);
      final newState = builder.build();

      // Nothing changed
      expect(newState.inventory.countOfItem(birdNestPotionI), 2);
      expect(newState.potionChargesUsed[Skill.woodcutting.id], isNull);
    });
  });

  group('Potion modifiers', () {
    test('potion items have modifiers', () {
      // Bird Nest Potion should have modifiers defined
      expect(birdNestPotionI.modifiers.modifiers, isNotEmpty);
    });

    test('bird nest potion provides randomProductChance modifier', () {
      // Verify the potion has the expected modifier
      final modifiers = birdNestPotionI.modifiers.modifiers;
      expect(modifiers.length, 1);
      expect(modifiers.first.name, 'randomProductChance');
      // Tier I gives +5% random product chance
      expect(modifiers.first.entries.first.value, 5);
    });

    test('resolveSkillModifiers includes potion randomProductChance', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 1),
        ]),
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      final action = normalTree as SkillAction;
      final modifiers = state.createActionModifierProvider(
        action,
        conditionContext: ConditionContext.empty,
      );
      // Bird Nest Potion I gives +5% randomProductChance for bird nest item
      expect(
        modifiers.randomProductChance(
          skillId: action.skill.id,
          itemId: const MelvorId('melvorD:Bird_Nest'),
        ),
        5,
      );
    });

    test('createModifierProvider works with potion selected', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 1),
        ]),
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      // Should not throw when resolving modifiers with potion
      final action = normalTree as SkillAction;
      final modifiers = state.createActionModifierProvider(
        action,
        conditionContext: ConditionContext.empty,
      );
      expect(modifiers, isNotNull);
    });

    test('createModifierProvider works when no potions in inventory', () {
      final state = GlobalState.test(
        testRegistries,
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      // No potions in inventory
      expect(state.inventory.countOfItem(birdNestPotionI), 0);

      // Modifiers should still resolve without error
      final action = normalTree as SkillAction;
      final modifiers = state.createActionModifierProvider(
        action,
        conditionContext: ConditionContext.empty,
      );
      expect(modifiers, isNotNull);
    });
  });

  group('Bird nest potion effect on drops', () {
    late Item birdNest;

    setUpAll(() {
      birdNest = testItems.byName('Bird Nest');
    });

    test('bird nest potion increases bird nest drop rate', () {
      // This test verifies that the randomProductChance modifier from
      // bird nest potion actually increases the bird nest drop rate.
      //
      // Base bird nest drop rate is 0.5% (0.005).
      // With Bird Nest Potion I (+5% randomProductChance), the effective
      // rate should be higher.

      // Create state with potion selected
      final stateWithPotion = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 10),
        ]),
      ).selectPotion(Skill.woodcutting.id, birdNestPotionI.id);

      // Create state without potion
      final stateWithoutPotion = GlobalState.test(testRegistries);

      // Use a seeded random for reproducibility
      const iterations = 10000;
      var nestsWithPotion = 0;
      var nestsWithoutPotion = 0;

      // Simulate woodcutting actions and count bird nests
      for (var i = 0; i < iterations; i++) {
        final random = Random(i);

        // With potion
        final builderWith = StateUpdateBuilder(stateWithPotion);
        final modifiersWith = stateWithPotion.createActionModifierProvider(
          normalTree as SkillAction,
          conditionContext: ConditionContext.empty,
        );
        rollAndCollectDrops(
          builderWith,
          normalTree as SkillAction,
          modifiersWith,
          random,
          const NoSelectedRecipe(),
        );
        nestsWithPotion += builderWith.state.inventory.countOfItem(birdNest);

        // Without potion (use same seed for fair comparison)
        final randomWithout = Random(i);
        final builderWithout = StateUpdateBuilder(stateWithoutPotion);
        final modifiersWithout = stateWithoutPotion
            .createActionModifierProvider(
              normalTree as SkillAction,
              conditionContext: ConditionContext.empty,
            );
        rollAndCollectDrops(
          builderWithout,
          normalTree as SkillAction,
          modifiersWithout,
          randomWithout,
          const NoSelectedRecipe(),
        );
        nestsWithoutPotion += builderWithout.state.inventory.countOfItem(
          birdNest,
        );
      }

      // With potion, we expect more bird nests due to randomProductChance
      // The potion gives +5% bonus, so:
      // - Without potion: ~0.5% chance = ~50 nests per 10000 actions
      // - With potion: effective rate should be higher
      //
      // If randomProductChance is working correctly, nestsWithPotion should
      // be noticeably higher than nestsWithoutPotion.
      expect(
        nestsWithPotion,
        greaterThan(nestsWithoutPotion),
        reason:
            'Bird nest potion should increase bird nest drops, but got '
            '$nestsWithPotion with potion vs $nestsWithoutPotion without',
      );
    });
  });
}
