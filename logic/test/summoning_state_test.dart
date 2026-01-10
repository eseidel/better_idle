import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
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
      summoningAction = testActions
          .forSkill(Skill.summoning)
          .whereType<SummoningAction>()
          .first;
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
      summoningAction = testActions
          .forSkill(Skill.summoning)
          .whereType<SummoningAction>()
          .first;
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
}
