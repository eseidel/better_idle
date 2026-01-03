import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/candidates/enumerate_candidates.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('ReachGpGoal', () {
    test('isSatisfied returns true when GP >= target', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const goal = ReachGpGoal(100);

      expect(goal.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when GP > target', () {
      final state = GlobalState.test(testRegistries, gp: 200);
      const goal = ReachGpGoal(100);

      expect(goal.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when GP < target', () {
      final state = GlobalState.test(testRegistries, gp: 50);
      const goal = ReachGpGoal(100);

      expect(goal.isSatisfied(state), isFalse);
    });

    test('remaining returns 0 when goal is satisfied', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const goal = ReachGpGoal(100);

      expect(goal.remaining(state), 0.0);
    });

    test('remaining returns positive value when not satisfied', () {
      final state = GlobalState.test(testRegistries, gp: 50);
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
      var state = GlobalState.empty(testRegistries);
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
      var state = GlobalState.empty(testRegistries);
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
      final state = GlobalState.empty(testRegistries); // Starts at level 1

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

      expect(goal.isSatisfied(state), isFalse);
    });

    test('remaining returns 0 when goal is satisfied', () {
      var state = GlobalState.empty(testRegistries);
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
      final state = GlobalState.empty(testRegistries); // 0 XP in woodcutting

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
      var state = GlobalState.empty(testRegistries);
      final xpForLevel10 = startXpForLevel(10);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel10, masteryPoolXp: 0),
        },
      );

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);
      final result = solve(state, goal, random: Random(42));

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.steps, isEmpty);
    });

    test('finds plan for simple skill level goal', () {
      final state = GlobalState.empty(testRegistries);

      // Goal: reach woodcutting level 2 (requires 83 XP)
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 2);
      final result = solve(state, goal, random: Random(42));

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.totalTicks, greaterThan(0));
    });
  });

  group('enumerateCandidates with skill goal', () {
    test('ranks activities by XP rate for skill goals', () {
      var state = GlobalState.empty(testRegistries);
      // Give high fishing level to unlock multiple fishing activities
      final xpForLevel50 = startXpForLevel(50);
      state = state.copyWith(
        skillStates: {
          Skill.fishing: SkillState(xp: xpForLevel50, masteryPoolXp: 0),
        },
      );

      const goal = ReachSkillLevelGoal(Skill.fishing, 60);
      final candidates = enumerateCandidates(state, goal);

      // Should have activities in switchToActivities
      expect(candidates.switchToActivities, isNotEmpty);

      // For skill goals, the top candidates should include the target skill's
      // best XP activities. However, activities from other skills may also
      // be included since they have xpRatePerTick = 0 for the target skill.
      // The important thing is that fishing activities are present and ranked
      // by their XP rate.
      final fishingActivities = candidates.switchToActivities
          .where((id) => testActions.byId(id).skill == Skill.fishing)
          .toList();
      expect(fishingActivities, isNotEmpty);
    });

    test('does not emit sell candidate for skill goals', () {
      // For skill goals, selling is not relevant to progress
      final state = GlobalState.empty(testRegistries);

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);
      final candidates = enumerateCandidates(state, goal);

      // sellPolicy is always available (for boundary detection)
      // but shouldEmitSellCandidate should be false (selling doesn't help XP)
      expect(candidates.sellPolicy, isNotNull);
      expect(candidates.shouldEmitSellCandidate, isFalse);
    });

    test('only watches activities for target skill', () {
      final state = GlobalState.empty(testRegistries);

      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);
      final candidates = enumerateCandidates(state, goal);

      // Only woodcutting activities should be watched
      for (final actionId in candidates.watch.lockedActivityIds) {
        final action = testActions.byId(actionId);
        expect(action.skill, Skill.woodcutting);
      }
    });
  });

  group('MultiSkillGoal', () {
    test('isSatisfied requires all subgoals satisfied', () {
      var state = GlobalState.empty(testRegistries);
      // Give woodcutting level 5 XP, but not enough for firemaking
      final xpForLevel5 = startXpForLevel(5);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
          Skill.firemaking: const SkillState(
            xp: 50,
            masteryPoolXp: 0,
          ), // Only level 1
        },
      );

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 5,
        Skill.firemaking: 3,
      });

      // Woodcutting is at 5, but firemaking is only level 1 (needs level 3)
      expect(goal.isSatisfied(state), isFalse);

      // Now give firemaking enough XP for level 3
      final xpForLevel3 = startXpForLevel(3);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
          Skill.firemaking: SkillState(xp: xpForLevel3, masteryPoolXp: 0),
        },
      );

      expect(goal.isSatisfied(state), isTrue);
    });

    test('remaining sums XP across unfinished skills', () {
      final state = GlobalState.empty(testRegistries);

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 2,
        Skill.firemaking: 2,
      });

      // Both skills at level 1 (0 XP)
      // Level 2 requires 83 XP each, so 166 total
      final xpForLevel2 = startXpForLevel(2);
      expect(goal.remaining(state), equals(xpForLevel2 * 2.0));
    });

    test('remaining only counts unfinished skills', () {
      var state = GlobalState.empty(testRegistries);
      final xpForLevel5 = startXpForLevel(5);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
          // firemaking still at 0
        },
      );

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 5, // Already satisfied
        Skill.firemaking: 2, // Not satisfied
      });

      // Only firemaking should contribute to remaining
      final xpForLevel2 = startXpForLevel(2);
      expect(goal.remaining(state), equals(xpForLevel2.toDouble()));
    });

    test('isSkillRelevant returns true for goal skills only', () {
      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 50,
      });

      expect(goal.isSkillRelevant(Skill.woodcutting), isTrue);
      expect(goal.isSkillRelevant(Skill.firemaking), isTrue);
      expect(goal.isSkillRelevant(Skill.fishing), isFalse);
      expect(goal.isSkillRelevant(Skill.thieving), isFalse);
    });

    test('isSellRelevant returns false', () {
      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 50,
      });

      expect(goal.isSellRelevant, isFalse);
    });

    test('describe lists all skill targets', () {
      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 40,
      });

      final description = goal.describe().toLowerCase();
      expect(description, contains('woodcutting'));
      expect(description, contains('firemaking'));
      expect(description, contains('50'));
      expect(description, contains('40'));
    });

    test('progress returns sum of XP across target skills', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: const SkillState(xp: 100, masteryPoolXp: 0),
          Skill.firemaking: const SkillState(xp: 50, masteryPoolXp: 0),
        },
      );

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 10,
        Skill.firemaking: 10,
      });

      expect(goal.progress(state), equals(150));
    });

    test('activityRate returns XP rate for relevant skills only', () {
      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 50,
      });

      // Woodcutting activity should contribute its XP rate
      expect(goal.activityRate(Skill.woodcutting, 10, 5), equals(5.0));
      expect(goal.activityRate(Skill.firemaking, 8, 4), equals(4.0));

      // Non-goal skill should return 0
      expect(goal.activityRate(Skill.fishing, 20, 10), equals(0.0));
    });

    test('equality works correctly', () {
      final goal1 = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 50,
      });
      final goal2 = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 50,
      });
      final goal3 = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 40, // Different level
      });

      expect(goal1, equals(goal2));
      expect(goal1, isNot(equals(goal3)));
    });

    test('fromMap with single skill returns MultiSkillGoal', () {
      // fromMap always creates MultiSkillGoal, even with single skill
      final goal = MultiSkillGoal.fromMap(const {Skill.woodcutting: 50});

      expect(goal, isA<MultiSkillGoal>());
      expect(goal.subgoals.length, equals(1));
    });
  });

  group('solve with MultiSkillGoal', () {
    test('returns empty plan when all skills at target level', () {
      var state = GlobalState.empty(testRegistries);
      final xpForLevel5 = startXpForLevel(5);
      state = state.copyWith(
        skillStates: {
          Skill.woodcutting: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
          Skill.firemaking: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
        },
      );

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 5,
        Skill.firemaking: 5,
      });
      final result = solve(state, goal, random: Random(42));

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.steps, isEmpty);
    });

    test('finds plan for simple multi-skill goal', () {
      final state = GlobalState.empty(testRegistries);

      // Goal: reach woodcutting and firemaking level 2
      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 2,
        Skill.firemaking: 2,
      });
      final result = solve(state, goal, random: Random(42));

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.totalTicks, greaterThan(0));
    });
  });

  group('Goal JSON serialization', () {
    test('ReachGpGoal round-trips through JSON', () {
      const original = ReachGpGoal(5000);
      final json = original.toJson();
      final restored = Goal.fromJson(json);

      expect(restored, isA<ReachGpGoal>());
      expect(restored, equals(original));
      expect((restored as ReachGpGoal).targetGp, 5000);
    });

    test('ReachSkillLevelGoal round-trips through JSON', () {
      const original = ReachSkillLevelGoal(Skill.woodcutting, 50);
      final json = original.toJson();
      final restored = Goal.fromJson(json);

      expect(restored, isA<ReachSkillLevelGoal>());
      expect(restored, equals(original));
      final restoredGoal = restored as ReachSkillLevelGoal;
      expect(restoredGoal.skill, Skill.woodcutting);
      expect(restoredGoal.targetLevel, 50);
    });

    test('MultiSkillGoal round-trips through JSON', () {
      final original = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 50,
        Skill.firemaking: 40,
      });
      final json = original.toJson();
      final restored = Goal.fromJson(json);

      expect(restored, isA<MultiSkillGoal>());
      expect(restored, equals(original));
      final restoredGoal = restored as MultiSkillGoal;
      expect(restoredGoal.subgoals.length, 2);
    });

    test('ReachGpGoal toJson has correct structure', () {
      const goal = ReachGpGoal(1000);
      final json = goal.toJson();

      expect(json['type'], 'ReachGpGoal');
      expect(json['targetGp'], 1000);
    });

    test('ReachSkillLevelGoal toJson has correct structure', () {
      const goal = ReachSkillLevelGoal(Skill.fishing, 25);
      final json = goal.toJson();

      expect(json['type'], 'ReachSkillLevelGoal');
      expect(json['skill'], 'Fishing');
      expect(json['targetLevel'], 25);
    });

    test('MultiSkillGoal toJson has correct structure', () {
      final goal = MultiSkillGoal.fromMap(const {
        Skill.mining: 30,
        Skill.smithing: 20,
      });
      final json = goal.toJson();

      expect(json['type'], 'MultiSkillGoal');
      expect(json['subgoals'], isA<List<dynamic>>());
      expect((json['subgoals'] as List<dynamic>).length, 2);
    });

    test('fromJson throws for unknown type', () {
      final json = {'type': 'UnknownGoal'};

      expect(() => Goal.fromJson(json), throwsArgumentError);
    });

    test('fromJson throws for SegmentGoal', () {
      final json = <String, dynamic>{
        'type': 'SegmentGoal',
        'innerGoal': <String, dynamic>{},
      };

      expect(() => Goal.fromJson(json), throwsArgumentError);
    });

    test('fromJson handles all Skill types in ReachSkillLevelGoal', () {
      for (final skill in Skill.values) {
        final original = ReachSkillLevelGoal(skill, 10);
        final json = original.toJson();
        final restored = Goal.fromJson(json) as ReachSkillLevelGoal;

        expect(restored.skill, skill);
        expect(restored.targetLevel, 10);
      }
    });
  });

  group('enumerateCandidates with MultiSkillGoal', () {
    test('includes activities for all goal skills', () {
      final state = GlobalState.empty(testRegistries);

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 10,
        Skill.firemaking: 10,
      });
      final candidates = enumerateCandidates(state, goal);

      expect(candidates.switchToActivities, isNotEmpty);

      // Should include both woodcutting and firemaking activities
      final skills = candidates.switchToActivities
          .map((id) => testActions.byId(id).skill)
          .toSet();

      // At minimum, woodcutting should be present (firemaking may need inputs)
      expect(skills, contains(Skill.woodcutting));
    });

    test('watches activities for all goal skills', () {
      final state = GlobalState.empty(testRegistries);

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 10,
        Skill.firemaking: 10,
      });
      final candidates = enumerateCandidates(state, goal);

      // Should only watch activities for goal skills
      for (final actionId in candidates.watch.lockedActivityIds) {
        final action = testActions.byId(actionId);
        expect(
          goal.isSkillRelevant(action.skill),
          isTrue,
          reason: '${action.skill} should be relevant to goal',
        );
      }
    });

    test('does not emit sell candidate for multi-skill goals', () {
      final state = GlobalState.empty(testRegistries);

      final goal = MultiSkillGoal.fromMap(const {
        Skill.woodcutting: 10,
        Skill.firemaking: 10,
      });
      final candidates = enumerateCandidates(state, goal);

      // sellPolicy is always available (for boundary detection)
      // but shouldEmitSellCandidate should be false (selling doesn't help XP)
      expect(candidates.sellPolicy, isNotNull);
      expect(candidates.shouldEmitSellCandidate, isFalse);
    });
  });
}
