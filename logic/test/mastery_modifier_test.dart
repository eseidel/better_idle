import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late RunecraftingAction airRune;
  late Item airRuneItem;
  late Item runeEssence;
  late SkillAction bronzeBar;
  late Item copperOre;
  late Item tinOre;

  setUpAll(() async {
    await loadTestRegistries();
    airRune = testRegistries.runecraftingAction('Air Rune');
    airRuneItem = testItems.byName('Air Rune');
    runeEssence = testItems.byName('Rune Essence');

    bronzeBar = testRegistries.smithingAction('Bronze Bar');
    copperOre = testItems.byName('Copper Ore');
    tinOre = testItems.byName('Tin Ore');
  });

  group('flatBasePrimaryProductQuantity', () {
    GlobalState stateWithMastery(int masteryLevel) {
      return GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(runeEssence, count: 100),
        ]),
        actionStates: {
          airRune.id: ActionState(masteryXp: startXpForLevel(masteryLevel)),
        },
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );
    }

    test('produces 1 rune at mastery level 1 (no bonus)', () {
      final state = stateWithMastery(1);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, airRune, random: random);
      final newState = builder.build();

      expect(newState.inventory.countOfItem(airRuneItem), 1);
    });

    test('produces extra runes at mastery level 15', () {
      final state = stateWithMastery(15);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, airRune, random: random);
      final newState = builder.build();

      // At mastery 15, the first flatBasePrimaryProductQuantity bonus
      // activates (+1), so we should get 2 runes.
      expect(newState.inventory.countOfItem(airRuneItem), 2);
    });

    test('produces more runes at higher mastery levels', () {
      // At mastery 90, the scaling bonus has triggered 6 times
      // (levels 15, 30, 45, 60, 75, 90) giving +6.
      final state = stateWithMastery(90);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, airRune, random: random);
      final newState = builder.build();

      expect(newState.inventory.countOfItem(airRuneItem), 7);
    });

    test('produces max runes at mastery level 99', () {
      // At mastery 99: scaling gives +6 (at 15,30,45,60,75,90)
      // plus the level 99 bonus of +4 = +10 total, so 11 runes.
      final state = stateWithMastery(99);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, airRune, random: random);
      final newState = builder.build();

      expect(newState.inventory.countOfItem(airRuneItem), 11);
    });
  });

  group('skillPreservationChance', () {
    GlobalState stateWithMastery(int masteryLevel) {
      return GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(copperOre, count: 100),
          ItemStack(tinOre, count: 100),
        ]),
        actionStates: {
          bronzeBar.id: ActionState(masteryXp: startXpForLevel(masteryLevel)),
        },
        skillStates: {
          Skill.smithing: SkillState(xp: startXpForLevel(99), masteryPoolXp: 0),
        },
      );
    }

    test('consumes inputs at mastery level 1 (no preservation)', () {
      final state = stateWithMastery(1);
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeAction(builder, bronzeBar, random: random);
      final newState = builder.build();

      // Inputs should be consumed normally.
      expect(newState.inventory.countOfItem(copperOre), 99);
      expect(newState.inventory.countOfItem(tinOre), 99);
    });

    test('sometimes preserves inputs at high mastery', () {
      // At high mastery, preservation chance is non-zero.
      // Run many completions and verify some inputs are preserved.
      final state = stateWithMastery(99);
      final random = Random(42);

      var currentState = state;
      for (var i = 0; i < 100; i++) {
        currentState = currentState.startAction(bronzeBar, random: random);
        final builder = StateUpdateBuilder(currentState);
        completeAction(builder, bronzeBar, random: random);
        currentState = builder.build();
      }

      // We did 100 completions. Without preservation, we'd use 100 of each.
      final copperUsed = 100 - currentState.inventory.countOfItem(copperOre);
      final tinUsed = 100 - currentState.inventory.countOfItem(tinOre);

      // With any preservation chance, some should be saved.
      // The exact number depends on the mastery bonus data.
      expect(
        copperUsed,
        lessThan(100),
        reason: 'some copper should be preserved at mastery 99',
      );
      expect(
        tinUsed,
        lessThan(100),
        reason: 'some tin should be preserved at mastery 99',
      );
      // But we should have still consumed some.
      expect(copperUsed, greaterThan(0));
      expect(tinUsed, greaterThan(0));
    });
  });
}
