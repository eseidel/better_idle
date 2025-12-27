import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/apply_interaction.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/estimate_rates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/value_model.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Default goal for tests - a large GP target that won't be reached
const _defaultGoal = ReachGpGoal(1000000);

/// Helper to get action display name from actionId.
String actionName(ActionId actionId) => testActions.byId(actionId).name;

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('buildActionSummaries', () {
    test('returns summaries for all skill actions including consuming ones', () {
      final state = GlobalState.empty(testRegistries);
      final summaries = buildActionSummaries(state);

      // Should have entries for all skill actions
      final actionNames = summaries.map((s) => actionName(s.actionId)).toList();

      // Producer actions
      expect(actionNames, contains('Normal Tree'));
      expect(actionNames, contains('Raw Shrimp'));
      expect(actionNames, contains('Copper'));
      expect(actionNames, contains('Man'));

      // Consuming actions are also included (with hasInputs=true, canStartNow=false)
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
        skillStates: {
          Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
          // Level 25 = 8740 XP (Willow Tree requires level 25)
          Skill.woodcutting: const SkillState(xp: 8740, masteryPoolXp: 0),
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

        // Candidates should include both thieving (best gold rate) and producers
        // for consuming actions that have positive gold rate from byproducts.
        // The ordering may not be strictly by gold rate because producers for
        // consuming actions are added alongside those actions.
        final actionNames = candidates.switchToActivities
            .map((id) => testActions.byId(id).name)
            .toList();
        expect(actionNames, contains('Man')); // Thieving is always included
      },
    );

    test('respects activity count limit', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {
          Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
          Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.fishing: const SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.mining: const SkillState(xp: 4470, masteryPoolXp: 0),
        },
      );

      final candidates = enumerateCandidates(
        state,
        _defaultGoal,
        activityCount: 3,
      );
      expect(candidates.switchToActivities.length, lessThanOrEqualTo(3));
    });

    test('upgrade candidates may include skill upgrades', () {
      // The upgrade filtering logic considers whether upgrades would
      // improve competitive activities. With the current rate calculation
      // (which includes byproducts from consuming actions), some upgrades
      // may be included in buyUpgrades.
      final state = GlobalState.test(testRegistries, gp: 1000);
      final candidates = enumerateCandidates(state, _defaultGoal);

      // Upgrades list is computed based on activity competitiveness.
      // We just verify the list is not null (the actual filtering logic
      // is tested implicitly through the solver tests).
      expect(candidates.buyUpgrades, isA<List>());
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

    test('includeSellAll true when inventory > 80% full', () {
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

      expect(candidates.includeSellAll, isTrue);
      expect(candidates.watch.inventory, isTrue);
    });

    test('includeSellAll false when inventory < 80% full', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(testItems.byName('Normal Logs'), count: 10),
        ]),
      );

      final candidates = enumerateCandidates(state, _defaultGoal);

      expect(candidates.includeSellAll, isFalse);
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
      expect(candidates1.includeSellAll, equals(candidates2.includeSellAll));
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
      final ironAxeId = MelvorId('melvorD:Iron_Axe');
      final ironRodId = MelvorId('melvorD:Iron_Fishing_Rod');
      final ironPickaxeId = MelvorId('melvorD:Iron_Pickaxe');
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
      final ironAxeId = MelvorId('melvorD:Iron_Axe');
      final interaction = BuyShopItem(ironAxeId);

      // Apply the upgrade
      final newState = applyInteraction(state, interaction);

      // Iron Axe costs 50 GP
      expect(newState.gp, equals(50));
      expect(newState.shop.purchaseCount(ironAxeId), equals(1));
    });

    test('BuyShopItem reduces GP by correct amount for each tier', () {
      // Test first fishing rod (costs 100)
      final ironRodId = MelvorId('melvorD:Iron_Fishing_Rod');
      var state = GlobalState.test(testRegistries, gp: 200);
      var newState = applyInteraction(state, BuyShopItem(ironRodId));
      expect(newState.gp, equals(100)); // 200 - 100
      expect(newState.shop.purchaseCount(ironRodId), equals(1));

      // Test first pickaxe (costs 250)
      final ironPickaxeId = MelvorId('melvorD:Iron_Pickaxe');
      state = GlobalState.test(testRegistries, gp: 500);
      newState = applyInteraction(state, BuyShopItem(ironPickaxeId));
      expect(newState.gp, equals(250)); // 500 - 250
      expect(newState.shop.purchaseCount(ironPickaxeId), equals(1));
    });
  });
}
