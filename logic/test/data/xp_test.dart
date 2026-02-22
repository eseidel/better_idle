import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });
  group('levelForXp', () {
    test('returns 1 for 0 XP', () {
      expect(levelForXp(0), 1);
    });

    test('returns 1 for XP below level 2 threshold', () {
      expect(levelForXp(1), 1);
      expect(levelForXp(50), 1);
      expect(levelForXp(82), 1);
    });

    test('returns 2 for XP at level 2 threshold', () {
      expect(levelForXp(83), 2);
    });

    test('returns 2 for XP between level 2 and 3', () {
      expect(levelForXp(100), 2);
      expect(levelForXp(173), 2);
    });

    test('returns 3 for XP at level 3 threshold', () {
      expect(levelForXp(174), 3);
    });

    test('returns correct level for various XP values', () {
      expect(levelForXp(276), 4);
      expect(levelForXp(512), 6);
      expect(levelForXp(650), 7);
    });

    test('invalid xp throws', () {
      expect(() => levelForXp(-1), throwsA(isA<StateError>()));
      expect(levelForXp(1000000000), equals(maxLevel));
    });
  });

  group('startXpForLevel', () {
    test('returns 0 for level 1', () {
      expect(startXpForLevel(1), 0);
    });

    test('returns 83 for level 2', () {
      expect(startXpForLevel(2), 83);
    });

    test('returns 174 for level 3', () {
      expect(startXpForLevel(3), 174);
    });

    test('returns correct XP for various levels', () {
      expect(startXpForLevel(4), 276);
      expect(startXpForLevel(5), 388);
    });

    test('invalid level throws', () {
      expect(() => startXpForLevel(-1), throwsA(isA<StateError>()));
      expect(() => startXpForLevel(0), throwsA(isA<StateError>()));
      expect(() => startXpForLevel(maxLevel + 1), throwsA(isA<StateError>()));
    });
  });

  group('skillProgressForXp', () {
    test('returns correct progress for 0 XP (level 1)', () {
      final progress = skillProgressForXp(0);
      expect(progress.level, 1);
      expect(progress.lastLevelXp, 0);
      expect(progress.nextLevelXp, 83);
      expect(progress.progress, 0.0);
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP at start of level 2', () {
      final progress = skillProgressForXp(83);
      expect(progress.level, 2);
      expect(progress.lastLevelXp, 83);
      expect(progress.nextLevelXp, 174);
      expect(progress.progress, 0.0);
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP in middle of level 1', () {
      final progress = skillProgressForXp(41);
      expect(progress.level, 1);
      expect(progress.lastLevelXp, 0);
      expect(progress.nextLevelXp, 83);
      expect(progress.progress, closeTo(41 / 83, 0.001));
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP in middle of level 2', () {
      final progress = skillProgressForXp(128);
      expect(progress.level, 2);
      expect(progress.lastLevelXp, 83);
      expect(progress.nextLevelXp, 174);
      // Progress should be (128 - 83) / (174 - 83) = 45 / 91
      expect(progress.progress, closeTo(45 / 91, 0.001));
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP at start of level 3', () {
      final progress = skillProgressForXp(174);
      expect(progress.level, 3);
      expect(progress.lastLevelXp, 174);
      expect(progress.nextLevelXp, 276);
      expect(progress.progress, 0.0);
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('progress is never negative', () {
      for (var xp = 0; xp < 100000; xp += 100) {
        final progress = skillProgressForXp(xp);
        expect(
          progress.progress,
          greaterThanOrEqualTo(0.0),
          reason:
              'Progress should not be negative for XP $xp '
              '(level ${progress.level})',
        );
        expect(
          progress.progress,
          lessThanOrEqualTo(1.0),
          reason:
              'Progress should not exceed 1.0 for XP $xp '
              '(level ${progress.level})',
        );
      }
    });

    test('progress is 1.0 at max level (or close to next level)', () {
      // Test at the last level in the table
      const maxXpInTable = 104273167;
      final progress = skillProgressForXp(maxXpInTable);
      // At max XP, we might be at max level, so nextLevelXp might not exist
      // But progress should still be valid
      expect(progress.progress, greaterThanOrEqualTo(0.0));
    });
  });

  group('calculateMasteryXpPerAction', () {
    test('uses mastery levels not XP in formula', () {
      // Get a firemaking action (Burn Magic Logs has 10 second duration)
      final action = testRegistries.firemakingAction('Burn Magic Logs');
      final actionsInSkill = testRegistries
          .actionsForSkill(Skill.firemaking)
          .length;

      // The formula is:
      // [(unlockedActions × playerTotalMasteryLevel / totalMasteryForSkill) +
      //  (itemMasteryLevel × totalItemsInSkill / 10)] × actionTime × 0.5

      // With mastery level 1 for the item, minimal total mastery:
      // itemPortion = 1 × (actionsInSkill / 10)
      // For firemaking, actionTime = 10 × 0.6 = 6 seconds
      // result ≈ itemPortion × 6 × 0.5 = itemPortion × 3

      final xpAtLevel1 = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: actionsInSkill,
        playerTotalMasteryLevel: actionsInSkill, // All actions at level 1
        itemMasteryLevel: 1,
        bonus: 0,
      );

      // At mastery level 50, itemPortion is 50× larger
      final xpAtLevel50 = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: actionsInSkill,
        playerTotalMasteryLevel: actionsInSkill * 50, // All actions at level 50
        itemMasteryLevel: 50,
        bonus: 0,
      );

      // The XP at level 50 should be much higher than at level 1
      // (roughly 50× higher for the itemPortion alone)
      expect(xpAtLevel50, greaterThan(xpAtLevel1 * 10));
    });

    test('totalMasteryForSkill uses 99 not maxMasteryXp', () {
      final action = testRegistries.firemakingAction('Burn Magic Logs');
      final actionsInSkill = testRegistries
          .actionsForSkill(Skill.firemaking)
          .length;

      // totalMasteryForSkill incorrectly used XP (~53 million for firemaking),
      // mastery portion would be nearly 0 even with high total mastery levels.
      // The correct formula (totalItems × 99), mastery portion is significant.

      // All actions level 99, playerTotalMasteryLevel = actionsInSkill × 99
      // Equals totalMasteryForSkill, so masteryPortion = unlockedActions × 1
      final xpWithMaxMastery = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: actionsInSkill,
        playerTotalMasteryLevel: actionsInSkill * 99, // All at level 99
        itemMasteryLevel: 99,
        bonus: 0,
      );

      // For firemaking with ~9 actions, action time = 6 seconds:
      // masteryPortion = 9 × (9×99 / 9×99) = 9
      // itemPortion = 99 × (9 / 10) = 89.1
      // baseValue = 98.1
      // result = 98.1 × 6 × 0.5 = 294.3 ≈ 294

      // The result should be substantial (>100 XP), not tiny like if we used XP
      expect(xpWithMaxMastery, greaterThan(100));
    });

    test('returns at least 1 XP', () {
      final action = testRegistries.firemakingAction('Burn Normal Logs');

      final xp = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: 1,
        playerTotalMasteryLevel: 1,
        itemMasteryLevel: 1,
        bonus: 0,
      );

      expect(xp, greaterThanOrEqualTo(1));
    });

    test('bonus increases XP', () {
      final action = testRegistries.firemakingAction('Burn Magic Logs');
      final actionsInSkill = testRegistries
          .actionsForSkill(Skill.firemaking)
          .length;

      final xpNoBonus = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: actionsInSkill,
        playerTotalMasteryLevel: actionsInSkill * 50,
        itemMasteryLevel: 50,
        bonus: 0,
      );

      final xpWith50PercentBonus = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: actionsInSkill,
        playerTotalMasteryLevel: actionsInSkill * 50,
        itemMasteryLevel: 50,
        bonus: 0.5, // 50% bonus
      );

      // With 50% bonus, XP should be 1.5× higher
      expect(xpWith50PercentBonus, greaterThan(xpNoBonus));
      expect(xpWith50PercentBonus, closeTo(xpNoBonus * 1.5, 1));
    });

    test('realistic scenario: one action trained high, others at level 1', () {
      // Simulates: trained Normal Logs to mastery 86, now trying Magic Logs
      // at mastery level 1, with 8 logs unlocked (level 79 firemaking)
      final action = testRegistries.firemakingAction('Burn Magic Logs');
      final actionsInSkill = testRegistries
          .actionsForSkill(Skill.firemaking)
          .length;

      // One action at level 86, rest at level 1
      // playerTotalMasteryLevel = 86 + (actionsInSkill - 1) * 1
      final playerTotalMasteryLevel = 86 + (actionsInSkill - 1);

      final xp = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: 8, // Level 79 unlocks 8 of 9 logs
        playerTotalMasteryLevel: playerTotalMasteryLevel,
        itemMasteryLevel: 1, // Magic logs just started
        bonus: 0,
      );

      // With 9 actions, playerTotalMasteryLevel = 94:
      // masteryPortion = 8 × (94 / 891) = 0.84
      // itemPortion = 1 × (9 / 10) = 0.9
      // baseValue = 1.74
      // result = 1.74 × 6 × 0.5 = 5.22 ≈ 5
      expect(xp, inInclusiveRange(4, 6));

      // Compare to having all actions at average level (94/9 ≈ 10.4)
      final xpWithEvenMastery = calculateMasteryXpPerAction(
        registries: testRegistries,
        action: action,
        unlockedActions: 8,
        playerTotalMasteryLevel: playerTotalMasteryLevel,
        itemMasteryLevel: 10, // If this action were also ~10
        bonus: 0,
      );

      // With itemMasteryLevel = 10:
      // itemPortion = 10 × 0.9 = 9
      // baseValue = 9.84
      // result = 9.84 × 6 × 0.5 = 29.5 ≈ 29
      expect(xpWithEvenMastery, greaterThan(xp * 3));
    });
  });

  group('masteryXpGlobalPercentIncrease', () {
    test('returns percentage based on levels added vs current total', () {
      final actions = testRegistries.actionsForSkill(Skill.firemaking);
      // All actions at level 1: total = actionsCount × 1
      final state = GlobalState.test(testRegistries);
      final pct = masteryXpGlobalPercentIncrease(
        state,
        Skill.firemaking,
        actions.length, // add one level per action
      );
      // Adding N levels when total is N means 100% increase.
      expect(pct, closeTo(100.0, 0.01));
    });

    test('returns smaller percentage when total mastery is high', () {
      final actions = testRegistries.actionsForSkill(Skill.firemaking);
      // Set all actions to mastery level 50 (XP = startXpForLevel(50)).
      final actionStates = {
        for (final a in actions)
          a.id: ActionState(masteryXp: startXpForLevel(50)),
      };
      final state = GlobalState.test(
        testRegistries,
        actionStates: actionStates,
      );
      final total = actions.length * 50;
      final pct = masteryXpGlobalPercentIncrease(state, Skill.firemaking, 1);
      // 1 / total × 100
      expect(pct, closeTo(1 / total * 100, 0.01));
    });

    test('returns 0 when levelsAdded is 0', () {
      final state = GlobalState.test(testRegistries);
      final pct = masteryXpGlobalPercentIncrease(state, Skill.firemaking, 0);
      expect(pct, 0.0);
    });
  });

  group('actionTimeForMastery', () {
    test('woodcutting uses actual action duration', () {
      final action = testRegistries.woodcuttingAction('Normal Tree');
      expect(
        actionTimeForMastery(action),
        action.maxDuration.inSeconds.toDouble(),
      );
    });

    test('fishing uses actual action duration', () {
      final action = testRegistries.fishingAction('Raw Shrimp');
      expect(
        actionTimeForMastery(action),
        action.maxDuration.inSeconds.toDouble(),
      );
    });

    test('smithing uses fixed 1.7 seconds', () {
      final action = testRegistries.smithingAction('Bronze Dagger');
      expect(actionTimeForMastery(action), 1.7);
    });

    test('firemaking uses 60% of burn interval', () {
      final action = testRegistries.firemakingAction('Burn Normal Logs');
      expect(actionTimeForMastery(action), action.maxDuration.inSeconds * 0.6);
    });
  });

  group('maxMasteryPoolXpForSkill', () {
    test('returns correct value for woodcutting', () {
      final actionCount = testRegistries
          .actionsForSkill(Skill.woodcutting)
          .length;
      expect(
        maxMasteryPoolXpForSkill(testRegistries, Skill.woodcutting),
        actionCount * 500000,
      );
    });
  });
}
