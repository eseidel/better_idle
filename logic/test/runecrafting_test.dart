import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late RunecraftingAction airRune;
  late RunecraftingAction staffOfAir;
  late Item airRuneItem;
  late Item runeEssence;

  setUpAll(() async {
    await loadTestRegistries();
    airRune = testRegistries.runecraftingAction('Air Rune');
    staffOfAir = testRegistries.runecraftingAction('Staff of Air');
    airRuneItem = testItems.byName('Air Rune');
    runeEssence = testItems.byName('Rune Essence');
  });

  group('mastery filter restricts bonuses by category', () {
    test('flatBasePrimaryProductQuantity only applies to rune category', () {
      final random = Random(42);

      // Air Rune is in StandardRunes category - filter "Rune" should apply.
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(runeEssence, count: 100),
        ]),
        actionStates: {airRune.id: ActionState(masteryXp: startXpForLevel(15))},
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );

      state = state.startAction(airRune, random: random);
      final builder = StateUpdateBuilder(state);
      completeAction(builder, airRune, random: random);
      state = builder.build();

      // At mastery 15, +1 bonus rune → 2 total.
      expect(state.inventory.countOfItem(airRuneItem), 2);
    });

    test(
      'flatBasePrimaryProductQuantity does not apply to equipment category',
      () {
        // Staff of Air is in StavesWands category - filter "Rune" should NOT
        // apply, so no flat product bonus even at high mastery.
        final normalLogs = testItems.byName('Normal Logs');
        final staffItem = testItems.byName('Staff of Air');

        var state = GlobalState.test(
          testRegistries,
          inventory: Inventory.fromItems(testItems, [
            ItemStack(normalLogs, count: 100),
            ItemStack(airRuneItem, count: 10000),
          ]),
          actionStates: {
            staffOfAir.id: ActionState(masteryXp: startXpForLevel(90)),
          },
          skillStates: {
            Skill.runecrafting: SkillState(
              xp: startXpForLevel(99),
              masteryPoolXp: 0,
            ),
          },
        );

        final random = Random(42);
        state = state.startAction(staffOfAir, random: random);
        final builder = StateUpdateBuilder(state);
        completeAction(builder, staffOfAir, random: random);
        state = builder.build();

        // Without the filter fix, mastery 90 would give +6 staves per craft.
        // With the filter fix, no bonus → exactly 1 staff.
        expect(state.inventory.countOfItem(staffItem), 1);
      },
    );
  });

  group('runecraftingRuneCostReduction', () {
    test('reduces rune costs for equipment actions', () {
      final normalLogs = testItems.byName('Normal Logs');
      final staffItem = testItems.byName('Staff of Air');

      // Staff of Air costs: 1 Normal Logs + 100 Air Runes.
      // At mastery 90, cost reduction = 9 tiers * 5% = 45%.
      // Reduced Air Rune cost: floor(100 * (1 - 0.45)) = 55.
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 100),
          ItemStack(airRuneItem, count: 10000),
        ]),
        actionStates: {
          staffOfAir.id: ActionState(masteryXp: startXpForLevel(90)),
        },
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );

      final random = Random(42);
      state = state.startAction(staffOfAir, random: random);
      final builder = StateUpdateBuilder(state);
      completeAction(builder, staffOfAir, random: random);
      state = builder.build();

      expect(state.inventory.countOfItem(staffItem), 1);
      // 10000 - 55 = 9945 Air Runes remaining (not 10000 - 100 = 9900).
      expect(state.inventory.countOfItem(airRuneItem), 9945);
      // Normal Logs not reduced (not a rune): 100 - 1 = 99.
      expect(state.inventory.countOfItem(normalLogs), 99);
    });

    test('does not reduce costs for standard rune actions', () {
      // Air Rune is in StandardRunes category, filter "Equipment" should NOT
      // apply cost reduction.
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(runeEssence, count: 100),
        ]),
        actionStates: {airRune.id: ActionState(masteryXp: startXpForLevel(90))},
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );

      final random = Random(42);
      state = state.startAction(airRune, random: random);
      final builder = StateUpdateBuilder(state);
      completeAction(builder, airRune, random: random);
      state = builder.build();

      // Still consumes exactly 1 Rune Essence.
      expect(state.inventory.countOfItem(runeEssence), 99);
    });

    test('canStartAction uses reduced costs', () {
      final normalLogs = testItems.byName('Normal Logs');

      // With 45% cost reduction, Staff of Air needs 55 Air Runes.
      // Give exactly 55 runes - should be able to start.
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 1),
          ItemStack(airRuneItem, count: 55),
        ]),
        actionStates: {
          staffOfAir.id: ActionState(masteryXp: startXpForLevel(90)),
        },
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );

      expect(state.canStartAction(staffOfAir), isTrue);
    });

    test('canStartAction fails when below reduced cost', () {
      final normalLogs = testItems.byName('Normal Logs');

      // With 45% reduction needs 55, give only 54.
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 1),
          ItemStack(airRuneItem, count: 54),
        ]),
        actionStates: {
          staffOfAir.id: ActionState(masteryXp: startXpForLevel(90)),
        },
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );

      expect(state.canStartAction(staffOfAir), isFalse);
    });
  });

  group('doubleRuneProvision feeds into doubling chance', () {
    test('doubles rune output when doubleRuneProvision triggers', () {
      final modifiers = StubModifierProvider({'doubleRuneProvision': 100});

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final random = Random(42);
      rollAndCollectDrops(
        builder,
        airRune,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      expect(builder.state.inventory.countOfItem(airRuneItem), 2);
    });

    test('no doubling without modifier', () {
      final modifiers = StubModifierProvider();

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final random = Random(42);
      rollAndCollectDrops(
        builder,
        airRune,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      expect(builder.state.inventory.countOfItem(airRuneItem), 1);
    });
  });

  group('elementalRuneChance feeds into doubling for elemental runes', () {
    test('doubles elemental rune output when elementalRuneChance triggers', () {
      final modifiers = StubModifierProvider({'elementalRuneChance': 100});

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final random = Random(42);
      rollAndCollectDrops(
        builder,
        airRune,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      expect(builder.state.inventory.countOfItem(airRuneItem), 2);
    });

    test('does not double non-elemental runecrafting output', () {
      final staffItem = testItems.byName('Staff of Air');
      final modifiers = StubModifierProvider({'elementalRuneChance': 100});

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final random = Random(42);
      rollAndCollectDrops(
        builder,
        staffOfAir,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      expect(builder.state.inventory.countOfItem(staffItem), 1);
    });
  });

  group('displayDoublingChance includes doubleRuneProvision', () {
    test('includes doubleRuneProvision for runecrafting actions', () {
      const modifierRing = Item(
        id: MelvorId('test:rune_ring'),
        name: 'Rune Ring',
        itemType: 'Equipment',
        sellsFor: 100,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'doubleRuneProvision',
            entries: [ModifierEntry(value: 15)],
          ),
        ]),
      );

      final state = GlobalState.test(
        testRegistries,
        equipment: const Equipment(
          foodSlots: [null, null, null],
          selectedFoodSlot: 0,
          gearSlots: {EquipmentSlot.ring: modifierRing},
        ),
      );

      final chance = state.displayDoublingChance(airRune);
      expect(chance, 15);
    });
  });

  group('applyRuneCostReduction', () {
    test('reduces rune costs by percentage', () {
      final result = testRegistries.runecrafting.applyRuneCostReduction({
        MelvorId.fromJson('melvorD:Air_Rune'): 100,
        MelvorId.fromJson('melvorD:Normal_Logs'): 1,
      }, 45);
      expect(result[MelvorId.fromJson('melvorD:Air_Rune')], 55);
      expect(result[MelvorId.fromJson('melvorD:Normal_Logs')], 1);
    });

    test('enforces minimum of 1 for rune costs', () {
      final result = testRegistries.runecrafting.applyRuneCostReduction({
        MelvorId.fromJson('melvorD:Air_Rune'): 1,
      }, 99);
      expect(result[MelvorId.fromJson('melvorD:Air_Rune')], 1);
    });

    test('no-op when reduction is 0', () {
      final inputs = {MelvorId.fromJson('melvorD:Air_Rune'): 100};
      final result = testRegistries.runecrafting.applyRuneCostReduction(
        inputs,
        0,
      );
      expect(result, inputs);
    });
  });
}
