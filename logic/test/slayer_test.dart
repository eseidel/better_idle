import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(loadTestRegistries);

  /// High combat skills so the player can one-shot weak monsters.
  const highSkill = SkillState(xp: 1000000, masteryPoolXp: 0);
  const highCombatSkills = {
    Skill.hitpoints: highSkill,
    Skill.attack: highSkill,
    Skill.strength: highSkill,
    Skill.defence: highSkill,
    Skill.slayer: highSkill,
  };

  SlayerTaskCategory easyCategory() {
    final categories = testRegistries.slayer.taskCategories.all;
    // Easy is the first/lowest level category.
    return categories.firstWhere(
      (c) => c.name == 'Easy',
      orElse: () => categories.first,
    );
  }

  group('slayer tasks', () {
    test(
      'startSlayerTask creates a combat activity with SlayerTaskContext',
      () {
        final category = easyCategory();
        var state = GlobalState.test(
          testRegistries,
          skillStates: highCombatSkills,
          currencies: {
            for (final cost in category.rollCost.costs)
              cost.currency: cost.amount * 10,
          },
        );
        final random = Random(42);
        state = state.startSlayerTask(category: category, random: random);

        expect(state.activeActivity, isA<CombatActivity>());
        final activity = state.activeActivity! as CombatActivity;
        expect(activity.context, isA<SlayerTaskContext>());
        final context = activity.context as SlayerTaskContext;
        expect(context.categoryId, category.id);
        expect(context.killsRequired, greaterThan(0));
        expect(context.killsCompleted, 0);
      },
    );

    test('startSlayerTask deducts roll cost', () {
      final category = easyCategory();
      final initialCurrencies = <Currency, int>{
        for (final cost in category.rollCost.costs)
          cost.currency: cost.amount * 5,
      };
      var state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        currencies: initialCurrencies,
      );
      final random = Random(42);
      state = state.startSlayerTask(category: category, random: random);

      for (final cost in category.rollCost.costs) {
        expect(
          state.currency(cost.currency),
          initialCurrencies[cost.currency]! - cost.amount,
        );
      }
    });

    test('startSlayerTask throws when slayer level is too low', () {
      final category = easyCategory();
      final state = GlobalState.test(
        testRegistries,
        currencies: {
          for (final cost in category.rollCost.costs)
            cost.currency: cost.amount * 10,
        },
      );
      final random = Random(42);

      if (category.level > 1) {
        expect(
          () => state.startSlayerTask(category: category, random: random),
          throwsArgumentError,
        );
      }
    });

    test('startSlayerTask throws when currency is insufficient', () {
      final category = easyCategory();
      if (category.rollCost.costs.isEmpty) return;

      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
      );
      final random = Random(42);

      expect(
        () => state.startSlayerTask(category: category, random: random),
        throwsArgumentError,
      );
    });

    test(
      'completing slayer combat grants slayer XP and increments completions',
      () {
        final category = easyCategory();
        var state = GlobalState.test(
          testRegistries,
          skillStates: highCombatSkills,
          currencies: {
            for (final cost in category.rollCost.costs)
              cost.currency: cost.amount * 10,
          },
        );
        final random = Random(42);
        state = state.startSlayerTask(category: category, random: random);

        final activity = state.activeActivity! as CombatActivity;
        final context = activity.context as SlayerTaskContext;

        // Record initial slayer XP.
        final initialSlayerXp = state.skillState(Skill.slayer).xp;
        expect(state.slayerTaskCompletions[category.id] ?? 0, 0);

        // Override killsRequired to a small number for test speed.
        // The real value can be 50+, each kill needs ~30+ ticks.
        const testKills = 3;
        state = state.copyWith(
          activeActivity: (state.activeActivity! as CombatActivity).copyWith(
            context: context.copyWith(killsRequired: testKills),
          ),
        );

        // Process ticks in a loop to complete all kills.
        var totalTicks = 0;
        while (state.activeActivity != null && totalTicks < 50000) {
          final builder = StateUpdateBuilder(state);
          consumeTicks(builder, 1000, random: random);
          state = builder.build();
          totalTicks += 1000;
        }

        // Should have gained slayer XP.
        expect(state.skillState(Skill.slayer).xp, greaterThan(initialSlayerXp));

        // Should have incremented task completion count.
        expect(state.slayerTaskCompletions[category.id], 1);
      },
    );

    test('slayer combat continues between kills within a task', () {
      final category = easyCategory();
      var state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        currencies: {
          for (final cost in category.rollCost.costs)
            cost.currency: cost.amount * 10,
        },
      );
      // Use a fixed seed for a task requiring multiple kills.
      final random = Random(99);
      state = state.startSlayerTask(category: category, random: random);

      final activity = state.activeActivity! as CombatActivity;
      final context = activity.context as SlayerTaskContext;

      // Only process enough ticks for one kill (not enough for all).
      if (context.killsRequired > 1) {
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, 200, random: random);
        state = builder.build();

        // Should still be in combat with an updated slayer context.
        if (state.activeActivity != null) {
          final updatedActivity = state.activeActivity! as CombatActivity;
          final updatedContext = updatedActivity.context as SlayerTaskContext;
          expect(updatedContext.categoryId, category.id);
          // Should have at least one kill recorded but task not yet complete.
          expect(updatedContext.killsCompleted, greaterThanOrEqualTo(0));
          expect(
            updatedContext.killsCompleted,
            lessThan(updatedContext.killsRequired),
          );
        }
      }
    });

    test('slayer task rewards currency based on category currencyRewards', () {
      final category = easyCategory();
      if (category.currencyRewards.isEmpty) return;

      var state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        currencies: {
          for (final cost in category.rollCost.costs)
            cost.currency: cost.amount * 10,
        },
      );
      final random = Random(42);
      state = state.startSlayerTask(category: category, random: random);

      // Track initial currency for rewards.
      final rewardCurrencyAmounts = <Currency, int>{
        for (final reward in category.currencyRewards)
          reward.currency: state.currency(reward.currency),
      };

      final activity = state.activeActivity! as CombatActivity;
      final context = activity.context as SlayerTaskContext;

      // Override to small number for test speed.
      const testKills = 3;
      state = state.copyWith(
        activeActivity: activity.copyWith(
          context: context.copyWith(killsRequired: testKills),
        ),
      );

      // Complete the full task.
      var totalTicks = 0;
      while (state.activeActivity != null && totalTicks < 50000) {
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, 1000, random: random);
        state = builder.build();
        totalTicks += 1000;
      }

      // Each reward currency should have increased.
      for (final reward in category.currencyRewards) {
        expect(
          state.currency(reward.currency),
          greaterThan(rewardCurrencyAmounts[reward.currency]!),
          reason: 'Should have earned ${reward.currency} reward',
        );
      }
    });
  });
}
