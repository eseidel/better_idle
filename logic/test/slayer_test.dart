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

  group('SlayerTask serialization', () {
    test('round-trips through toJson/fromJson', () {
      const task = SlayerTask(
        categoryId: MelvorId('melvorF:SlayerEasy'),
        monsterId: MelvorId('melvorD:Chicken'),
        killsRequired: 25,
        killsCompleted: 10,
      );
      final json = task.toJson();
      final restored = SlayerTask.fromJson(json);

      expect(restored.categoryId, task.categoryId);
      expect(restored.monsterId, task.monsterId);
      expect(restored.killsRequired, task.killsRequired);
      expect(restored.killsCompleted, task.killsCompleted);
    });

    test('preserves zero killsCompleted', () {
      const task = SlayerTask(
        categoryId: MelvorId('melvorF:SlayerHard'),
        monsterId: MelvorId('melvorD:Dragon'),
        killsRequired: 50,
        killsCompleted: 0,
      );
      final json = task.toJson();
      final restored = SlayerTask.fromJson(json);
      expect(restored.killsCompleted, 0);
      expect(restored.killsRequired, 50);
    });

    test('old SlayerTaskContext JSON migrates to MonsterCombatContext', () {
      // Old format stored slayer tasks as a CombatContext type.
      final json = {
        'type': 'slayerTask',
        'categoryId': 'melvorF:SlayerEasy',
        'monsterId': 'melvorD:Chicken',
        'killsRequired': 25,
        'killsCompleted': 10,
      };
      final context = CombatContext.fromJson(json);
      expect(context, isA<MonsterCombatContext>());
      expect(context.currentMonsterId, const MelvorId('melvorD:Chicken'));
    });
  });

  group('slayer tasks', () {
    test('startSlayerTask sets slayerTask and starts combat', () {
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

      // Slayer task is set independently.
      expect(state.slayerTask, isNotNull);
      expect(state.slayerTask!.categoryId, category.id);
      expect(state.slayerTask!.killsRequired, greaterThan(0));
      expect(state.slayerTask!.killsCompleted, 0);

      // Combat activity uses MonsterCombatContext.
      expect(state.activeActivity, isA<CombatActivity>());
      final activity = state.activeActivity! as CombatActivity;
      expect(activity.context, isA<MonsterCombatContext>());
      expect(activity.context.currentMonsterId, state.slayerTask!.monsterId);
    });

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
      'completing slayer task grants slayer XP and increments completions',
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

        // Record initial slayer XP.
        final initialSlayerXp = state.skillState(Skill.slayer).xp;
        expect(state.slayerTaskCompletions[category.id] ?? 0, 0);

        // Override killsRequired to a small number for test speed.
        const testKills = 3;
        state = state.copyWith(
          slayerTask: state.slayerTask!.copyWith(killsRequired: testKills),
        );

        // Process ticks until the task completes.
        var totalTicks = 0;
        while (state.slayerTask != null && totalTicks < 50000) {
          final builder = StateUpdateBuilder(state);
          consumeTicks(builder, 1000, random: random);
          state = builder.build();
          totalTicks += 1000;
        }

        // Task should be cleared after completion.
        expect(state.slayerTask, isNull);

        // Combat should continue (player keeps fighting).
        expect(state.activeActivity, isNotNull);

        // Should have gained slayer XP.
        expect(state.skillState(Skill.slayer).xp, greaterThan(initialSlayerXp));

        // Should have incremented task completion count.
        expect(state.slayerTaskCompletions[category.id], 1);
      },
    );

    test('slayer task tracks kills between monster deaths', () {
      final category = easyCategory();
      var state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        currencies: {
          for (final cost in category.rollCost.costs)
            cost.currency: cost.amount * 10,
        },
      );
      final random = Random(99);
      state = state.startSlayerTask(category: category, random: random);

      // Only process enough ticks for one kill (not enough for all).
      if (state.slayerTask!.killsRequired > 1) {
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, 200, random: random);
        state = builder.build();

        // Should still have the slayer task with progress.
        if (state.slayerTask != null) {
          expect(state.slayerTask!.categoryId, category.id);
          expect(state.slayerTask!.killsCompleted, greaterThanOrEqualTo(0));
          expect(
            state.slayerTask!.killsCompleted,
            lessThan(state.slayerTask!.killsRequired),
          );
        }
      }
    });

    test('slayer task persists when switching combat areas', () {
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

      final task = state.slayerTask!;

      // Switch to a different monster.
      final differentMonster = testRegistries.combat.monsters.firstWhere(
        (m) => m.id.localId != task.monsterId,
      );
      state = state.startAction(differentMonster, random: random);

      // Slayer task should still be active.
      expect(state.slayerTask, isNotNull);
      expect(state.slayerTask!.categoryId, task.categoryId);
      expect(state.slayerTask!.monsterId, task.monsterId);

      // But combat is now with the different monster.
      final activity = state.activeActivity! as CombatActivity;
      expect(activity.context.currentMonsterId, differentMonster.id.localId);
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

      // Override to small number for test speed.
      const testKills = 3;
      state = state.copyWith(
        slayerTask: state.slayerTask!.copyWith(killsRequired: testKills),
      );

      // Complete the full task.
      var totalTicks = 0;
      while (state.slayerTask != null && totalTicks < 50000) {
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

  group('SlayerAreaCombatContext serialization', () {
    test('round-trips through toJson/fromJson', () {
      const context = SlayerAreaCombatContext(
        slayerAreaId: MelvorId('melvorD:Lowlands'),
        monsterId: MelvorId('melvorD:Cow'),
      );
      final json = context.toJson();
      final restored = CombatContext.fromJson(json) as SlayerAreaCombatContext;

      expect(restored.slayerAreaId, context.slayerAreaId);
      expect(restored.monsterId, context.monsterId);
    });

    test('toJson includes correct type tag', () {
      const context = SlayerAreaCombatContext(
        slayerAreaId: MelvorId('melvorD:Lowlands'),
        monsterId: MelvorId('melvorD:Cow'),
      );
      final json = context.toJson();
      expect(json['type'], 'slayerArea');
    });

    test('currentMonsterId returns monsterId', () {
      const context = SlayerAreaCombatContext(
        slayerAreaId: MelvorId('melvorD:Lowlands'),
        monsterId: MelvorId('melvorD:Cow'),
      );
      expect(context.currentMonsterId, const MelvorId('melvorD:Cow'));
    });
  });

  group('meetsSlayerAreaRequirements', () {
    test('returns true when all requirements are met', () {
      // Penumbra requires slayer level 1, which every player meets.
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.every(
          (r) => r is SlayerLevelRequirement && r.level <= 1,
        ),
      );
      final state = GlobalState.test(testRegistries);
      expect(state.meetsSlayerAreaRequirements(area), isTrue);
    });

    test('returns false when slayer level requirement is unmet', () {
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.any(
          (r) => r is SlayerLevelRequirement && r.level > 1,
        ),
      );
      // Level 1 player should not meet higher level requirements.
      final state = GlobalState.test(testRegistries);
      expect(state.meetsSlayerAreaRequirements(area), isFalse);
    });

    test('returns true when slayer level requirement is met', () {
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.any(
          (r) => r is SlayerLevelRequirement && r.level > 1,
        ),
      );
      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
      );
      // High slayer level should meet level requirements (item reqs may
      // still fail, so check only the level requirement specifically).
      final levelReqs = state
          .unmetSlayerAreaRequirements(area)
          .whereType<SlayerLevelRequirement>();
      expect(levelReqs, isEmpty);
    });
  });

  group('unmetSlayerAreaRequirements', () {
    test('returns empty list when all requirements are met', () {
      // Penumbra requires slayer level 1, which every player meets.
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.every(
          (r) => r is SlayerLevelRequirement && r.level <= 1,
        ),
      );
      final state = GlobalState.test(testRegistries);
      expect(state.unmetSlayerAreaRequirements(area), isEmpty);
    });

    test('returns all unmet requirements for under-leveled player', () {
      // Find an area requiring a slayer level above 1.
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.any(
          (r) => r is SlayerLevelRequirement && r.level > 1,
        ),
      );
      final state = GlobalState.test(testRegistries);
      final unmet = state.unmetSlayerAreaRequirements(area);
      expect(unmet, isNotEmpty);
    });

    test('item requirement is unmet without the item equipped', () {
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.any((r) => r is SlayerItemRequirement),
        orElse: () => throw StateError('No area with item requirement'),
      );
      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
      );
      final itemReqs = state
          .unmetSlayerAreaRequirements(area)
          .whereType<SlayerItemRequirement>();
      expect(itemReqs, isNotEmpty);
    });

    test('item requirement is met when the item is equipped', () {
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.any((r) => r is SlayerItemRequirement),
        orElse: () => throw StateError('No area with item requirement'),
      );
      final itemReq = area.entryRequirements
          .whereType<SlayerItemRequirement>()
          .first;
      final item = testRegistries.items.byId(itemReq.itemId);
      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        equipment: Equipment(
          foodSlots: const [null, null, null],
          selectedFoodSlot: 0,
          gearSlots: {item.validSlots.first: item},
        ),
      );
      final itemReqs = state
          .unmetSlayerAreaRequirements(area)
          .whereType<SlayerItemRequirement>();
      expect(itemReqs, isEmpty);
    });
  });

  group('startSlayerAreaCombat', () {
    /// Finds an area with only a level requirement (no item/dungeon/shop).
    SlayerArea levelOnlyArea() => testRegistries.slayer.areas.all.firstWhere(
      (a) =>
          a.entryRequirements.isNotEmpty &&
          a.entryRequirements.every((r) => r is SlayerLevelRequirement),
    );

    CombatAction monsterInArea(SlayerArea area) {
      final monsterId = area.monsterIds.first;
      return testRegistries.allActions.whereType<CombatAction>().firstWhere(
        (a) => a.id.localId == monsterId,
      );
    }

    test('creates CombatActivity with SlayerAreaCombatContext', () {
      final area = levelOnlyArea();
      final monster = monsterInArea(area);
      var state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
      );
      state = state.startSlayerAreaCombat(
        area: area,
        monster: monster,
        random: Random(42),
      );

      expect(state.activeActivity, isA<CombatActivity>());
      final activity = state.activeActivity! as CombatActivity;
      expect(activity.context, isA<SlayerAreaCombatContext>());
      final context = activity.context as SlayerAreaCombatContext;
      expect(context.slayerAreaId, area.id);
      expect(context.monsterId, monster.id.localId);
    });

    test('throws StateError when requirements are not met', () {
      // Find an area requiring a slayer level above 1.
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.any(
          (r) => r is SlayerLevelRequirement && r.level > 1,
        ),
      );
      final monsterId = area.monsterIds.first;
      final monster = testRegistries.allActions
          .whereType<CombatAction>()
          .firstWhere((a) => a.id.localId == monsterId);
      // No skills, so requirements won't be met.
      final state = GlobalState.test(testRegistries);

      expect(
        () => state.startSlayerAreaCombat(
          area: area,
          monster: monster,
          random: Random(42),
        ),
        throwsStateError,
      );
    });

    test('throws ArgumentError when monster is not in area', () {
      final area = levelOnlyArea();
      // Find a monster NOT in this area.
      final otherMonster = testRegistries.allActions
          .whereType<CombatAction>()
          .firstWhere((a) => !area.monsterIds.contains(a.id.localId));
      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
      );

      expect(
        () => state.startSlayerAreaCombat(
          area: area,
          monster: otherMonster,
          random: Random(42),
        ),
        throwsArgumentError,
      );
    });

    test('throws StunnedException when player is stunned', () {
      final area = levelOnlyArea();
      final monster = monsterInArea(area);
      final state = GlobalState.test(
        testRegistries,
        skillStates: highCombatSkills,
        stunned: const StunnedState(ticksRemaining: 100),
      );

      expect(
        () => state.startSlayerAreaCombat(
          area: area,
          monster: monster,
          random: Random(42),
        ),
        throwsA(isA<StunnedException>()),
      );
    });
  });

  group('slayerAreaGearChangeError', () {
    test('returns null when not in a slayer area', () {
      final state = GlobalState.test(testRegistries);
      final item = testRegistries.items.all.first;
      expect(state.slayerAreaGearChangeError(item), isNull);
    });

    test('returns null for non-required item in slayer area', () {
      // Use an area with only level requirements (no item requirements).
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) =>
            a.entryRequirements.isNotEmpty &&
            a.entryRequirements.every((r) => r is SlayerLevelRequirement),
      );
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
      final item = testRegistries.items.all.first;
      expect(state.slayerAreaGearChangeError(item), isNull);
    });

    test('returns error message for required item in slayer area', () {
      final area = testRegistries.slayer.areas.all.firstWhere(
        (a) => a.entryRequirements.any((r) => r is SlayerItemRequirement),
        orElse: () => throw StateError('No area with item requirement'),
      );
      final itemReq = area.entryRequirements
          .whereType<SlayerItemRequirement>()
          .first;
      final item = testRegistries.items.byId(itemReq.itemId);
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

      final error = state.slayerAreaGearChangeError(item);
      expect(error, isNotNull);
      expect(error, contains(item.name));
      expect(error, contains(area.name));
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
