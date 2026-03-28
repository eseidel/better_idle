import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late WoodcuttingTree normalTree;

  setUpAll(() async {
    await loadTestRegistries();

    normalTree =
        testRegistries.woodcuttingAction('Normal Tree') as WoodcuttingTree;
  });

  group('globalItemDoublingChance', () {
    test('stacks with skillItemDoublingChance', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');

      // 50% from skill + 50% from global = 100% effective doubling.
      final modifiers = StubModifierProvider({
        'skillItemDoublingChance': 50,
        'globalItemDoublingChance': 50,
      });

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final random = Random(42);

      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      // With 100% combined chance, should always double.
      final count = builder.state.inventory.countById(normalLogsId);
      expect(count, 2, reason: 'Should always double with 100% combined');
    });

    test('works alone without skillItemDoublingChance', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');

      // 100% from global alone.
      final modifiers = StubModifierProvider({'globalItemDoublingChance': 100});

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final random = Random(42);

      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      final count = builder.state.inventory.countById(normalLogsId);
      expect(count, 2, reason: 'Should double with 100% global chance');
    });
  });

  group('doubleItemsSkill', () {
    test('adds to doubling chance for matching skill', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');

      // 100% from doubleItemsSkill alone should always double.
      final modifiers = StubModifierProvider({'doubleItemsSkill': 100});

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final random = Random(42);

      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      final count = builder.state.inventory.countById(normalLogsId);
      expect(count, 2, reason: 'Should double with 100% doubleItemsSkill');
    });
  });

  group('nonCombatSkillXP', () {
    test('applies XP bonus to non-combat skills', () {
      final state = GlobalState.test(testRegistries);

      // +50% XP bonus for non-combat skills
      final modifiers = StubModifierProvider({'nonCombatSkillXP': 50});
      final base = xpPerAction(state, normalTree, StubModifierProvider());

      final boosted = xpPerAction(state, normalTree, modifiers);

      // 50% increase: boosted should be ~1.5x base.
      expect(boosted.xp, greaterThan(base.xp));
      expect(boosted.xp, (base.xp * 1.5).round());
    });

    test('stacks with skillXP modifier', () {
      final state = GlobalState.test(testRegistries);

      // +20% from skillXP and +30% from nonCombatSkillXP = +50% total.
      final stacked = StubModifierProvider({
        'skillXP': 20,
        'nonCombatSkillXP': 30,
      });
      final separate50 = StubModifierProvider({'skillXP': 50});

      final stackedXp = xpPerAction(state, normalTree, stacked);
      final separate50Xp = xpPerAction(state, normalTree, separate50);

      expect(stackedXp.xp, separate50Xp.xp);
    });
  });

  group('altMagicSkillXP', () {
    test('applies XP bonus to alt magic actions', () {
      final altMagicActions = testRegistries.altMagic.actions;
      if (altMagicActions.isEmpty) {
        // Skip if no alt magic actions in test data.
        return;
      }
      final altAction = altMagicActions.first;
      final state = GlobalState.test(testRegistries);

      final base = xpPerAction(state, altAction, StubModifierProvider());
      final boosted = xpPerAction(
        state,
        altAction,
        StubModifierProvider({'altMagicSkillXP': 100}),
      );

      // +100% XP: boosted should be 2x base.
      expect(boosted.xp, base.xp * 2);
    });

    test('does not apply to non-alt-magic skills', () {
      final state = GlobalState.test(testRegistries);

      final base = xpPerAction(state, normalTree, StubModifierProvider());
      final withAltMagicMod = xpPerAction(
        state,
        normalTree,
        StubModifierProvider({'altMagicSkillXP': 100}),
      );

      // Alt magic XP mod should not affect woodcutting.
      expect(withAltMagicMod.xp, base.xp);
    });
  });

  group('flatMasteryTokens', () {
    test('MasteryTokenDrop rollWithContext returns 1 token normally', () {
      const drop = MasteryTokenDrop(skill: Skill.woodcutting);
      // With 18500 unlocked, chance is 100%.
      final result = drop.rollWithContext(
        testItems,
        Random(42),
        unlockedActions: 18500,
      );
      expect(result, isNotNull);
      expect(result!.count, 1);
    });

    test('flatMasteryTokens bonus is applied in rollAndCollectDrops', () {
      const wcTokenId = MelvorId('melvorD:Mastery_Token_Woodcutting');

      final modifiers = StubModifierProvider({'flatMasteryTokens': 2});

      // Give max WC level so all actions unlocked for higher drop rate.
      // Use a targeted approach: find a seed that drops a token first.
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.woodcutting: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );

      // First find a seed that produces a token drop.
      late int goodSeed;
      var found = false;
      for (var i = 0; i < 50000; i++) {
        final builder = StateUpdateBuilder(state);
        rollAndCollectDrops(
          builder,
          normalTree,
          StubModifierProvider(),
          Random(i),
          const NoSelectedRecipe(),
        );
        if (builder.state.inventory.countById(wcTokenId) > 0) {
          goodSeed = i;
          found = true;
          break;
        }
      }

      expect(found, isTrue, reason: 'Should find a seed that drops a token');

      // Now use the same seed with flatMasteryTokens modifier.
      final builder = StateUpdateBuilder(state);
      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        Random(goodSeed),
        const NoSelectedRecipe(),
      );
      final count = builder.state.inventory.countById(wcTokenId);
      expect(count, 3, reason: 'Token should be 1 base + 2 flat bonus');
    });

    test('does not add bonus when no token drops', () {
      const wcTokenId = MelvorId('melvorD:Mastery_Token_Woodcutting');

      final modifiers = StubModifierProvider({'flatMasteryTokens': 5});

      // At level 1, drop rate is ~1/18500, so most trials produce no token.
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        Random(42),
        const NoSelectedRecipe(),
      );
      final count = builder.state.inventory.countById(wcTokenId);
      expect(count, 0, reason: 'No bonus without a token drop');
    });
  });

  group('combatLootDoublingChance', () {
    test('modifier accessor returns expected value', () {
      final modifiers = StubModifierProvider({'combatLootDoublingChance': 100});
      expect(modifiers.combatLootDoublingChance, 100);
    });
  });

  group('doublingChance combines all sources', () {
    test('SkillAction.doublingChance sums all three modifiers', () {
      // 30% skill + 20% global + 10% doubleItemsSkill = 60% total.
      final modifiers = StubModifierProvider({
        'skillItemDoublingChance': 30,
        'globalItemDoublingChance': 20,
        'doubleItemsSkill': 10,
      });

      final chance = normalTree.doublingChance(modifiers);
      expect(chance, closeTo(0.6, 0.001));
    });

    test('clamps to 1.0 when total exceeds 100%', () {
      final modifiers = StubModifierProvider({
        'skillItemDoublingChance': 80,
        'globalItemDoublingChance': 80,
      });

      final chance = normalTree.doublingChance(modifiers);
      expect(chance, 1.0);
    });
  });
}
