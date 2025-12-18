import 'package:logic/logic.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:test/test.dart';

void main() {
  group('buildActionSummaries', () {
    test('returns summaries for all skill actions without inputs', () {
      final state = GlobalState.empty();
      final summaries = buildActionSummaries(state);

      // Should have entries for woodcutting, fishing, mining, thieving
      // but NOT firemaking, cooking, smithing (they require inputs)
      final actionNames = summaries.map((s) => s.actionName).toList();

      expect(actionNames, contains('Normal Tree'));
      expect(actionNames, contains('Raw Shrimp'));
      expect(actionNames, contains('Copper'));
      expect(actionNames, contains('Man'));

      // Should not include input-requiring actions
      expect(actionNames, isNot(contains('Burn Normal Logs')));
      expect(actionNames, isNot(contains('Shrimp'))); // cooking
      expect(actionNames, isNot(contains('Bronze Bar'))); // smithing
    });

    test('marks unlocked actions correctly', () {
      final state = GlobalState.empty().copyWith(
        skillStates: {
          Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
          // Level 20 = 4470 XP
          Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
        },
      );
      final summaries = buildActionSummaries(state);

      final normalTree = summaries.firstWhere(
        (s) => s.actionName == 'Normal Tree',
      );
      final oakTree = summaries.firstWhere((s) => s.actionName == 'Oak Tree');
      final willowTree = summaries.firstWhere(
        (s) => s.actionName == 'Willow Tree',
      );
      final teakTree = summaries.firstWhere((s) => s.actionName == 'Teak Tree');

      // Level 1, 10, 20 should be unlocked at level 20
      expect(normalTree.isUnlocked, isTrue);
      expect(oakTree.isUnlocked, isTrue);
      expect(willowTree.isUnlocked, isTrue);
      // Level 35 should be locked
      expect(teakTree.isUnlocked, isFalse);
    });

    test('calculates positive gold rate for activities with outputs', () {
      final state = GlobalState.empty();
      final summaries = buildActionSummaries(state);

      final normalTree = summaries.firstWhere(
        (s) => s.actionName == 'Normal Tree',
      );
      final copper = summaries.firstWhere((s) => s.actionName == 'Copper');

      expect(normalTree.goldRatePerTick, greaterThan(0));
      expect(copper.goldRatePerTick, greaterThan(0));
    });

    test('calculates positive xp rate for all actions', () {
      final state = GlobalState.empty();
      final summaries = buildActionSummaries(state);

      for (final summary in summaries) {
        expect(
          summary.xpRatePerTick,
          greaterThan(0),
          reason: '${summary.actionName} should have positive XP rate',
        );
      }
    });
  });

  group('enumerateCandidates', () {
    test('returns activity candidates sorted by gold rate', () {
      final state = GlobalState.empty();
      final candidates = enumerateCandidates(state);

      expect(candidates.switchToActivities, isNotEmpty);

      // Verify sorted by gold rate (descending)
      final summaries = buildActionSummaries(state);
      double? lastRate;
      for (final name in candidates.switchToActivities) {
        final summary = summaries.firstWhere((s) => s.actionName == name);
        if (lastRate != null) {
          expect(
            summary.goldRatePerTick,
            lessThanOrEqualTo(lastRate),
            reason: 'Activities should be sorted by gold rate descending',
          );
        }
        lastRate = summary.goldRatePerTick;
      }
    });

    test('respects activity count limit', () {
      final state = GlobalState.empty().copyWith(
        skillStates: {
          Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
          Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.fishing: const SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.mining: const SkillState(xp: 4470, masteryPoolXp: 0),
        },
      );

      final candidates = enumerateCandidates(state, activityCount: 3);
      expect(candidates.switchToActivities.length, lessThanOrEqualTo(3));
    });

    test('returns upgrade candidates', () {
      final state = GlobalState.empty().copyWith(gp: 1000);
      final candidates = enumerateCandidates(state);

      expect(candidates.buyUpgrades, isNotEmpty);
      // Should include axe, fishing rod, pickaxe
      expect(candidates.buyUpgrades, contains(UpgradeType.axe));
      expect(candidates.buyUpgrades, contains(UpgradeType.fishingRod));
      expect(candidates.buyUpgrades, contains(UpgradeType.pickaxe));
    });

    test('includes unaffordable upgrades in candidates', () {
      // With 0 GP, upgrades are unaffordable but should still be candidates
      final state = GlobalState.empty();
      final candidates = enumerateCandidates(state);

      expect(candidates.buyUpgrades, isNotEmpty);
    });

    test('watch list includes locked activities', () {
      final state = GlobalState.empty();
      final candidates = enumerateCandidates(state);

      expect(candidates.watch.lockedActivityNames, isNotEmpty);
      // Should watch for activities that will unlock soon
      // At level 1, Raw Sardine (level 5) should be watched
      expect(candidates.watch.lockedActivityNames, contains('Raw Sardine'));
    });

    test('watch list includes upgrade types', () {
      final state = GlobalState.empty();
      final candidates = enumerateCandidates(state);

      expect(candidates.watch.upgradeTypes, isNotEmpty);
    });

    test('includeSellAll true when inventory > 80% full', () {
      // Create inventory with 17+ unique items (>80% of 20 slots)
      final state = GlobalState.empty().copyWith(
        inventory: Inventory.fromItems([
          ItemStack(itemRegistry.byName('Normal Logs'), count: 10),
          ItemStack(itemRegistry.byName('Oak Logs'), count: 10),
          ItemStack(itemRegistry.byName('Willow Logs'), count: 10),
          ItemStack(itemRegistry.byName('Teak Logs'), count: 10),
          ItemStack(itemRegistry.byName('Raw Shrimp'), count: 10),
          ItemStack(itemRegistry.byName('Raw Lobster'), count: 10),
          ItemStack(itemRegistry.byName('Raw Sardine'), count: 10),
          ItemStack(itemRegistry.byName('Raw Herring'), count: 10),
          ItemStack(itemRegistry.byName('Copper Ore'), count: 10),
          ItemStack(itemRegistry.byName('Tin Ore'), count: 10),
          ItemStack(itemRegistry.byName('Iron Ore'), count: 10),
          ItemStack(itemRegistry.byName('Bronze Bar'), count: 10),
          ItemStack(itemRegistry.byName('Iron Bar'), count: 10),
          ItemStack(itemRegistry.byName('Shrimp'), count: 10),
          ItemStack(itemRegistry.byName('Sardine'), count: 10),
          ItemStack(itemRegistry.byName('Herring'), count: 10),
          ItemStack(itemRegistry.byName('Coal Ore'), count: 10),
        ]),
      );

      final candidates = enumerateCandidates(state);

      expect(candidates.includeSellAll, isTrue);
      expect(candidates.watch.inventory, isTrue);
    });

    test('includeSellAll false when inventory < 80% full', () {
      final state = GlobalState.empty().copyWith(
        inventory: Inventory.fromItems([
          ItemStack(itemRegistry.byName('Normal Logs'), count: 10),
        ]),
      );

      final candidates = enumerateCandidates(state);

      expect(candidates.includeSellAll, isFalse);
      expect(candidates.watch.inventory, isFalse);
    });

    test('is deterministic for same state', () {
      final state = GlobalState.empty().copyWith(gp: 1000);

      final candidates1 = enumerateCandidates(state);
      final candidates2 = enumerateCandidates(state);

      expect(
        candidates1.switchToActivities,
        equals(candidates2.switchToActivities),
      );
      expect(candidates1.buyUpgrades, equals(candidates2.buyUpgrades));
      expect(candidates1.includeSellAll, equals(candidates2.includeSellAll));
      expect(
        candidates1.watch.lockedActivityNames,
        equals(candidates2.watch.lockedActivityNames),
      );
      expect(
        candidates1.watch.upgradeTypes,
        equals(candidates2.watch.upgradeTypes),
      );
    });
  });
}
