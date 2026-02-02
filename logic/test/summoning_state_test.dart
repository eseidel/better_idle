// cspell:words succesful
import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/types/conditional_modifier.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('SummoningAction.fromJson', () {
    test('non-shard item quantity is tier * 6 for tier 1', () {
      final json = {
        'id': 'TestFamiliar',
        'level': 1,
        'productID': 'melvorF:Test_Familiar',
        'baseQuantity': 25,
        'baseExperience': 5,
        'itemCosts': [
          {'id': 'melvorF:Summoning_Shard_Green', 'quantity': 6},
        ],
        'nonShardItemCosts': ['melvorD:Normal_Logs', 'melvorD:Oak_Logs'],
        'tier': 1,
        'skillIDs': ['melvorD:Woodcutting'],
      };

      final action = SummoningAction.fromJson(json, namespace: 'melvorF');

      // Tier 1 should have non-shard quantity of 6
      expect(action.alternativeRecipes, isNotNull);
      expect(action.alternativeRecipes!.length, 2);

      // Check first alternative has correct quantity
      final firstRecipe = action.alternativeRecipes!.first;
      const logsId = MelvorId('melvorD:Normal_Logs');
      expect(firstRecipe.inputs[logsId], 6);
    });

    test('non-shard item quantity is tier * 6 for tier 2', () {
      final json = {
        'id': 'TestFamiliar2',
        'level': 45,
        'productID': 'melvorF:Test_Familiar_2',
        'baseQuantity': 25,
        'baseExperience': 25,
        'itemCosts': [
          {'id': 'melvorF:Summoning_Shard_Blue', 'quantity': 10},
        ],
        'nonShardItemCosts': ['melvorD:Mithril_Bar'],
        'tier': 2,
        'skillIDs': ['melvorD:Smithing'],
      };

      final action = SummoningAction.fromJson(json, namespace: 'melvorF');

      // Tier 2 should have non-shard quantity of 12
      expect(action.alternativeRecipes, isNotNull);
      final recipe = action.alternativeRecipes!.first;
      const barId = MelvorId('melvorD:Mithril_Bar');
      expect(recipe.inputs[barId], 12);
    });

    test('non-shard item quantity is tier * 6 for tier 3', () {
      final json = {
        'id': 'TestFamiliar3',
        'level': 85,
        'productID': 'melvorF:Test_Familiar_3',
        'baseQuantity': 25,
        'baseExperience': 50,
        'itemCosts': [
          {'id': 'melvorF:Summoning_Shard_Red', 'quantity': 14},
        ],
        'nonShardItemCosts': ['melvorD:Dragon_Bar'],
        'tier': 3,
        'skillIDs': ['melvorD:Smithing'],
      };

      final action = SummoningAction.fromJson(json, namespace: 'melvorF');

      // Tier 3 should have non-shard quantity of 18
      expect(action.alternativeRecipes, isNotNull);
      final recipe = action.alternativeRecipes!.first;
      const barId = MelvorId('melvorD:Dragon_Bar');
      expect(recipe.inputs[barId], 18);
    });

    test('default tier is 1 when not specified', () {
      final json = {
        'id': 'TestFamiliar',
        'level': 1,
        'productID': 'melvorF:Test_Familiar',
        'baseQuantity': 25,
        'baseExperience': 5,
        'itemCosts': [
          {'id': 'melvorF:Summoning_Shard_Green', 'quantity': 6},
        ],
        'nonShardItemCosts': ['melvorD:Normal_Logs'],
        // No tier specified
        'skillIDs': ['melvorD:Woodcutting'],
      };

      final action = SummoningAction.fromJson(json, namespace: 'melvorF');

      // Default tier 1 should have non-shard quantity of 6
      final recipe = action.alternativeRecipes!.first;
      const logsId = MelvorId('melvorD:Normal_Logs');
      expect(recipe.inputs[logsId], 6);
      expect(action.tier, 1);
    });
  });

  group('markLevelForCount', () {
    test('returns 0 for no marks', () {
      expect(markLevelForCount(0), 0);
    });

    test('returns 1 for 1 mark', () {
      expect(markLevelForCount(1), 1);
    });

    test('returns 1 for 5 marks', () {
      expect(markLevelForCount(5), 1);
    });

    test('returns 2 for 6 marks', () {
      expect(markLevelForCount(6), 2);
    });

    test('returns 2 for 15 marks', () {
      expect(markLevelForCount(15), 2);
    });

    test('returns 3 for 16 marks', () {
      expect(markLevelForCount(16), 3);
    });

    test('returns 4 for 31 marks', () {
      expect(markLevelForCount(31), 4);
    });

    test('returns 5 for 46 marks', () {
      expect(markLevelForCount(46), 5);
    });

    test('returns 6 for 61 marks', () {
      expect(markLevelForCount(61), 6);
    });

    test('returns 6 for marks above 61', () {
      expect(markLevelForCount(100), 6);
    });
  });

  group('SummoningState', () {
    const familiarId1 = MelvorId('melvorF:Summoning_Familiar_Ent');
    const familiarId2 = MelvorId('melvorF:Summoning_Familiar_Golbin_Thief');

    test('empty state has no marks', () {
      const state = SummoningState.empty();
      expect(state.isEmpty, true);
      expect(state.marksFor(familiarId1), 0);
      expect(state.markLevel(familiarId1), 0);
      expect(state.canCraftTablet(familiarId1), false);
    });

    test('withMarks adds marks to familiar', () {
      const state = SummoningState.empty();
      final newState = state.withMarks(familiarId1, 5);

      expect(newState.marksFor(familiarId1), 5);
      expect(newState.markLevel(familiarId1), 1);
      expect(newState.canCraftTablet(familiarId1), true);
    });

    test('withMarks accumulates marks', () {
      const state = SummoningState.empty();
      final state1 = state.withMarks(familiarId1, 5);
      final state2 = state1.withMarks(familiarId1, 10);

      expect(state2.marksFor(familiarId1), 15);
      expect(state2.markLevel(familiarId1), 2);
    });

    test('marks are tracked per familiar', () {
      const state = SummoningState.empty();
      final newState = state
          .withMarks(familiarId1, 10)
          .withMarks(familiarId2, 20);

      expect(newState.marksFor(familiarId1), 10);
      expect(newState.marksFor(familiarId2), 20);
      expect(newState.markLevel(familiarId1), 2);
      expect(newState.markLevel(familiarId2), 3);
    });

    test('withTabletCrafted marks familiar as crafted', () {
      const state = SummoningState.empty();
      final newState = state
          .withMarks(familiarId1, 1)
          .withTabletCrafted(familiarId1);

      expect(newState.hasCrafted(familiarId1), true);
      expect(newState.hasCrafted(familiarId2), false);
    });

    test('isMarkDiscoveryBlocked returns true when 1+ marks but no tablet', () {
      const state = SummoningState.empty();
      final stateWithMark = state.withMarks(familiarId1, 1);

      // Has a mark but no tablet crafted -> blocked
      expect(stateWithMark.isMarkDiscoveryBlocked(familiarId1), true);
    });

    test('isMarkDiscoveryBlocked returns false when no marks', () {
      const state = SummoningState.empty();
      expect(state.isMarkDiscoveryBlocked(familiarId1), false);
    });

    test('isMarkDiscoveryBlocked returns false after crafting tablet', () {
      const state = SummoningState.empty();
      final newState = state
          .withMarks(familiarId1, 1)
          .withTabletCrafted(familiarId1);

      expect(newState.isMarkDiscoveryBlocked(familiarId1), false);
    });

    group('JSON serialization', () {
      test('empty state round-trips correctly', () {
        const original = SummoningState.empty();
        final json = original.toJson();
        final loaded = SummoningState.fromJson(json);

        expect(loaded.isEmpty, true);
        expect(loaded.marks, isEmpty);
        expect(loaded.hasCraftedTablet, isEmpty);
      });

      test('state with marks round-trips correctly', () {
        const original = SummoningState.empty();
        final withMarks = original
            .withMarks(familiarId1, 15)
            .withMarks(familiarId2, 6);

        final json = withMarks.toJson();
        final loaded = SummoningState.fromJson(json);

        expect(loaded.marksFor(familiarId1), 15);
        expect(loaded.marksFor(familiarId2), 6);
        expect(loaded.markLevel(familiarId1), 2);
        expect(loaded.markLevel(familiarId2), 2);
      });

      test('state with crafted tablets round-trips correctly', () {
        const original = SummoningState.empty();
        final withCrafted = original
            .withMarks(familiarId1, 1)
            .withTabletCrafted(familiarId1);

        final json = withCrafted.toJson();
        final loaded = SummoningState.fromJson(json);

        expect(loaded.hasCrafted(familiarId1), true);
        expect(loaded.hasCrafted(familiarId2), false);
      });

      test('maybeFromJson returns null for null input', () {
        expect(SummoningState.maybeFromJson(null), isNull);
      });

      test('maybeFromJson parses valid input', () {
        const original = SummoningState.empty();
        final withMarks = original.withMarks(familiarId1, 10);
        final json = withMarks.toJson();

        final loaded = SummoningState.maybeFromJson(json);
        expect(loaded, isNotNull);
        expect(loaded!.marksFor(familiarId1), 10);
      });
    });

    group('copyWith', () {
      test('creates a copy with new marks', () {
        const state = SummoningState.empty();
        final stateWithMarks = state.withMarks(familiarId1, 5);

        final copied = stateWithMarks.copyWith(marks: {familiarId2: 10});

        expect(copied.marksFor(familiarId1), 0);
        expect(copied.marksFor(familiarId2), 10);
      });

      test('preserves values when not overridden', () {
        const state = SummoningState.empty();
        final stateWithData = state
            .withMarks(familiarId1, 5)
            .withTabletCrafted(familiarId1);

        final copied = stateWithData.copyWith();

        expect(copied.marksFor(familiarId1), 5);
        expect(copied.hasCrafted(familiarId1), true);
      });
    });
  });

  group('markDiscoveryChance', () {
    test('tier 1 familiar with 3 second action has expected chance', () {
      // Formula: actionTime / ((tier + 1)² × 200)
      // 3 / ((1 + 1)² × 200) = 3 / (4 × 200) = 3 / 800 = 0.00375
      final chance = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 1,
        equipmentModifier: 1,
      );
      expect(chance, closeTo(0.00375, 0.0001));
    });

    test('tier 2 familiar has lower chance than tier 1', () {
      final chanceTier1 = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 1,
        equipmentModifier: 1,
      );
      final chanceTier2 = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 2,
        equipmentModifier: 1,
      );
      expect(chanceTier2, lessThan(chanceTier1));
    });

    test('tier 3 familiar has lowest chance', () {
      final chanceTier1 = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 1,
        equipmentModifier: 1,
      );
      final chanceTier3 = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 3,
        equipmentModifier: 1,
      );
      // Tier 3: 3 / ((3 + 1)² × 200) = 3 / (16 × 200) = 3 / 3200 = 0.0009375
      expect(chanceTier3, closeTo(0.0009375, 0.0001));
      expect(chanceTier3, lessThan(chanceTier1));
    });

    test('longer actions have higher discovery chance', () {
      final chance3s = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 1,
        equipmentModifier: 1,
      );
      final chance6s = markDiscoveryChance(
        actionTimeSeconds: 6,
        tier: 1,
        equipmentModifier: 1,
      );
      expect(chance6s, closeTo(chance3s * 2, 0.0001));
    });

    test('equipment modifier increases chance', () {
      final baseChance = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 1,
        equipmentModifier: 1,
      );
      final boostedChance = markDiscoveryChance(
        actionTimeSeconds: 3,
        tier: 1,
        equipmentModifier: 2.5,
      );
      expect(boostedChance, closeTo(baseChance * 2.5, 0.0001));
    });
  });

  group('Gated tablet creation', () {
    late SummoningAction summoningAction;

    setUpAll(() async {
      await loadTestRegistries();
      // Get a summoning action from the registry
      summoningAction = testRegistries.summoning.actions.first;
    });

    test('canStartAction returns false without marks', () {
      final state = GlobalState.test(testRegistries);
      expect(state.canStartAction(summoningAction), isFalse);
    });

    test('canStartAction returns true with at least 1 mark', () {
      final summoningState = const SummoningState.empty().withMarks(
        summoningAction.productId,
        1,
      );
      // Give the player enough ingredients to craft
      final inventory = Inventory.empty(testItems);
      var inventoryWithItems = inventory;
      for (final input in summoningAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventoryWithItems = inventoryWithItems.adding(
          ItemStack(item, count: input.value * 10),
        );
      }

      final state = GlobalState.test(
        testRegistries,
        summoning: summoningState,
        inventory: inventoryWithItems,
      );
      expect(state.canStartAction(summoningAction), isTrue);
    });

    test(
      'canStartAction returns false without ingredients even with marks',
      () {
        final summoningState = const SummoningState.empty().withMarks(
          summoningAction.productId,
          1,
        );
        final state = GlobalState.test(
          testRegistries,
          summoning: summoningState,
          // Empty inventory - no ingredients
        );
        expect(state.canStartAction(summoningAction), isFalse);
      },
    );
  });

  group('Tablet Equipment', () {
    late Item tablet;
    late SummoningAction summoningAction;

    setUpAll(() async {
      await loadTestRegistries();
      // Get a summoning action and its product (tablet)
      summoningAction = testRegistries.summoning.actions.first;
      tablet = testItems.byId(summoningAction.productId);
    });

    test('isSummonTablet returns true for tablet items', () {
      expect(tablet.isSummonTablet, isTrue);
    });

    test('isSummonTablet returns false for non-tablet items', () {
      final logs = testItems.byName('Normal Logs');
      expect(logs.isSummonTablet, isFalse);
    });

    test('equipSummonTablet equips tablet with count', () {
      const equipment = Equipment.empty();

      final (newEquipment, previousStack) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        25,
      );

      expect(newEquipment.gearInSlot(EquipmentSlot.summon1), tablet);
      expect(newEquipment.summonCountInSlot(EquipmentSlot.summon1), 25);
      expect(previousStack, isNull);
    });

    test('equipSummonTablet returns previous tablet stack', () {
      const equipment = Equipment.empty();

      // Equip first tablet
      final (equippedOnce, _) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        25,
      );

      // Equip different tablet (using same for simplicity, but with diff count)
      final (equippedTwice, previousStack) = equippedOnce.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        50,
      );

      expect(previousStack, isNotNull);
      expect(previousStack!.item, tablet);
      expect(previousStack.count, 25);
      expect(equippedTwice.summonCountInSlot(EquipmentSlot.summon1), 50);
    });

    test('unequipSummonTablet returns tablet stack', () {
      const equipment = Equipment.empty();

      final (equipped, _) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        25,
      );

      final result = equipped.unequipSummonTablet(EquipmentSlot.summon1);

      expect(result, isNotNull);
      final (stack, newEquipment) = result!;
      expect(stack.item, tablet);
      expect(stack.count, 25);
      expect(newEquipment.gearInSlot(EquipmentSlot.summon1), isNull);
      expect(newEquipment.summonCountInSlot(EquipmentSlot.summon1), 0);
    });

    test('unequipSummonTablet returns null for empty slot', () {
      const equipment = Equipment.empty();

      final result = equipment.unequipSummonTablet(EquipmentSlot.summon1);

      expect(result, isNull);
    });

    test('consumeSummonCharges decrements count', () {
      const equipment = Equipment.empty();

      final (equipped, _) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        25,
      );

      final afterConsume = equipped.consumeSummonCharges(
        EquipmentSlot.summon1,
        5,
      );

      expect(afterConsume.summonCountInSlot(EquipmentSlot.summon1), 20);
      expect(afterConsume.gearInSlot(EquipmentSlot.summon1), tablet);
    });

    test('consumeSummonCharges unequips when depleted', () {
      const equipment = Equipment.empty();

      final (equipped, _) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        5,
      );

      final afterConsume = equipped.consumeSummonCharges(
        EquipmentSlot.summon1,
        5,
      );

      expect(afterConsume.gearInSlot(EquipmentSlot.summon1), isNull);
      expect(afterConsume.summonCountInSlot(EquipmentSlot.summon1), 0);
    });

    test('consumeSummonCharges unequips when over-consuming', () {
      const equipment = Equipment.empty();

      final (equipped, _) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        3,
      );

      final afterConsume = equipped.consumeSummonCharges(
        EquipmentSlot.summon1,
        10,
      );

      expect(afterConsume.gearInSlot(EquipmentSlot.summon1), isNull);
      expect(afterConsume.summonCountInSlot(EquipmentSlot.summon1), 0);
    });

    test('summon slots can have different tablets', () {
      const equipment = Equipment.empty();

      final (equipped1, _) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        25,
      );

      final (equipped2, _) = equipped1.equipSummonTablet(
        tablet,
        EquipmentSlot.summon2,
        50,
      );

      expect(equipped2.gearInSlot(EquipmentSlot.summon1), tablet);
      expect(equipped2.summonCountInSlot(EquipmentSlot.summon1), 25);
      expect(equipped2.gearInSlot(EquipmentSlot.summon2), tablet);
      expect(equipped2.summonCountInSlot(EquipmentSlot.summon2), 50);
    });

    test('equipment toJson/fromJson preserves summon counts', () {
      const equipment = Equipment.empty();

      final (equipped, _) = equipment.equipSummonTablet(
        tablet,
        EquipmentSlot.summon1,
        42,
      );

      final json = equipped.toJson();
      final loaded = Equipment.fromJson(testItems, json);

      expect(loaded.gearInSlot(EquipmentSlot.summon1), tablet);
      expect(loaded.summonCountInSlot(EquipmentSlot.summon1), 42);
    });

    test('equipSummonTablet throws for non-summon slot', () {
      const equipment = Equipment.empty();

      expect(
        () => equipment.equipSummonTablet(tablet, EquipmentSlot.weapon, 25),
        throwsArgumentError,
      );
    });

    test('isSummonSlot returns true only for summon slots', () {
      expect(EquipmentSlot.summon1.isSummonSlot, isTrue);
      expect(EquipmentSlot.summon2.isSummonSlot, isTrue);
      expect(EquipmentSlot.weapon.isSummonSlot, isFalse);
      expect(EquipmentSlot.helmet.isSummonSlot, isFalse);
    });
  });

  group('Charge Consumption', () {
    late Item entTablet; // Ent is relevant to Woodcutting
    late SkillAction woodcuttingAction;

    setUpAll(() async {
      await loadTestRegistries();
      // Get the Ent summoning tablet (relevant to Woodcutting)
      final entAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.woodcutting.id),
      );
      entTablet = testItems.byId(entAction.productId);

      // Get a woodcutting action for testing
      woodcuttingAction = testRegistries.woodcutting.actions.first;
    });

    test('skill action consumes 1 charge from equipped tablets', () {
      // Set up state with equipped tablet
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Give player enough inputs for the action
      var inventory = Inventory.empty(testItems);
      for (final input in woodcuttingAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventory = inventory.adding(ItemStack(item, count: input.value * 100));
      }

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
        inventory: inventory,
      ).startAction(woodcuttingAction, random: Random(42));

      // Run enough ticks to complete one action
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 1000, random: Random(42));
      final newState = builder.build();

      // Should have consumed at least 1 charge (could be more if multiple
      // actions completed)
      expect(
        newState.equipment.summonCountInSlot(EquipmentSlot.summon1),
        lessThan(10),
      );
    });

    test('charges deplete and tablet unequips', () {
      // Set up state with equipped tablet with only 2 charges
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        2,
      );

      // Give player enough inputs for the action
      var inventory = Inventory.empty(testItems);
      for (final input in woodcuttingAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventory = inventory.adding(ItemStack(item, count: input.value * 100));
      }

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
        inventory: inventory,
      ).startAction(woodcuttingAction, random: Random(42));

      // Run enough ticks for several actions to deplete the tablet
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 5000, random: Random(42));
      final newState = builder.build();

      // Tablet should be unequipped (0 charges)
      expect(newState.equipment.summonCountInSlot(EquipmentSlot.summon1), 0);
      expect(newState.equipment.gearInSlot(EquipmentSlot.summon1), isNull);
    });

    test('both summon slots consume charges', () {
      // Set up state with tablets in both slots
      const equipment = Equipment.empty();
      final (equipped1, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (equipped2, _) = equipped1.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon2,
        10,
      );

      // Give player enough inputs for the action
      var inventory = Inventory.empty(testItems);
      for (final input in woodcuttingAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventory = inventory.adding(ItemStack(item, count: input.value * 100));
      }

      final state = GlobalState.test(
        testRegistries,
        equipment: equipped2,
        inventory: inventory,
      ).startAction(woodcuttingAction, random: Random(42));

      // Run enough ticks to complete one action
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 1000, random: Random(42));
      final newState = builder.build();

      // Both slots should have consumed charges
      expect(
        newState.equipment.summonCountInSlot(EquipmentSlot.summon1),
        lessThan(10),
      );
      expect(
        newState.equipment.summonCountInSlot(EquipmentSlot.summon2),
        lessThan(10),
      );
    });

    test('combat action consumes charges from relevant familiar', () {
      // Get a combat familiar (Wolf - relevant to melee via Attack skill)
      final wolfAction = testRegistries.summoning.actions.firstWhere(
        (a) =>
            a.name.contains('Wolf') && a.markSkillIds.contains(Skill.attack.id),
      );
      final wolfTablet = testItems.byId(wolfAction.productId);

      // Set up state with Wolf tablet equipped
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        wolfTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Get a weak monster for combat
      final combatAction = testRegistries.combatAction('Plant');

      // Give player enough health to survive combat
      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      ).startAction(combatAction, random: Random(42));

      // Run enough ticks for player to attack (default attack speed is ~2.4s)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: Random(42));
      final newState = builder.build();

      // Wolf tablet should have consumed charges during combat
      // (charges consumed on each player attack)
      expect(
        newState.equipment.summonCountInSlot(EquipmentSlot.summon1),
        lessThan(10),
      );
    });

    test('combat action does not consume charges from irrelevant familiar', () {
      // Ent is a woodcutting familiar - not relevant to combat
      final entAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.woodcutting.id),
      );
      final entTablet = testItems.byId(entAction.productId);

      // Set up state with Ent tablet equipped
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Get a weak monster for combat
      final combatAction = testRegistries.combatAction('Plant');

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      ).startAction(combatAction, random: Random(42));

      // Run enough ticks for player to attack multiple times
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: Random(42));
      final newState = builder.build();

      // Ent tablet should NOT have consumed charges during combat
      expect(newState.equipment.summonCountInSlot(EquipmentSlot.summon1), 10);
    });

    test('irrelevant familiar does not consume charges', () {
      // Get a combat familiar (Golbin Thief - relevant to Attack/Strength/Defence)
      final combatAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.attack.id),
      );
      final combatTablet = testItems.byId(combatAction.productId);

      // Set up state with combat tablet equipped
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        combatTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Give player enough inputs for woodcutting
      var inventory = Inventory.empty(testItems);
      for (final input in woodcuttingAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventory = inventory.adding(ItemStack(item, count: input.value * 100));
      }

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
        inventory: inventory,
      ).startAction(woodcuttingAction, random: Random(42));

      // Run enough ticks to complete several actions
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 5000, random: Random(42));
      final newState = builder.build();

      // Combat tablet should NOT have consumed charges while woodcutting.
      expect(newState.equipment.summonCountInSlot(EquipmentSlot.summon1), 10);
    });
  });

  group('Familiar Modifier Bonuses', () {
    late Item
    entTablet; // Ent has additionalPrimaryProductChance for Woodcutting
    late SkillAction woodcuttingAction;

    setUpAll(() async {
      await loadTestRegistries();
      // Get the Ent summoning tablet (relevant to Woodcutting)
      final entAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.woodcutting.id),
      );
      entTablet = testItems.byId(entAction.productId);

      // Get a woodcutting action for testing
      woodcuttingAction = testRegistries.woodcutting.actions.first;
    });

    test('relevant familiar modifiers are included in skill modifiers', () {
      // Set up state with Ent tablet equipped
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      );

      // Resolve modifiers for woodcutting action
      final modifiers = state.testModifiersFor(woodcuttingAction);

      // Ent provides additionalPrimaryProductChance of 10
      expect(
        modifiers.additionalPrimaryProductChance(
          skillId: woodcuttingAction.skill.id,
        ),
        10,
      );
    });

    test('irrelevant familiar modifiers are NOT included', () {
      // Get a combat familiar (Golbin Thief - relevant to Attack/Strength/Defence)
      final combatAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.attack.id),
      );
      final combatTablet = testItems.byId(combatAction.productId);

      // Set up state with combat tablet equipped
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        combatTablet,
        EquipmentSlot.summon1,
        10,
      );

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      );

      // Resolve modifiers for woodcutting action
      final modifiers = state.testModifiersFor(woodcuttingAction);

      // Combat familiar should NOT contribute to woodcutting
      // (Golbin Thief has flatCurrencyGainOnEnemyHit, not relevant here)
      expect(
        modifiers.additionalPrimaryProductChance(
          skillId: woodcuttingAction.skill.id,
        ),
        0,
      );
    });

    test('combat familiar modifiers are included in combat modifiers', () {
      // Get a combat familiar with combat modifiers (e.g., Wolf with lifesteal)
      final wolfAction = testRegistries.summoning.actions.firstWhere(
        (a) =>
            a.name.contains('Wolf') && a.markSkillIds.contains(Skill.attack.id),
      );
      final wolfTablet = testItems.byId(wolfAction.productId);

      // Set up state with Wolf tablet equipped
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        wolfTablet,
        EquipmentSlot.summon1,
        10,
      );

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      );

      // Resolve combat modifiers
      final modifiers = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // Wolf provides lifesteal of 2
      expect(modifiers.lifesteal, 2);
    });

    test('non-combat familiar modifiers are NOT in combat modifiers', () {
      // Set up state with Ent tablet equipped (woodcutting familiar)
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      );

      // Resolve combat modifiers
      final modifiers = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // Ent's additionalPrimaryProductChance should NOT apply to combat
      expect(
        modifiers.additionalPrimaryProductChance(skillId: Skill.woodcutting.id),
        0,
      );
    });

    test('melee familiar applies when using melee attack style', () {
      // Minotaur is a melee familiar (Strength skill)
      final minotaurAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.name.contains('Minotaur'),
      );
      final minotaurTablet = testItems.byId(minotaurAction.productId);

      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        minotaurTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Default attack style is melee (stab)
      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      );

      final modifiers = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // Minotaur provides meleeMaxHit and meleeAccuracyRating
      expect(modifiers.meleeMaxHit, 3);
      expect(modifiers.meleeAccuracyRating, 3);
    });

    test('melee familiar does NOT apply when using ranged attack style', () {
      // Minotaur is a melee familiar (Strength skill)
      final minotaurAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.name.contains('Minotaur'),
      );
      final minotaurTablet = testItems.byId(minotaurAction.productId);

      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        minotaurTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Use ranged attack style
      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
        attackStyle: AttackStyle.accurate, // Ranged style
      );

      final modifiers = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // Minotaur should NOT apply to ranged combat
      expect(modifiers.meleeMaxHit, 0);
      expect(modifiers.meleeAccuracyRating, 0);
    });

    test('ranged familiar applies when using ranged attack style', () {
      // Centaur is a ranged familiar
      final centaurAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.name.contains('Centaur'),
      );
      final centaurTablet = testItems.byId(centaurAction.productId);

      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        centaurTablet,
        EquipmentSlot.summon1,
        10,
      );

      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
        attackStyle: AttackStyle.accurate, // Ranged style
      );

      final modifiers = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // Centaur provides rangedMaxHit and rangedAccuracyRating
      expect(modifiers.rangedMaxHit, 3);
      expect(modifiers.rangedAccuracyRating, 3);
    });

    test('defence familiar applies to all combat types', () {
      // Yak is a Defence familiar - applies to all combat
      final yakAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.name.contains('Yak'),
      );
      final yakTablet = testItems.byId(yakAction.productId);

      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipSummonTablet(
        yakTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Test with melee
      final meleeState = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      );
      expect(
        meleeState
            .createCombatModifierProvider(
              conditionContext: ConditionContext.empty,
            )
            .flatResistance,
        1,
      );

      // Test with ranged
      final rangedState = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
        attackStyle: AttackStyle.accurate,
      );
      expect(
        rangedState
            .createCombatModifierProvider(
              conditionContext: ConditionContext.empty,
            )
            .flatResistance,
        1,
      );

      // Test with magic
      final magicState = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
        attackStyle: AttackStyle.standard,
      );
      expect(
        magicState
            .createCombatModifierProvider(
              conditionContext: ConditionContext.empty,
            )
            .flatResistance,
        1,
      );
    });
  });

  group('Summoning Synergies', () {
    late Item golbinThiefTablet;
    late Item occultistTablet;
    late SummoningAction golbinThiefAction;
    late SummoningAction occultistAction;

    setUpAll(() async {
      await loadTestRegistries();
      // Get Golbin Thief and Occultist familiars (they have a synergy)
      golbinThiefAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.name.contains('Golbin Thief'),
      );
      occultistAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.name.contains('Occultist'),
      );

      golbinThiefTablet = testItems.byId(golbinThiefAction.productId);
      occultistTablet = testItems.byId(occultistAction.productId);
    });

    test('no synergy when only one tablet equipped', () {
      const equipment = Equipment.empty();
      final (equipped, _) = equipment.equipSummonTablet(
        golbinThiefTablet,
        EquipmentSlot.summon1,
        10,
      );

      // Even with high mark levels, no synergy with only one tablet
      final summoningState = const SummoningState.empty().withMarks(
        golbinThiefAction.productId,
        61,
      ); // Mark level 6

      final state = GlobalState.test(
        testRegistries,
        equipment: equipped,
        summoning: summoningState,
      );

      expect(state.getActiveSynergy(), isNull);
    });

    test('no synergy when mark levels too low', () {
      const equipment = Equipment.empty();
      final (equipped1, _) = equipment.equipSummonTablet(
        golbinThiefTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (equipped2, _) = equipped1.equipSummonTablet(
        occultistTablet,
        EquipmentSlot.summon2,
        10,
      );

      // Only mark level 2 for each (need level 3)
      final summoningState = const SummoningState.empty()
          .withMarks(golbinThiefAction.productId, 15) // Mark level 2
          .withMarks(occultistAction.productId, 15); // Mark level 2

      final state = GlobalState.test(
        testRegistries,
        equipment: equipped2,
        summoning: summoningState,
      );

      expect(state.getActiveSynergy(), isNull);
    });

    test('synergy activates with mark level 3 for both familiars', () {
      const equipment = Equipment.empty();
      final (equipped1, _) = equipment.equipSummonTablet(
        golbinThiefTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (equipped2, _) = equipped1.equipSummonTablet(
        occultistTablet,
        EquipmentSlot.summon2,
        10,
      );

      // Mark level 3 for both (16 marks = level 3)
      final summoningState = const SummoningState.empty()
          .withMarks(golbinThiefAction.productId, 16)
          .withMarks(occultistAction.productId, 16);

      final state = GlobalState.test(
        testRegistries,
        equipment: equipped2,
        summoning: summoningState,
      );

      final synergy = state.getActiveSynergy();
      expect(synergy, isNotNull);
      // Golbin Thief + Occultist has currencyGainOnMonsterKillBasedOnEvasion
      expect(synergy!.modifiers.modifiers, isNotEmpty);
    });

    test('synergy modifiers are included in resolved modifiers', () {
      const equipment = Equipment.empty();
      final (equipped1, _) = equipment.equipSummonTablet(
        golbinThiefTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (equipped2, _) = equipped1.equipSummonTablet(
        occultistTablet,
        EquipmentSlot.summon2,
        10,
      );

      // Mark level 3 for both
      final summoningState = const SummoningState.empty()
          .withMarks(golbinThiefAction.productId, 16)
          .withMarks(occultistAction.productId, 16);

      final state = GlobalState.test(
        testRegistries,
        equipment: equipped2,
        summoning: summoningState,
      );

      // Verify synergy is active
      expect(state.getActiveSynergy(), isNotNull);

      // Resolve combat modifiers - synergy modifiers should be included
      final modifiers = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // The Golbin Thief + Occultist synergy provides
      // currencyGainOnMonsterKillBasedOnEvasion which should be in modifiers
      expect(modifiers.currencyGainOnMonsterKillBasedOnEvasion, greaterThan(0));
    });

    test('synergy registry finds synergies correctly', () {
      // Test the synergy lookup directly
      final synergy = testRegistries.summoningSynergies.findSynergy(
        golbinThiefAction.summonId,
        occultistAction.summonId,
      );
      expect(synergy, isNotNull);

      // Test reverse order
      final synergyReverse = testRegistries.summoningSynergies.findSynergy(
        occultistAction.summonId,
        golbinThiefAction.summonId,
      );
      expect(synergyReverse, isNotNull);

      // Both should be the same synergy
      expect(synergy, equals(synergyReverse));
    });

    test('real Ent+Bear synergy has Bird Nest Potion conditional', () {
      // Ent + Bear synergy in the real Melvor data has a PotionUsedCondition
      // for Bird Nest Potion that grants flatBaseRandomProductQuantity.
      const entId = MelvorId('melvorF:Ent');
      const bearId = MelvorId('melvorF:Bear');
      final synergy = testRegistries.summoningSynergies.findSynergy(
        entId,
        bearId,
      );
      expect(synergy, isNotNull, reason: 'Ent+Bear synergy should exist');
      expect(
        synergy!.conditionalModifiers,
        isNotEmpty,
        reason: 'Should have conditional modifiers',
      );

      final potionCond = synergy.conditionalModifiers.firstWhere(
        (c) => c.condition is PotionUsedCondition,
      );
      final condition = potionCond.condition as PotionUsedCondition;
      expect(condition.recipeId, const MelvorId('melvorF:Bird_Nest_Potion'));
      expect(potionCond.modifiers.modifiers, isNotEmpty);
    });

    test('fromJson parses consumesOn entries', () {
      final json = {
        'summonIDs': ['melvorF:Ent', 'melvorF:Bear'],
        'modifiers': <String, dynamic>{},
        'consumesOn': [
          {'type': 'WoodcuttingAction'},
          {'type': 'PlayerSummonAttack'},
          {
            'type': 'ThievingAction',
            'succesful': true,
            'npcIDs': ['melvorF:LUMBERJACK'],
          },
        ],
      };
      final synergy = SummoningSynergy.fromJson(json, namespace: 'melvorF');

      expect(synergy.consumesOn, hasLength(3));
      expect(synergy.appliesTo(ConsumesOnType.woodcuttingAction), true);
      expect(synergy.appliesTo(ConsumesOnType.thievingAction), true);
      expect(synergy.appliesTo(ConsumesOnType.miningAction), false);
      expect(synergy.appliesTo(ConsumesOnType.playerSummonAttack), true);

      // Verify detailed fields on thieving entry.
      final thieving = synergy.consumesOn.firstWhere(
        (e) => e.type == ConsumesOnType.thievingAction,
      );
      expect(thieving.successful, true);
      expect(thieving.npcIds, [const MelvorId('melvorF:LUMBERJACK')]);
    });

    test('real Ent+Bear synergy consumesOn parsed from data', () {
      const entId = MelvorId('melvorF:Ent');
      const bearId = MelvorId('melvorF:Bear');
      final synergy = testRegistries.summoningSynergies.findSynergy(
        entId,
        bearId,
      );
      expect(synergy, isNotNull);
      // Ent+Bear consumesOn includes WoodcuttingAction.
      expect(synergy!.appliesTo(ConsumesOnType.woodcuttingAction), true);
      expect(synergy.appliesTo(ConsumesOnType.miningAction), false);
    });

    test('fromJson parses conditionalModifiers', () {
      final json = {
        'summonIDs': ['melvorF:GolbinThief', 'melvorF:Occultist'],
        'modifiers': <String, dynamic>{},
        'conditionalModifiers': [
          {
            'condition': {
              'type': 'PotionUsed',
              'recipeID': 'melvorF:Bird_Nest_Potion',
            },
            'modifiers': {
              'increasedChanceToPreserveNest': [
                {'value': 50},
              ],
            },
          },
        ],
      };

      final synergy = SummoningSynergy.fromJson(json, namespace: 'melvorF');

      expect(synergy.conditionalModifiers, hasLength(1));
      final condMod = synergy.conditionalModifiers.first;
      expect(condMod.condition, isA<PotionUsedCondition>());
      final condition = condMod.condition as PotionUsedCondition;
      expect(condition.recipeId, const MelvorId('melvorF:Bird_Nest_Potion'));
      expect(condMod.modifiers.modifiers, isNotEmpty);
    });

    test('synergy conditional modifiers apply when condition met', () {
      const potionRecipeId = MelvorId('melvorF:TestPotion');

      // Create a synergy with a PotionUsed conditional modifier
      const synergy = SummoningSynergy(
        summonIds: [
          MelvorId('melvorF:GolbinThief'),
          MelvorId('melvorF:Occultist'),
        ],
        modifiers: ModifierDataSet([]),
        conditionalModifiers: [
          ConditionalModifier(
            condition: PotionUsedCondition(recipeId: potionRecipeId),
            modifiers: ModifierDataSet([
              ModifierData(
                name: 'increasedGPFromMonsters',
                entries: [ModifierEntry(value: 25)],
              ),
            ]),
          ),
        ],
      );

      // Without matching condition — conditional modifier should not apply
      final modsNoMatch = synergy.conditionalModifiers
          .where((c) => ConditionContext.empty.evaluate(c.condition))
          .toList();
      expect(modsNoMatch, isEmpty);

      // With matching potion condition
      final context = ConditionContext(activePotionRecipes: {potionRecipeId});
      final modsMatch = synergy.conditionalModifiers
          .where((c) => context.evaluate(c.condition))
          .toList();
      expect(modsMatch, hasLength(1));
      expect(
        modsMatch.first.modifiers.modifiers.first.name,
        'increasedGPFromMonsters',
      );
      expect(modsMatch.first.modifiers.modifiers.first.entries.first.value, 25);
    });

    test('combat synergy not active during woodcutting, tablets apply', () {
      // Golbin Thief + Occultist is a combat synergy. During woodcutting
      // neither familiar is relevant and the synergy should not activate.
      // Equip an Ent (relevant to woodcutting) in slot 1 and verify its
      // individual modifiers still apply when slot 2 has a combat familiar
      // with no synergy to Ent.
      final entAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.woodcutting.id),
      );
      final entTablet = testItems.byId(entAction.productId);

      const equipment = Equipment.empty();
      final (equipped1, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (equipped2, _) = equipped1.equipSummonTablet(
        golbinThiefTablet,
        EquipmentSlot.summon2,
        10,
      );

      final summoningState = const SummoningState.empty()
          .withMarks(entAction.productId, 16)
          .withMarks(golbinThiefAction.productId, 16);

      final state = GlobalState.test(
        testRegistries,
        equipment: equipped2,
        summoning: summoningState,
      );

      // No synergy between Ent and Golbin Thief.
      expect(state.getActiveSynergy(), isNull);

      final wcAction = testRegistries.woodcutting.actions.first;
      final modifiers = state.testModifiersFor(wcAction);

      // Ent's individual modifier applies since no synergy is active.
      expect(
        modifiers.additionalPrimaryProductChance(skillId: wcAction.skill.id),
        10,
      );
    });

    test('synergy replaces individual tablets when applicable', () {
      // When a synergy applies to the current skill, individual tablet
      // modifiers are replaced by synergy modifiers.
      final entAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.woodcutting.id),
      );
      final entTablet = testItems.byId(entAction.productId);

      // Find a familiar that forms a woodcutting synergy with Ent.
      SummoningSynergy? wcSynergy;
      SummoningAction? partnerAction;
      for (final syn in testRegistries.summoningSynergies.all) {
        if (!syn.appliesTo(ConsumesOnType.woodcuttingAction)) continue;
        if (!syn.summonIds.contains(entAction.summonId)) continue;
        wcSynergy = syn;
        final partnerId = syn.summonIds.firstWhere(
          (id) => id != entAction.summonId,
        );
        partnerAction = testRegistries.summoning.actions.firstWhere(
          (a) => a.summonId == partnerId,
        );
        break;
      }
      // Skip if no woodcutting synergy exists for Ent in test data.
      if (wcSynergy == null || partnerAction == null) return;

      final partnerTablet = testItems.byId(partnerAction.productId);

      const equipment = Equipment.empty();
      final (equipped1, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (equipped2, _) = equipped1.equipSummonTablet(
        partnerTablet,
        EquipmentSlot.summon2,
        10,
      );

      final summoningState = const SummoningState.empty()
          .withMarks(entAction.productId, 16)
          .withMarks(partnerAction.productId, 16);

      final state = GlobalState.test(
        testRegistries,
        equipment: equipped2,
        summoning: summoningState,
      );

      final wcAction = testRegistries.woodcutting.actions.first;
      final modifiers = state.createActionModifierProvider(
        wcAction,
        conditionContext: ConditionContext.empty,
        consumesOnType: ConsumesOnType.woodcuttingAction,
      );

      // With the synergy active for woodcutting, Ent's individual
      // additionalPrimaryProductChance should NOT apply.
      expect(
        modifiers.additionalPrimaryProductChance(skillId: wcAction.skill.id),
        0,
      );
    });
  });

  group('Synergy Charge Consumption', () {
    late Item entTablet;
    late Item bearTablet;
    late SummoningAction entAction;
    late SummoningAction bearAction;
    late SkillAction woodcuttingAction;

    setUpAll(() async {
      await loadTestRegistries();
      entAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.markSkillIds.contains(Skill.woodcutting.id),
      );
      entTablet = testItems.byId(entAction.productId);

      // Bear is a combat familiar (relevant to Strength).
      bearAction = testRegistries.summoning.actions.firstWhere(
        (a) => a.name.contains('Bear'),
      );
      bearTablet = testItems.byId(bearAction.productId);

      woodcuttingAction = testRegistries.woodcutting.actions.first;
    });

    test('synergy consumes charges from both tablets on matching action', () {
      // Equip Ent (slot1, woodcutting) + Bear (slot2, combat).
      const equipment = Equipment.empty();
      final (eq1, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (eq2, _) = eq1.equipSummonTablet(
        bearTablet,
        EquipmentSlot.summon2,
        10,
      );

      // Activate synergy: mark level >= 3 for both.
      final summoningState = const SummoningState.empty()
          .withMarks(entAction.productId, 16)
          .withMarks(bearAction.productId, 16);

      var inventory = Inventory.empty(testItems);
      for (final input in woodcuttingAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventory = inventory.adding(ItemStack(item, count: input.value * 100));
      }

      final state = GlobalState.test(
        testRegistries,
        equipment: eq2,
        summoning: summoningState,
        inventory: inventory,
      ).startAction(woodcuttingAction, random: Random(42));

      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 1000, random: Random(42));
      final newState = builder.build();

      // Both tablets should have consumed charges, even though Bear is not
      // individually relevant to woodcutting.
      expect(
        newState.equipment.summonCountInSlot(EquipmentSlot.summon1),
        lessThan(10),
      );
      expect(
        newState.equipment.summonCountInSlot(EquipmentSlot.summon2),
        lessThan(10),
      );
    });

    test('without synergy, irrelevant tablet does not consume charges', () {
      // Equip Ent (slot1) + Bear (slot2) but without mark levels for synergy.
      const equipment = Equipment.empty();
      final (eq1, _) = equipment.equipSummonTablet(
        entTablet,
        EquipmentSlot.summon1,
        10,
      );
      final (eq2, _) = eq1.equipSummonTablet(
        bearTablet,
        EquipmentSlot.summon2,
        10,
      );

      // Mark levels too low for synergy (need 16 for level 3).
      final summoningState = const SummoningState.empty()
          .withMarks(entAction.productId, 5)
          .withMarks(bearAction.productId, 5);

      var inventory = Inventory.empty(testItems);
      for (final input in woodcuttingAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventory = inventory.adding(ItemStack(item, count: input.value * 100));
      }

      final state = GlobalState.test(
        testRegistries,
        equipment: eq2,
        summoning: summoningState,
        inventory: inventory,
      ).startAction(woodcuttingAction, random: Random(42));

      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 1000, random: Random(42));
      final newState = builder.build();

      // Ent is relevant to woodcutting, should consume charges.
      expect(
        newState.equipment.summonCountInSlot(EquipmentSlot.summon1),
        lessThan(10),
      );
      // Bear is NOT relevant to woodcutting, should NOT consume charges.
      expect(newState.equipment.summonCountInSlot(EquipmentSlot.summon2), 10);
    });
  });
}
