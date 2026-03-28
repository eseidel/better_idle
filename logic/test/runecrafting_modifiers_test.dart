import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late RunecraftingAction airRune;
  late Item airRuneItem;
  late Item runeEssence;

  setUpAll(() async {
    await loadTestRegistries();
    airRune = testRegistries.runecraftingAction('Air Rune');
    airRuneItem = testItems.byName('Air Rune');
    runeEssence = testItems.byName('Rune Essence');
  });

  group('RunecraftingRegistry rune classification', () {
    test('elementalRuneIds is not empty', () {
      expect(
        testRegistries.runecrafting.elementalRuneIds,
        isNotEmpty,
      );
    });

    test('comboRuneIds is not empty', () {
      expect(
        testRegistries.runecrafting.comboRuneIds,
        isNotEmpty,
      );
    });

    test('Air Rune is an elemental rune', () {
      expect(
        testRegistries.runecrafting.isElementalRune(
          airRuneItem.id,
        ),
        isTrue,
      );
    });

    test('Air Rune is not a combo rune', () {
      expect(
        testRegistries.runecrafting.isComboRune(airRuneItem.id),
        isFalse,
      );
    });
  });

  group('doubleRuneProvision', () {
    test('produces runes when crafting', () {
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(runeEssence, count: 100),
        ]),
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
      expect(
        state.inventory.countOfItem(airRuneItem),
        greaterThan(0),
      );
    });
  });

  group('runecraftingBaseXPForRunes', () {
    test('adds flat base XP for rune actions', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );
      final baseModifiers = StubModifierProvider();
      final baseResult =
          xpPerAction(state, airRune, baseModifiers);
      final bonusModifiers = StubModifierProvider({
        'runecraftingBaseXPForRunes': 10,
      });
      final bonusResult =
          xpPerAction(state, airRune, bonusModifiers);
      expect(bonusResult.xp, baseResult.xp + 10);
    });

    test('does not apply to non-rune runecrafting', () {
      final staffOfAir =
          testRegistries.runecraftingAction('Staff of Air');
      final state = GlobalState.test(
        testRegistries,
        skillStates: {
          Skill.runecrafting: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );
      final baseModifiers = StubModifierProvider();
      final baseXp =
          xpPerAction(state, staffOfAir, baseModifiers);
      final bonusModifiers = StubModifierProvider({
        'runecraftingBaseXPForRunes': 10,
      });
      final bonusXp =
          xpPerAction(state, staffOfAir, bonusModifiers);
      expect(bonusXp.xp, baseXp.xp);
    });
  });
}
