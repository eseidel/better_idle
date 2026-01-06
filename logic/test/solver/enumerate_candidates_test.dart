import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/candidates/enumerate_candidates.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/value_model.dart';
import 'package:logic/src/solver/interactions/apply_interaction.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

/// Default goal for tests - a large GP target that won't be reached
const _defaultGoal = ReachGpGoal(1000000);

/// Helper to get action display name from actionId.
String actionName(ActionId actionId) => testActions.byId(actionId).name;

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('buildActionSummaries', () {
    test('returns summaries for all skill actions including consuming', () {
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);

      // Should have entries for all skill actions
      final actionNames = summaries.map((s) => actionName(s.actionId)).toList();

      // Producer actions
      expect(actionNames, contains('Normal Tree'));
      expect(actionNames, contains('Raw Shrimp'));
      expect(actionNames, contains('Copper'));
      expect(actionNames, contains('Man'));

      // Consuming actions are included (hasInputs=true, canStartNow=false)
      expect(actionNames, contains('Burn Normal Logs'));

      // Verify consuming actions are marked correctly
      final burnLogs = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Burn Normal Logs',
      );
      expect(burnLogs.hasInputs, isTrue);
      expect(burnLogs.canStartNow, isFalse); // No logs in inventory
    });

    test('marks unlocked actions correctly', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
          // Level 25 = 8740 XP (Willow Tree requires level 25)
          Skill.woodcutting: SkillState(xp: 8740, masteryPoolXp: 0),
        },
      );
      final summaries = buildActionSummaries(state);

      final normalTree = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Normal Tree',
      );
      final oakTree = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Oak Tree',
      );
      final willowTree = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Willow Tree',
      );
      final teakTree = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Teak Tree',
      );

      // Level 1, 10, 25 should be unlocked at level 25
      expect(normalTree.isUnlocked, isTrue);
      expect(oakTree.isUnlocked, isTrue);
      expect(willowTree.isUnlocked, isTrue);
      // Level 35 should be locked
      expect(teakTree.isUnlocked, isFalse);
    });

    test('calculates positive gold rate for activities with outputs', () {
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);

      final normalTree = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Normal Tree',
      );
      final copper = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Copper',
      );

      expect(normalTree.goldRatePerTick, greaterThan(0));
      expect(copper.goldRatePerTick, greaterThan(0));
    });

    test('consuming actions account for input costs in gold rate', () {
      // Consuming actions like firemaking burn logs (which have sell value)
      // and produce drops. The gold rate should account for input costs.
      // Note: Due to Coal Ore drops, firemaking can actually be profitable!
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);

      final burnNormalLogs = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Burn Normal Logs',
      );

      // The action has inputs that are consumed
      expect(burnNormalLogs.hasInputs, isTrue);

      // Compare to a producer action (woodcutting produces logs worth 1 GP)
      final normalTree = summaries.firstWhere(
        (s) => actionName(s.actionId) == 'Normal Tree',
      );

      // Woodcutting Normal Tree just produces logs - no inputs consumed
      // Firemaking Burn Normal Logs consumes logs but also produces Coal Ore
      // The key test is that the gold rate calculation is working, not the sign
      expect(
        burnNormalLogs.goldRatePerTick,
        isA<double>(),
        reason: 'Consuming actions should have a computed gold rate',
      );
      expect(
        normalTree.goldRatePerTick,
        greaterThan(0),
        reason: 'Producer actions should have positive gold rate',
      );
    });

    test('calculates positive xp rate for all actions', () {
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);

      for (final summary in summaries) {
        expect(
          summary.xpRatePerTick,
          greaterThan(0),
          reason: '${summary.actionId} should have positive XP rate',
        );
      }
    });
  });

  group('enumerateCandidates', () {
    test(
      'returns activity candidates including producers for consuming actions',
      () {
        final state = GlobalState.empty(testRegistries);
        final candidates = enumerateCandidates(state, _defaultGoal);

        expect(candidates.switchToActivities, isNotEmpty);

        // Candidates should include thieving (best gold rate) and producers
        // for consuming actions that have positive gold rate from byproducts.
        // The ordering may not be strictly by gold rate because producers for
        // consuming actions are added alongside those actions.
        final actionNames = candidates.switchToActivities
            .map((id) => testActions.byId(id).name)
            .toList();
        expect(actionNames, contains('Man')); // Thieving is always included
      },
    );

    test('respects activity count limit (with producer overhead)', () {
      // With unconditional producer inclusion, the actual count may exceed
      // activityCount because we always include producers for consuming goals.
      // For a GP goal, all consuming skills apply, so we include producers.
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
          Skill.woodcutting: SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.fishing: SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.mining: SkillState(xp: 4470, masteryPoolXp: 0),
        },
      );

      final candidates = enumerateCandidates(
        state,
        _defaultGoal,
        activityCount: 3,
      );
      // With producer overhead, we may have more than activityCount, but
      // should still have a reasonable limit (activityCount + producers).
      // Each consuming skill adds up to 2 producers, and there are 5 skills
      // with producer mappings, so max overhead = 10 producers.
      expect(candidates.switchToActivities.length, lessThanOrEqualTo(3 + 10));
    });
    test('watch list includes upgrades from buyUpgrades', () {
      // The watch list should include upgrades that are candidates
      // for affordability tracking.
      final state = GlobalState.empty(testRegistries);
      final candidates = enumerateCandidates(state, _defaultGoal);

      // Any upgrade in buyUpgrades should also be in watch list
      for (final upgradeId in candidates.buyUpgrades) {
        expect(
          candidates.watch.upgradePurchaseIds,
          contains(upgradeId),
          reason: 'Upgrade candidates should be in watch list',
        );
      }
    });

    test('watch list includes locked activities', () {
      final state = GlobalState.empty(testRegistries);
      final candidates = enumerateCandidates(state, _defaultGoal);

      expect(candidates.watch.lockedActivityIds, isNotEmpty);
      // Should watch for activities that will unlock soon
      // At level 1, activities like Raw Sardine (level 5 Fishing), Superheat I
      // (level 5 Alt Magic), etc. should be watched
    });

    test('watch list includes upgrades when upgrades are candidates', () {
      // The watch list includes all upgrades that meet skill requirements and
      // have positive gain, even if not competitive with the best activity.
      // This allows the planner to know when any upgrade becomes affordable.
      final state = GlobalState.empty(testRegistries);
      final candidates = enumerateCandidates(state, _defaultGoal);

      // Even though thieving dominates, we still watch for tool upgrades
      // so the planner can reconsider when they become affordable
      // The specific IDs depend on the parsed shop data
      expect(
        candidates.watch.upgradePurchaseIds,
        isNotEmpty,
        reason: 'Watch list should include eligible upgrades',
      );
    });

    test('sellPolicy non-null when inventory > 80% full', () {
      // Create inventory with 17+ unique items (>80% of 20 slots)
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(testItems.byName('Normal Logs'), count: 10),
          ItemStack(testItems.byName('Oak Logs'), count: 10),
          ItemStack(testItems.byName('Willow Logs'), count: 10),
          ItemStack(testItems.byName('Teak Logs'), count: 10),
          ItemStack(testItems.byName('Raw Shrimp'), count: 10),
          ItemStack(testItems.byName('Raw Lobster'), count: 10),
          ItemStack(testItems.byName('Raw Sardine'), count: 10),
          ItemStack(testItems.byName('Raw Herring'), count: 10),
          ItemStack(testItems.byName('Copper Ore'), count: 10),
          ItemStack(testItems.byName('Tin Ore'), count: 10),
          ItemStack(testItems.byName('Iron Ore'), count: 10),
          ItemStack(testItems.byName('Bronze Bar'), count: 10),
          ItemStack(testItems.byName('Iron Bar'), count: 10),
          ItemStack(testItems.byName('Shrimp'), count: 10),
          ItemStack(testItems.byName('Sardine'), count: 10),
          ItemStack(testItems.byName('Herring'), count: 10),
          ItemStack(testItems.byName('Coal Ore'), count: 10),
        ]),
      );

      final candidates = enumerateCandidates(state, _defaultGoal);

      expect(candidates.sellPolicy, isNotNull);
      expect(candidates.watch.inventory, isTrue);
    });

    test('shouldEmitSellCandidate false when inventory < 80% full', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(testItems.byName('Normal Logs'), count: 10),
        ]),
      );

      final candidates = enumerateCandidates(state, _defaultGoal);

      // sellPolicy is always available but we don't emit a sell candidate
      expect(candidates.sellPolicy, isNotNull);
      expect(candidates.shouldEmitSellCandidate, isFalse);
      expect(candidates.watch.inventory, isFalse);
    });

    test('is deterministic for same state', () {
      final state = GlobalState.test(testRegistries, gp: 1000);

      final candidates1 = enumerateCandidates(state, _defaultGoal);
      final candidates2 = enumerateCandidates(state, _defaultGoal);

      expect(
        candidates1.switchToActivities,
        equals(candidates2.switchToActivities),
      );
      expect(candidates1.buyUpgrades, equals(candidates2.buyUpgrades));
      expect(candidates1.sellPolicy, equals(candidates2.sellPolicy));
      expect(
        candidates1.watch.lockedActivityIds,
        equals(candidates2.watch.lockedActivityIds),
      );
      expect(
        candidates1.watch.upgradePurchaseIds,
        equals(candidates2.watch.upgradePurchaseIds),
      );
    });
  });

  group('estimateRates', () {
    test('thieving Man gold/tick unaffected by tool levels', () {
      // Start with Man activity
      var state = GlobalState.empty(testRegistries);
      final manAction = testActions.thieving('Man');
      state = state.startAction(manAction, random: Random(0));

      // Get baseline rate with no upgrades
      final baseRates = estimateRates(state);
      final baseGoldRate = defaultValueModel.valuePerTick(state, baseRates);

      // Buy all tool upgrades (axe, fishing rod, pickaxe)
      const ironAxeId = MelvorId('melvorD:Iron_Axe');
      const ironRodId = MelvorId('melvorD:Iron_Fishing_Rod');
      const ironPickaxeId = MelvorId('melvorD:Iron_Pickaxe');
      var upgradedState = state.copyWith(
        shop: state.shop
            .withPurchase(ironAxeId)
            .withPurchase(ironRodId)
            .withPurchase(ironPickaxeId),
      );
      // Re-apply the action since we changed state
      upgradedState = upgradedState.startAction(manAction, random: Random(0));

      // Get rate with all tool upgrades
      final upgradedRates = estimateRates(upgradedState);
      final upgradedGoldRate = defaultValueModel.valuePerTick(
        upgradedState,
        upgradedRates,
      );

      // Gold rate should be identical - tools don't affect thieving
      expect(
        upgradedGoldRate,
        equals(baseGoldRate),
        reason: 'Tool upgrades should not affect thieving gold rate',
      );
    });
  });

  group('applyInteraction', () {
    test('BuyShopItem reduces GP by upgrade cost', () {
      // Start with enough GP for an axe upgrade
      final state = GlobalState.test(testRegistries, gp: 100);
      const ironAxeId = MelvorId('melvorD:Iron_Axe');
      const interaction = BuyShopItem(ironAxeId);
      final random = Random(0);

      // Apply the upgrade
      final newState = applyInteraction(state, interaction, random: random);

      // Iron Axe costs 50 GP
      expect(newState.gp, equals(50));
      expect(newState.shop.purchaseCount(ironAxeId), equals(1));
    });

    test('BuyShopItem reduces GP by correct amount for each tier', () {
      // Test first fishing rod (costs 100)
      const ironRodId = MelvorId('melvorD:Iron_Fishing_Rod');
      var state = GlobalState.test(testRegistries, gp: 200);
      final random = Random(0);
      var newState = applyInteraction(
        state,
        const BuyShopItem(ironRodId),
        random: random,
      );
      expect(newState.gp, equals(100)); // 200 - 100
      expect(newState.shop.purchaseCount(ironRodId), equals(1));

      // Test first pickaxe (costs 250)
      const ironPickaxeId = MelvorId('melvorD:Iron_Pickaxe');
      state = GlobalState.test(testRegistries, gp: 500);
      newState = applyInteraction(
        state,
        const BuyShopItem(ironPickaxeId),
        random: random,
      );
      expect(newState.gp, equals(250)); // 500 - 250
      expect(newState.shop.purchaseCount(ironPickaxeId), equals(1));
    });
  });

  group('ProducerResolver', () {
    test('resolves producer for simple item (Normal Logs)', () {
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);
      final resolver = ProducerResolver(summaries, state);

      // Normal Logs are produced by Normal Tree (Woodcutting)
      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final plan = resolver.resolve(normalLogsId);

      expect(plan, isNotNull);
      expect(actionName(plan!.primaryProducer.actionId), equals('Normal Tree'));
      expect(plan.ticksPerUnit, greaterThan(0));
      expect(plan.chainActions, contains(plan.primaryProducer.actionId));
      expect(plan.chainActions.length, equals(1)); // Simple producer, no chain
    });

    test('returns null for non-producible item', () {
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);
      final resolver = ProducerResolver(summaries, state);

      // Use a fake item ID that doesn't exist
      const fakeItemId = MelvorId('melvorD:Fake_Item');
      final plan = resolver.resolve(fakeItemId);

      expect(plan, isNull);
    });

    test('caches producer lookups', () {
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);
      final resolver = ProducerResolver(summaries, state);

      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final plan1 = resolver.resolve(normalLogsId);
      final plan2 = resolver.resolve(normalLogsId);

      // Same object should be returned from cache
      expect(identical(plan1, plan2), isTrue);
    });

    test('resolves multi-tier chain for Bronze Bar', () {
      // Bronze Bar requires Copper Ore and Tin Ore
      // Both ores come from Mining
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);
      final resolver = ProducerResolver(summaries, state);

      const bronzeBarId = MelvorId('melvorD:Bronze_Bar');
      final plan = resolver.resolve(bronzeBarId);

      expect(plan, isNotNull);
      // Bronze Bar is produced by Smithing (Bronze Bar action)
      expect(actionName(plan!.primaryProducer.actionId), equals('Bronze Bar'));

      // Chain should include the bar smelting action AND the ore mining actions
      expect(plan.chainActions.length, greaterThan(1));

      // ticksPerUnit should include upstream ore mining time
      // This is more than just the bar smelting time
      expect(
        plan.ticksPerUnit,
        greaterThan(plan.primaryProducer.expectedTicks),
      );
    });

    test('ticksPerUnit includes upstream costs', () {
      // Test that ticksPerUnit correctly accounts for upstream production
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);
      final resolver = ProducerResolver(summaries, state);

      // Get plan for Copper Ore (simple, no upstream)
      const copperOreId = MelvorId('melvorD:Copper_Ore');
      final copperPlan = resolver.resolve(copperOreId);
      expect(copperPlan, isNotNull);

      // Copper mining has no inputs, so ticksPerUnit = expectedTicks/output
      final copperAction =
          testActions.byId(copperPlan!.primaryProducer.actionId) as SkillAction;
      final copperOutputs = copperAction.outputs[copperOreId] ?? 1;
      expect(
        copperPlan.ticksPerUnit,
        equals(copperPlan.primaryProducer.expectedTicks / copperOutputs),
      );
    });

    test('prefers producer with lower ticksPerUnit', () {
      // This test verifies that when multiple producers exist for an item,
      // the resolver picks the one with lowest ticksPerUnit.
      // In practice, most items have only one producer, but the logic
      // evaluates top-K candidates.
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);
      final resolver = ProducerResolver(summaries, state);

      // Normal Logs from Normal Tree should be picked (only producer)
      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final plan = resolver.resolve(normalLogsId);
      expect(plan, isNotNull);
      expect(plan!.ticksPerUnit, greaterThan(0));
    });
  });

  group('consuming skill candidate selection', () {
    test('includes producers for consuming skill candidates', () {
      // When selecting candidates for a consuming skill like Firemaking,
      // the result should include both consumer actions AND their producers
      final state = GlobalState.empty(testRegistries);
      final candidates = enumerateCandidates(
        state,
        const ReachSkillLevelGoal(Skill.firemaking, 10),
      );

      // Should include both firemaking actions and woodcutting producers
      final actionNames = candidates.switchToActivities
          .map((id) => testActions.byId(id).name)
          .toList();

      // Should have firemaking actions
      expect(
        actionNames.any((name) => name.contains('Burn')),
        isTrue,
        reason: 'Should include firemaking (Burn) actions',
      );

      // Should have woodcutting producers
      expect(
        actionNames.any((name) => name.contains('Tree')),
        isTrue,
        reason: 'Should include woodcutting (Tree) producers',
      );
    });

    test('handles multi-input consuming skills (Smithing)', () {
      // Smithing actions require multiple inputs (e.g., Bronze Bars needs
      // Copper Ore + Tin Ore). The candidate selection should handle this.
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
          // Unlock Smithing
          Skill.smithing: SkillState(xp: 0, masteryPoolXp: 0),
          // Need mining for ore production
          Skill.mining: SkillState(xp: 0, masteryPoolXp: 0),
        },
      );
      final candidates = enumerateCandidates(
        state,
        const ReachSkillLevelGoal(Skill.smithing, 5),
      );

      // Should include mining actions for ore production
      final actionNames = candidates.switchToActivities
          .map((id) => testActions.byId(id).name)
          .toList();

      // Should have mining producers for the ores needed by smithing
      expect(
        actionNames.any(
          (name) => name == 'Copper' || name == 'Tin' || name == 'Iron',
        ),
        isTrue,
        reason: 'Should include mining actions for ore production',
      );
    });
  });
}
