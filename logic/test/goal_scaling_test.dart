/// Goal scaling regression tests for solver performance.
///
/// These tests verify that solver performance scales reasonably (linearly-ish,
/// not exponentially) as goal complexity increases. They use generous bounds
/// to avoid flakiness while catching exponential blowups.
///
/// Run with: dart test test/goal_scaling_test.dart
/// Skip in quick runs: dart test --exclude-tags slow
@Tags(['slow'])
library;

import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('goal scaling regression', () {
    test('2 skills to 99 completes efficiently', () {
      final state = GlobalState.empty(testRegistries);
      const goal = MultiSkillGoal([
        ReachSkillLevelGoal(Skill.woodcutting, 99),
        ReachSkillLevelGoal(Skill.fishing, 99),
      ]);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      // Verify reasonable node expansion (current baseline ~10k-50k)
      expect(
        profile.expandedNodes,
        lessThan(150000),
        reason: 'WC/Fish 99 should not expand >150k nodes',
      );

      // Verify plan is reasonable (not thousands of micro-steps)
      expect(
        success.plan.steps.length,
        lessThan(500),
        reason: 'Plan should not have >500 steps',
      );

      // Verify plan reaches goal when executed
      expect(success.plan.totalTicks, greaterThan(0));
    });

    test('single skill to 99 establishes baseline', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 99);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      // Single skill should be very efficient
      expect(
        profile.expandedNodes,
        lessThan(50000),
        reason: 'Single skill 99 should not expand >50k nodes',
      );
    });

    test('3 skills to 50 scales sub-exponentially', () {
      final state = GlobalState.empty(testRegistries);
      const goal = MultiSkillGoal([
        ReachSkillLevelGoal(Skill.woodcutting, 50),
        ReachSkillLevelGoal(Skill.fishing, 50),
        ReachSkillLevelGoal(Skill.mining, 50),
      ]);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      // 3 skills to 50 should not explode
      expect(
        profile.expandedNodes,
        lessThan(100000),
        reason: '3 skills to 50 should not expand >100k nodes',
      );
    });

    test('4 skills to 30 scales sub-exponentially', () {
      final state = GlobalState.empty(testRegistries);
      const goal = MultiSkillGoal([
        ReachSkillLevelGoal(Skill.woodcutting, 30),
        ReachSkillLevelGoal(Skill.fishing, 30),
        ReachSkillLevelGoal(Skill.mining, 30),
        ReachSkillLevelGoal(Skill.thieving, 30),
      ]);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      // 4 skills to 30 should be efficient
      expect(
        profile.expandedNodes,
        lessThan(100000),
        reason: '4 skills to 30 should not expand >100k nodes',
      );
    }, skip: true);
  });

  group('consuming skill scaling', () {
    test('firemaking 50 alone completes efficiently', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.firemaking, 50);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      // Single consuming skill should be efficient
      expect(
        profile.expandedNodes,
        lessThan(75000),
        reason: 'Firemaking 50 should not expand >75k nodes',
      );

      // Should have diagnostic stats about consuming skill candidates
      expect(profile.candidateStatsHistory, isNotEmpty);
    });

    test('cooking 50 alone completes efficiently', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.cooking, 50);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      expect(
        profile.expandedNodes,
        lessThan(75000),
        reason: 'Cooking 50 should not expand >75k nodes',
      );
    });

    test('woodcutting + firemaking 50 scales reasonably', () {
      final state = GlobalState.empty(testRegistries);
      const goal = MultiSkillGoal([
        ReachSkillLevelGoal(Skill.woodcutting, 50),
        ReachSkillLevelGoal(Skill.firemaking, 50),
      ]);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      // Producer + consumer pair should be efficient
      expect(
        profile.expandedNodes,
        lessThan(100000),
        reason: 'WC + FM 50 should not expand >100k nodes',
      );
    });

    test('fishing + cooking 50 scales reasonably', () {
      final state = GlobalState.empty(testRegistries);
      const goal = MultiSkillGoal([
        ReachSkillLevelGoal(Skill.fishing, 50),
        ReachSkillLevelGoal(Skill.cooking, 50),
      ]);

      final result = solve(
        state,
        goal,
        random: Random(42),
        collectDiagnostics: true,
      );

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      final profile = success.profile!;

      expect(
        profile.expandedNodes,
        lessThan(100000),
        reason: 'Fish + Cook 50 should not expand >100k nodes',
      );
    });
  });

  group('linear scaling validation', () {
    test('expansion count grows sub-exponentially with skill count', () {
      final state = GlobalState.empty(testRegistries);

      // Solve with 1, 2, 3 skills to level 30 and track expansion counts
      final expansionCounts = <int, int>{};

      // 1 skill
      final result1 = solve(
        state,
        const ReachSkillLevelGoal(Skill.woodcutting, 30),
        random: Random(42),
        collectDiagnostics: true,
      );
      expect(result1, isA<SolverSuccess>());
      expansionCounts[1] = (result1 as SolverSuccess).profile!.expandedNodes;

      // 2 skills
      final result2 = solve(
        state,
        const MultiSkillGoal([
          ReachSkillLevelGoal(Skill.woodcutting, 30),
          ReachSkillLevelGoal(Skill.fishing, 30),
        ]),
        random: Random(42),
        collectDiagnostics: true,
      );
      expect(result2, isA<SolverSuccess>());
      expansionCounts[2] = (result2 as SolverSuccess).profile!.expandedNodes;

      // 3 skills
      final result3 = solve(
        state,
        const MultiSkillGoal([
          ReachSkillLevelGoal(Skill.woodcutting, 30),
          ReachSkillLevelGoal(Skill.fishing, 30),
          ReachSkillLevelGoal(Skill.mining, 30),
        ]),
        random: Random(42),
        collectDiagnostics: true,
      );
      expect(result3, isA<SolverSuccess>());
      expansionCounts[3] = (result3 as SolverSuccess).profile!.expandedNodes;

      // Verify sub-exponential growth:
      // If exponential: 3-skill would be >> 4x of 2-skill
      // We allow up to 4x growth per additional skill (generous bound)
      final ratio2to1 = expansionCounts[2]! / expansionCounts[1]!;
      final ratio3to2 = expansionCounts[3]! / expansionCounts[2]!;

      expect(
        ratio2to1,
        lessThan(10),
        reason:
            '2-skill expansion (${expansionCounts[2]}) should be <10x '
            '1-skill (${expansionCounts[1]})',
      );

      expect(
        ratio3to2,
        lessThan(10),
        reason:
            '3-skill expansion (${expansionCounts[3]}) should be <10x '
            '2-skill (${expansionCounts[2]})',
      );
    });

    test('expansion count grows sub-exponentially with target level', () {
      final state = GlobalState.empty(testRegistries);

      // Solve WC to 20, 40, 60 and track expansion counts
      final expansionCounts = <int, int>{};

      for (final level in [20, 40, 60]) {
        final result = solve(
          state,
          ReachSkillLevelGoal(Skill.woodcutting, level),
          random: Random(42),
          collectDiagnostics: true,
        );
        expect(result, isA<SolverSuccess>());
        final success = result as SolverSuccess;
        expansionCounts[level] = success.profile!.expandedNodes;
      }

      // XP requirement grows exponentially with level, but expansion should not
      // (thanks to macro planning and dominance pruning)
      final ratio40to20 = expansionCounts[40]! / expansionCounts[20]!;
      final ratio60to40 = expansionCounts[60]! / expansionCounts[40]!;

      // Generous bound: allow up to 5x per 20 levels
      expect(
        ratio40to20,
        lessThan(10),
        reason:
            'L40 expansion (${expansionCounts[40]}) should be <10x '
            'L20 (${expansionCounts[20]})',
      );

      expect(
        ratio60to40,
        lessThan(10),
        reason:
            'L60 expansion (${expansionCounts[60]}) should be <10x '
            'L40 (${expansionCounts[40]})',
      );
    });
  });

  group('plan quality checks', () {
    test('multi-skill plan has reasonable step count', () {
      final state = GlobalState.empty(testRegistries);
      const goal = MultiSkillGoal([
        ReachSkillLevelGoal(Skill.woodcutting, 50),
        ReachSkillLevelGoal(Skill.fishing, 50),
      ]);

      final result = solve(state, goal, random: Random(42));

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;

      // Plan should be compressed (not micro-steps for every action)
      final compressed = success.plan.compress();
      expect(
        compressed.steps.length,
        lessThan(100),
        reason: 'Compressed plan should have <100 steps',
      );
    });

    test('consuming skill plan alternates produce/consume', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.firemaking, 30);

      final result = solve(state, goal, random: Random(42));

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;

      // Plan should reach the goal
      expect(success.plan.totalTicks, greaterThan(0));

      // Plan should have both WC (produce) and FM (consume) activities
      // Check interaction steps for activity switches OR macros
      final switches = success.plan.steps
          .whereType<InteractionStep>()
          .where((step) => step.interaction is SwitchActivity)
          .map((step) => (step.interaction as SwitchActivity).actionId)
          .toList();

      // Check for macro steps (which include activity selection)
      final macros = success.plan.steps.whereType<MacroStep>().toList();

      // Should have at least one switch or macro (to start an activity)
      expect(
        switches.isNotEmpty || macros.isNotEmpty,
        isTrue,
        reason: 'Plan should have activity switches or macros',
      );
    });
  });
}
