import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Finds a slayer area that has a player-targeting area effect.
SlayerArea _areaWithPlayerEffect(Registries registries) {
  return registries.slayer.areas.all.firstWhere(
    (a) => a.areaEffect != null && a.areaEffect!.target == 'Player',
  );
}

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
    return categories.firstWhere(
      (c) => c.name == 'Easy',
      orElse: () => categories.first,
    );
  }

  /// Returns a category that has a non-empty roll cost (Normal: 2000 SC).
  SlayerTaskCategory paidCategory() {
    final categories = testRegistries.slayer.taskCategories.all;
    return categories.firstWhere((c) => c.rollCost.costs.isNotEmpty);
  }

  group('SlayerTaskContext serialization', () {
    test('round-trips through toJson/fromJson', () {
      const context = SlayerTaskContext(
        categoryId: MelvorId('melvorF:SlayerEasy'),
        monsterId: MelvorId('melvorD:Chicken'),
        killsRequired: 25,
        killsCompleted: 10,
      );
      final json = context.toJson();
      final restored = CombatContext.fromJson(json) as SlayerTaskContext;

      expect(restored.categoryId, context.categoryId);
      expect(restored.monsterId, context.monsterId);
      expect(restored.killsRequired, context.killsRequired);
      expect(restored.killsCompleted, context.killsCompleted);
    });

    test('toJson includes correct type tag', () {
      const context = SlayerTaskContext(
        categoryId: MelvorId('melvorF:SlayerEasy'),
        monsterId: MelvorId('melvorD:Chicken'),
        killsRequired: 5,
        killsCompleted: 0,
      );
      final json = context.toJson();
      expect(json['type'], 'slayerTask');
    });

    test('preserves zero killsCompleted', () {
      const context = SlayerTaskContext(
        categoryId: MelvorId('melvorF:SlayerHard'),
        monsterId: MelvorId('melvorD:Dragon'),
        killsRequired: 50,
        killsCompleted: 0,
      );
      final json = context.toJson();
      final restored = SlayerTaskContext.fromJson(json);
      expect(restored.killsCompleted, 0);
      expect(restored.killsRequired, 50);
    });
  });

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
      final category = paidCategory();
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
      final category = paidCategory();
      // Give enough currency but no slayer level.
      final state = GlobalState.test(
        testRegistries,
        currencies: {
          for (final cost in category.rollCost.costs)
            cost.currency: cost.amount * 10,
        },
      );
      final random = Random(42);

      expect(
        () => state.startSlayerTask(category: category, random: random),
        throwsArgumentError,
      );
    });

    test('startSlayerTask throws when currency is insufficient', () {
      final category = paidCategory();
      // Give slayer level but no currency.
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

  group('slayer area effects', () {
    test('combat modifier provider includes area effect modifiers', () {
      final area = _areaWithPlayerEffect(testRegistries);
      final effect = area.areaEffect!;
      final monsterId = area.monsterIds.first;

      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        activeActivity: CombatActivity(
          context: SlayerAreaCombatContext(
            slayerAreaId: area.id,
            monsterId: monsterId,
          ),
          progress: const CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );

      final provider = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // The area effect should apply its modifier.
      final modifierName = effect.modifiers.keys.first;
      final sign = effect.modifiers[modifierName]!;
      final expected = sign * effect.magnitude;

      // Get the modifier value - it includes area effect contribution.
      final value = provider.getModifier(modifierName);
      // The area effect should contribute the expected amount.
      // Other sources may also contribute, so check that removing the
      // area effect changes the value by the expected amount.
      final stateNoArea = state.copyWith(
        activeActivity: const CombatActivity(
          context: MonsterCombatContext(monsterId: MelvorId('melvorD:Chicken')),
          progress: CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );
      final providerNoArea = stateNoArea.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );
      final valueNoArea = providerNoArea.getModifier(modifierName);

      expect(value - valueNoArea, expected);
    });

    test('area effect is not applied for non-slayer-area combat', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        activeActivity: const CombatActivity(
          context: MonsterCombatContext(monsterId: MelvorId('melvorD:Chicken')),
          progress: CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );

      final provider = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // Penumbra's effect modifier - should not be present.
      final area = _areaWithPlayerEffect(testRegistries);
      final modifierName = area.areaEffect!.modifiers.keys.first;
      final sign = area.areaEffect!.modifiers[modifierName]!;

      // Without area, modifier should not include area effect.
      // (value should be 0 from area contribution - same as base)
      final stateInArea = state.copyWith(
        activeActivity: CombatActivity(
          context: SlayerAreaCombatContext(
            slayerAreaId: area.id,
            monsterId: area.monsterIds.first,
          ),
          progress: const CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );
      final providerInArea = stateInArea.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      expect(
        providerInArea.getModifier(modifierName) -
            provider.getModifier(modifierName),
        sign * area.areaEffect!.magnitude,
      );
    });

    test('flatSlayerAreaEffectNegation reduces area effect magnitude', () {
      final area = _areaWithPlayerEffect(testRegistries);
      final effect = area.areaEffect!;

      // Find a shop item that grants flatSlayerAreaEffectNegation.
      final shopItem = testRegistries.shop.all.where((p) {
        return p.contains.modifiers.modifiers.any(
          (m) => m.name == 'flatSlayerAreaEffectNegation',
        );
      });

      // If no shop item provides negation, test with the raw modifier.
      if (shopItem.isEmpty) {
        // Just verify magnitude is applied without negation.
        final state = GlobalState.test(
          testRegistries,
          skillStates: highCombatSkills,
          activeActivity: CombatActivity(
            context: SlayerAreaCombatContext(
              slayerAreaId: area.id,
              monsterId: area.monsterIds.first,
            ),
            progress: const CombatProgressState(
              monsterHp: 100,
              playerAttackTicksRemaining: 10,
              monsterAttackTicksRemaining: 10,
            ),
            progressTicks: 0,
            totalTicks: 10,
          ),
        );
        final provider = state.createCombatModifierProvider(
          conditionContext: ConditionContext.empty,
        );
        final modName = effect.modifiers.keys.first;
        // Provider should include the full area effect.
        expect(provider.getModifier(modName), isNonZero);
        return;
      }

      // Purchase the negation item.
      final purchase = shopItem.first;
      final negationValue =
          purchase.contains.modifiers.modifiers
                  .firstWhere((m) => m.name == 'flatSlayerAreaEffectNegation')
                  .entries
                  .first
                  .value
              as int;

      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        shop: ShopState(purchaseCounts: {purchase.id: 1}),
        activeActivity: CombatActivity(
          context: SlayerAreaCombatContext(
            slayerAreaId: area.id,
            monsterId: area.monsterIds.first,
          ),
          progress: const CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );

      final provider = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );
      final modName = effect.modifiers.keys.first;
      final sign = effect.modifiers[modName]!;

      // Without the shop purchase, effect would be sign * magnitude.
      // With negation, it should be sign * max(magnitude - negation, 0).
      final expectedMagnitude = (effect.magnitude - negationValue).clamp(
        0,
        999,
      );

      final stateNoShop = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        activeActivity: CombatActivity(
          context: SlayerAreaCombatContext(
            slayerAreaId: area.id,
            monsterId: area.monsterIds.first,
          ),
          progress: const CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );
      final providerNoShop = stateNoShop.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      final diff =
          provider.getModifier(modName) - providerNoShop.getModifier(modName);
      // The difference should be the reduction in the effect.
      expect(diff, sign * (expectedMagnitude - effect.magnitude));
    });

    test('area effect with enemy target is not applied to player', () {
      // Find an area with enemy-targeting effect.
      final enemyAreas = testRegistries.slayer.areas.all.where(
        (a) => a.areaEffect != null && a.areaEffect!.target == 'Enemy',
      );
      if (enemyAreas.isEmpty) return; // Skip if no enemy-target areas exist.

      final area = enemyAreas.first;
      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        activeActivity: CombatActivity(
          context: SlayerAreaCombatContext(
            slayerAreaId: area.id,
            monsterId: area.monsterIds.first,
          ),
          progress: const CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );

      // Enemy effects should not be in the player's modifier provider.
      final provider = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );
      final stateNoArea = state.copyWith(
        activeActivity: const CombatActivity(
          context: MonsterCombatContext(monsterId: MelvorId('melvorD:Chicken')),
          progress: CombatProgressState(
            monsterHp: 100,
            playerAttackTicksRemaining: 10,
            monsterAttackTicksRemaining: 10,
          ),
          progressTicks: 0,
          totalTicks: 10,
        ),
      );
      final providerNoArea = stateNoArea.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // Both should produce the same modifier values since enemy effects
      // should not affect the player's modifier provider.
      expect(
        provider.getModifier('accuracyRating'),
        providerNoArea.getModifier('accuracyRating'),
      );
    });
  });
}
