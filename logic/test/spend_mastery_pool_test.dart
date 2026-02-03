import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('spendMasteryPoolXp', () {
    test('raises action mastery to next level', () {
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      var state = GlobalState.empty(testRegistries);

      // Give pool XP to spend.
      state = state.addSkillMasteryXp(Skill.woodcutting, 100000);

      // Action starts at mastery level 1 (0 XP). Cost to level 2 is 83 XP.
      final cost = state.masteryLevelUpCost(normalTree.id);
      expect(cost, 83);

      final poolBefore = state.skillState(Skill.woodcutting).masteryPoolXp;
      final newState = state.spendMasteryPoolXp(
        Skill.woodcutting,
        normalTree.id,
      );
      expect(newState, isNotNull);

      // Pool decreased by cost.
      expect(
        newState!.skillState(Skill.woodcutting).masteryPoolXp,
        poolBefore - 83,
      );
      // Action mastery is now level 2.
      expect(newState.actionState(normalTree.id).masteryLevel, 2);
    });

    test('returns null when pool is insufficient', () {
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      var state = GlobalState.empty(testRegistries);

      // Give only 10 pool XP (need 83).
      state = state.addSkillMasteryXp(Skill.woodcutting, 10);

      final result = state.spendMasteryPoolXp(Skill.woodcutting, normalTree.id);
      expect(result, isNull);
    });

    test('returns null when already at max mastery', () {
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      var state = GlobalState.empty(testRegistries);

      // Set action mastery to max (level 99).
      state = state.addActionMasteryXp(normalTree.id, maxMasteryXp);
      state = state.addSkillMasteryXp(Skill.woodcutting, 100000);

      expect(state.masteryLevelUpCost(normalTree.id), isNull);
      final result = state.spendMasteryPoolXp(Skill.woodcutting, normalTree.id);
      expect(result, isNull);
    });
  });

  group('masteryLevelUpCostForLevels', () {
    test('calculates cost for multiple levels', () {
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      final state = GlobalState.empty(testRegistries);

      // Action starts at level 1. Cost to level 2 is 83, to level 3 is 174.
      final cost1 = state.masteryLevelUpCostForLevels(normalTree.id, 1);
      expect(cost1, 83); // Same as masteryLevelUpCost

      final cost2 = state.masteryLevelUpCostForLevels(normalTree.id, 2);
      expect(cost2, 174); // XP needed to reach level 3

      final cost5 = state.masteryLevelUpCostForLevels(normalTree.id, 5);
      expect(cost5, 512); // XP needed to reach level 6
    });

    test('returns null for zero or negative levels', () {
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      final state = GlobalState.empty(testRegistries);

      expect(state.masteryLevelUpCostForLevels(normalTree.id, 0), isNull);
      expect(state.masteryLevelUpCostForLevels(normalTree.id, -1), isNull);
    });

    test('returns null when already at max mastery', () {
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      var state = GlobalState.empty(testRegistries);

      // Set action mastery to max (level 99).
      state = state.addActionMasteryXp(normalTree.id, maxMasteryXp);

      expect(state.masteryLevelUpCostForLevels(normalTree.id, 1), isNull);
    });

    test('clamps to max level 99', () {
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      var state = GlobalState.empty(testRegistries);

      // Set action mastery to level 98 (one below max).
      state = state.addActionMasteryXp(normalTree.id, startXpForLevel(98));

      // Requesting 5 levels should only give cost for 1 level (to 99).
      final cost = state.masteryLevelUpCostForLevels(normalTree.id, 5);
      final costFor1 = state.masteryLevelUpCost(normalTree.id);
      expect(cost, costFor1);
    });
  });

  group('masteryPoolCheckpointCrossed', () {
    test('detects crossing a checkpoint', () {
      var state = GlobalState.empty(testRegistries);
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );

      // Set pool to exactly 25% of max.
      final poolXp = (maxPoolXp * 0.25).toInt();
      state = state.addSkillMasteryXp(Skill.woodcutting, poolXp);

      // Spending 1 XP would cross the 25% checkpoint.
      final crossed = state.masteryPoolCheckpointCrossed(Skill.woodcutting, 1);
      expect(crossed, 25);
    });

    test('returns null when no checkpoint crossed', () {
      var state = GlobalState.empty(testRegistries);
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );

      // Set pool to 60% of max (between 50% and 95% checkpoints).
      final poolXp = (maxPoolXp * 0.60).toInt();
      state = state.addSkillMasteryXp(Skill.woodcutting, poolXp);

      // Spending 1 XP stays well above 50%, no crossing.
      final crossed = state.masteryPoolCheckpointCrossed(Skill.woodcutting, 1);
      expect(crossed, isNull);
    });
  });
}
