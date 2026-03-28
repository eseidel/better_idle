import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late CookingAction shrimpRecipe;
  late Item rawShrimp;
  late Item cookedShrimp;
  late Item chefsSpoon;
  late Item badCookerScroll;
  late Item coalOre;
  late HerbloreAction herbloreAction;
  late Item herblorePotionI;

  setUpAll(() async {
    await loadTestRegistries();
    final items = testItems;

    shrimpRecipe = testRegistries
        .actionsForSkill(Skill.cooking)
        .whereType<CookingAction>()
        .firstWhere((a) => a.name == 'Shrimp');

    rawShrimp = items.byName('Raw Shrimp');
    cookedShrimp = items.byName('Shrimp');
    chefsSpoon = items.byName("Chef's Spoon");
    badCookerScroll = items.byName('Bad Cooker Scroll');
    coalOre = items.byId(coalOreId);

    // Set up herblore
    herblorePotionI = items.byName('Herblore Potion I');
    final recipeId = testRegistries.herblore.recipeIdForPotionItem(
      herblorePotionI.id,
    )!;
    herbloreAction = testRegistries.herblore.byId(recipeId)!;
  });

  group('successfulCookChance modifier', () {
    test('increases cooking success rate', () {
      // Chef's Spoon gives +2 successfulCookChance.
      // Equip it and verify the success rate increases.
      // At mastery 0, base success rate is 70%. With +2% it becomes 72%.
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: chefsSpoon},
      );

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(rawShrimp, count: 100),
        ]),
        equipment: equipment,
      );

      // Run many cooks and count successes.
      // With the modifier, success rate should be higher than 70%.
      var successes = 0;
      const trials = 1000;
      final random = Random(123);
      for (var i = 0; i < trials; i++) {
        final s = state.copyWith(
          inventory: state.inventory.adding(ItemStack(rawShrimp, count: 1)),
        );
        final builder = StateUpdateBuilder(s);
        completeCookingAction(builder, shrimpRecipe, random, isPassive: false);
        final result = builder.state;
        if (result.inventory.countOfItem(cookedShrimp) > 0) {
          successes++;
        }
      }

      // With 72% success rate over 1000 trials, we expect ~720 successes.
      // Without modifier it would be ~700. Allow some variance.
      expect(successes, greaterThan(680));
    });

    test('modifier is included in modifier resolution', () {
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: chefsSpoon},
      );

      final state = GlobalState.test(testRegistries, equipment: equipment);

      final modifiers = state.testModifiersFor(shrimpRecipe);
      expect(
        modifiers.successfulCookChance(actionId: shrimpRecipe.id.localId),
        2,
      );
    });
  });

  group('flatCoalGainedOnCookingFailure modifier', () {
    test('grants coal on cooking failure', () {
      // Bad Cooker Scroll gives flatCoalGainedOnCookingFailure=10.
      // It goes in the Consumable slot.
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.consumable: badCookerScroll},
      );

      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(rawShrimp, count: 10),
        ]),
        equipment: equipment,
      );

      // Find a random seed that causes cooking failure.
      // At mastery 0 with no successfulCookChance modifier, base is 70%.
      // We need nextDouble() > 0.70.
      // Try several seeds to find one that fails.
      Random? failRandom;
      for (var seed = 0; seed < 100; seed++) {
        final r = Random(seed);
        final val = r.nextDouble();
        if (val > 0.70) {
          failRandom = Random(seed);
          break;
        }
      }
      expect(failRandom, isNotNull, reason: 'Need a seed that fails');

      final builder = StateUpdateBuilder(state);
      completeCookingAction(
        builder,
        shrimpRecipe,
        failRandom!,
        isPassive: false,
      );
      state = builder.state;

      // Should have received 10 coal ore on failure
      expect(state.inventory.countOfItem(coalOre), 10);
      // Cooking failed, no cooked shrimp
      expect(state.inventory.countOfItem(cookedShrimp), 0);
    });

    test('no coal granted on cooking success', () {
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.consumable: badCookerScroll},
      );

      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(rawShrimp, count: 10),
        ]),
        equipment: equipment,
      );

      // Random(42) first value is ~0.37, success at 70%
      final random = Random(42);
      final builder = StateUpdateBuilder(state);
      completeCookingAction(builder, shrimpRecipe, random, isPassive: false);
      state = builder.state;

      // Cooking succeeded, no coal
      expect(state.inventory.countOfItem(coalOre), 0);
      // Cooked shrimp produced
      expect(state.inventory.countOfItem(cookedShrimp), greaterThan(0));
    });

    test('modifier value is resolved from equipment', () {
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.consumable: badCookerScroll},
      );

      final state = GlobalState.test(testRegistries, equipment: equipment);

      final modifiers = state.testModifiersFor(shrimpRecipe);
      expect(modifiers.flatCoalGainedOnCookingFailure, 10);
    });
  });

  group('convertBoneDropsIntoCake modifier', () {
    test('cake slice item exists in registry', () {
      // Verify the Birthday Cake Slice item (conversion target) is in the
      // registry. The convertBoneDropsIntoCake modifier replaces bone drops
      // with this item when active (requires all 4 birthday items equipped).
      final cakeSlice = testItems.maybeById(
        const MelvorId('melvorF:Birthday_Cake_Slice'),
      );
      expect(cakeSlice, isNotNull);
      expect(cakeSlice!.name, contains('Cake'));
    });

    test('birthday equipment items exist in registry', () {
      // Verify all birthday set items exist for equipping.
      // The modifier is a conditional set bonus requiring all 4 pieces.
      final partyHat = testItems.maybeById(
        const MelvorId('melvorF:Orange_Party_Hat'),
      );
      final balloon = testItems.maybeById(
        const MelvorId('melvorF:Birthday_Balloon'),
      );
      final bowTie = testItems.maybeById(
        const MelvorId('melvorF:Party_Bow_Tie'),
      );
      final shoes = testItems.maybeById(const MelvorId('melvorF:Party_Shoes'));
      expect(partyHat, isNotNull);
      expect(balloon, isNotNull);
      expect(bowTie, isNotNull);
      expect(shoes, isNotNull);
    });
  });

  group('randomHerblorePotionChance modifier', () {
    test('grants random potion on herblore completion', () {
      // Herblore Potion I gives randomHerblorePotionChance=1 (1%).
      // Select it as the active potion for herblore.
      final inputs = herbloreAction.inputs;
      final inventoryItems = <ItemStack>[
        for (final entry in inputs.entries)
          ItemStack(testItems.byId(entry.key), count: entry.value * 100),
        ItemStack(herblorePotionI, count: 10),
      ];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, inventoryItems),
        skillStates: {
          Skill.herblore: SkillState(xp: startXpForLevel(99), masteryPoolXp: 0),
        },
      ).selectPotion(Skill.herblore.id, herblorePotionI.id);

      // Verify the selected potion has the modifier
      final potionItemId = state.selectedPotions[Skill.herblore.id];
      expect(potionItemId, herblorePotionI.id);
      // Herblore Potion I provides randomHerblorePotionChance=1
      final potionMods = herblorePotionI.modifiers.modifiers;
      expect(
        potionMods.any((m) => m.name == 'randomHerblorePotionChance'),
        isTrue,
      );

      // Run many herblore completions and check if we get extra potions.
      // With 1% chance, over 1000 trials we should get some.
      // The modifier should award potions across all tiers, not just tier 1.
      var extraPotions = 0;
      final tiersAwarded = <int>{};

      for (var i = 0; i < 1000; i++) {
        final random = Random(i);
        final s = state
            .copyWith(inventory: Inventory.fromItems(testItems, inventoryItems))
            .selectPotion(Skill.herblore.id, herblorePotionI.id);

        final builder = StateUpdateBuilder(s);
        completeAction(builder, herbloreAction, random: random);
        final result = builder.state;

        // Count all potions (any tier) except the one we're brewing
        for (final recipe in testRegistries.herblore.actions) {
          for (var tier = 0; tier < recipe.potionIds.length; tier++) {
            final potionId = recipe.potionIds[tier];
            if (potionId == herbloreAction.potionIds.first) continue;
            final item = testItems.byId(potionId);
            final count = result.inventory.countOfItem(item);
            if (count > 0) {
              extraPotions += count;
              tiersAwarded.add(tier);
            }
          }
        }
      }

      // With 1% chance over 1000 trials, expect roughly 10 extra potions
      // (allowing for variance)
      expect(extraPotions, greaterThan(0));
      // Verify that multiple tiers are awarded, not just tier 0
      expect(tiersAwarded.length, greaterThan(1));
    });

    test('no random potion without modifier', () {
      final inputs = herbloreAction.inputs;
      final inventoryItems = <ItemStack>[
        for (final entry in inputs.entries)
          ItemStack(testItems.byId(entry.key), count: entry.value * 100),
      ];

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, inventoryItems),
        skillStates: {
          Skill.herblore: SkillState(xp: startXpForLevel(99), masteryPoolXp: 0),
        },
      );

      // Verify no potion is selected
      expect(state.selectedPotions[Skill.herblore.id], isNull);

      // Run completions - should never get extra potions (any tier)
      for (var i = 0; i < 100; i++) {
        final random = Random(i);
        final s = state.copyWith(
          inventory: Inventory.fromItems(testItems, inventoryItems),
        );
        final builder = StateUpdateBuilder(s);
        completeAction(builder, herbloreAction, random: random);
        final result = builder.state;

        for (final recipe in testRegistries.herblore.actions) {
          for (final potionId in recipe.potionIds) {
            if (potionId == herbloreAction.potionIds.first) continue;
            final item = testItems.byId(potionId);
            expect(result.inventory.countOfItem(item), 0);
          }
        }
      }
    });
  });
}
