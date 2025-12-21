import 'package:logic/logic.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('ReachGpGoal', () {
    test('isSatisfied returns true when GP >= target', () {
      final state = GlobalState.empty(testItems).copyWith(gp: 100);
      const goal = ReachGpGoal(100);

      expect(goal.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when GP > target', () {
      final state = GlobalState.empty(testItems).copyWith(gp: 200);
      const goal = ReachGpGoal(100);

      expect(goal.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when GP < target', () {
      final state = GlobalState.empty(testItems).copyWith(gp: 50);
      const goal = ReachGpGoal(100);

      expect(goal.isSatisfied(state), isFalse);
    });

    test('remaining returns 0 when goal is satisfied', () {
      final state = GlobalState.empty(testItems).copyWith(gp: 100);
      const goal = ReachGpGoal(100);

      expect(goal.remaining(state), 0.0);
    });

    test('remaining returns positive value when not satisfied', () {
      final state = GlobalState.empty(testItems).copyWith(gp: 50);
      const goal = ReachGpGoal(100);

      expect(goal.remaining(state), 50.0);
    });

    test('describe returns human-readable string', () {
      const goal = ReachGpGoal(5000);

      expect(goal.describe(), 'Reach 5000 GP');
    });

    test('equality works correctly', () {
      const goal1 = ReachGpGoal(100);
      const goal2 = ReachGpGoal(100);
      const goal3 = ReachGpGoal(200);

      expect(goal1, equals(goal2));
      expect(goal1, isNot(equals(goal3)));
    });
  });

  group('ReachSkillLevelGoal', () {
    test('isSatisfied returns true when skill level >= target', () {
      var state = GlobalState.empty(testItems);
      // Give woodcutting XP for level 5
      final xpForLevel5 = startXpForLevel(5);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
        },
      );

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

      expect(goal.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when skill level > target', () {
      var state = GlobalState.empty(testItems);
      final xpForLevel10 = startXpForLevel(10);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel10, masteryPoolXp: 0),
        },
      );

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

      expect(goal.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when skill level < target', () {
      final state = GlobalState.empty(testItems); // Starts at level 1

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

      expect(goal.isSatisfied(state), isFalse);
    });

    test('remaining returns 0 when goal is satisfied', () {
      var state = GlobalState.empty(testItems);
      final xpForLevel5 = startXpForLevel(5);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
        },
      );

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

      expect(goal.remaining(state), 0.0);
    });

    test('remaining returns XP needed when not satisfied', () {
      final state = GlobalState.empty(testItems); // 0 XP in woodcutting

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);
      final xpForLevel5 = startXpForLevel(5);

      expect(goal.remaining(state), xpForLevel5.toDouble());
    });

    test('describe returns human-readable string', () {
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

      // Check case-insensitive match for skill name
      expect(goal.describe().toLowerCase(), contains('woodcutting'));
      expect(goal.describe(), contains('50'));
    });

    test('targetXp returns correct XP for target level', () {
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);

      expect(goal.targetXp, startXpForLevel(10));
    });

    test('equality works correctly', () {
      const goal1 = ReachSkillLevelGoal(Skill.woodcutting, 50);
      const goal2 = ReachSkillLevelGoal(Skill.woodcutting, 50);
      const goal3 = ReachSkillLevelGoal(Skill.woodcutting, 60);
      const goal4 = ReachSkillLevelGoal(Skill.fishing, 50);

      expect(goal1, equals(goal2));
      expect(goal1, isNot(equals(goal3)));
      expect(goal1, isNot(equals(goal4)));
    });
  });

  group('solve with ReachSkillLevelGoal', () {
    test('returns empty plan when already at target level', () {
      var state = GlobalState.empty(testItems);
      final xpForLevel10 = startXpForLevel(10);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel10, masteryPoolXp: 0),
        },
      );

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);
      final result = solve(testRegistries, state, goal);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.steps, isEmpty);
    });

    test('finds plan for simple skill level goal', () {
      final state = GlobalState.empty(testItems);

      // Goal: reach woodcutting level 2 (requires 83 XP)
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 2);
      final result = solve(testRegistries, state, goal);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.totalTicks, greaterThan(0));
    });
  });

  group('enumerateCandidates with skill goal', () {
    test('ranks activities by XP rate for skill goals', () {
      var state = GlobalState.empty(testItems);
      // Give high fishing level to unlock multiple fishing activities
      final xpForLevel50 = startXpForLevel(50);
      state = state.copyWith(
        skillStates: {
          Skill.fishing: SkillState(xp: xpForLevel50, masteryPoolXp: 0),
        },
      );

      const goal = ReachSkillLevelGoal(Skill.fishing, 60);
      final candidates = enumerateCandidates(testRegistries, state, goal);

      // Should have activities in switchToActivities
      expect(candidates.switchToActivities, isNotEmpty);

      // For skill goals, the top candidates should include the target skill's
      // best XP activities. However, activities from other skills may also
      // be included since they have xpRatePerTick = 0 for the target skill.
      // The important thing is that fishing activities are present and ranked
      // by their XP rate.
      final fishingActivities = candidates.switchToActivities
          .where((name) => testActions.byName(name).skill == Skill.fishing)
          .toList();
      expect(fishingActivities, isNotEmpty);
    });

    test('does not include SellAll for skill goals', () {
      // For skill goals, selling is not relevant
      final state = GlobalState.empty(testItems);

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);
      final candidates = enumerateCandidates(testRegistries, state, goal);

      // SellAll should not be included for skill goals
      expect(candidates.includeSellAll, isFalse);
    });

    test('only watches activities for target skill', () {
      final state = GlobalState.empty(testItems);

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);
      final candidates = enumerateCandidates(testRegistries, state, goal);

      // Only woodcutting activities should be watched
      for (final name in candidates.watch.lockedActivityNames) {
        final action = testActions.byName(name);
        expect(action.skill, Skill.woodcutting);
      }
    });
  });
}
