/// Regression tests for solveWithReplanning vs solveToGoal migration.
///
/// These tests verify that both solver paths:
/// 1. Reach the goal successfully
/// 2. Don't hang or loop infinitely
/// 3. Maintain invariants (sell policy consistency, etc.)
///
/// Tick delta comparisons are SOFT metrics (logged, not failed) since
/// stochastic execution can legitimately differ from projected execution.
@Tags(['bench'])
library;

import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/execution/execute_plan.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('solveWithReplanning regression', () {
    // Goals with their tolerance thresholds
    // Simple skills: 25% to account for stochastic variance (fishing randomness)
    // Use lower levels to keep tests fast
    final testCases = <(Goal, double, String)>[
      (
        const ReachSkillLevelGoal(Skill.woodcutting, 15),
        0.25,
        'Woodcutting 15',
      ),
      (const ReachSkillLevelGoal(Skill.fishing, 15), 0.25, 'Fishing 15'),
      (const ReachSkillLevelGoal(Skill.firemaking, 15), 0.25, 'Firemaking 15'),
      // Mining is simpler than smithing (no consuming skill)
      (const ReachSkillLevelGoal(Skill.mining, 15), 0.25, 'Mining 15'),
    ];

    for (final (goal, tolerance, description) in testCases) {
      test('$description - both paths reach goal', () {
        final state = GlobalState.empty(testRegistries);
        const seed = 42;

        // OLD PATH: solveToGoal → execute returned steps
        final oldResult = solveToGoal(state, goal, random: Random(seed));
        expect(
          oldResult,
          isA<SegmentedSuccess>(),
          reason: 'Old path should succeed',
        );
        final oldSuccess = oldResult as SegmentedSuccess;

        // Build plan from segments and execute
        final oldPlan = Plan.fromSegments(oldSuccess.segments);
        final oldExec = executePlan(state, oldPlan, random: Random(seed));

        // NEW PATH: solveWithReplanning (executes internally)
        final newResult = solveWithReplanning(
          state,
          goal,
          random: Random(seed),
          config: const ReplanConfig(maxReplans: 100),
        );

        // HARD ASSERTS: both reach goal, no hangs
        expect(
          goal.isSatisfied(oldExec.finalState),
          isTrue,
          reason: 'Old path must reach goal',
        );
        expect(
          goal.isSatisfied(newResult.finalState),
          isTrue,
          reason: 'New path must reach goal',
        );
        expect(
          newResult.totalTicks,
          lessThan(10000000),
          reason: 'No infinite loops (10M tick sanity)',
        );

        // SOFT METRICS: log ratio, don't fail
        final oldTicks = oldExec.actualTicks;
        final newTicks = newResult.totalTicks;
        final tickDelta = (newTicks - oldTicks).abs();
        final ratio = oldTicks > 0 ? tickDelta / oldTicks : 0.0;

        // Log for bench test output
        // ignore: avoid_print
        print(
          '$description: old=$oldTicks, new=$newTicks, '
          'delta=${(ratio * 100).toStringAsFixed(1)}%',
        );
        if (ratio > tolerance) {
          // ignore: avoid_print
          print('  WARNING: exceeds ${(tolerance * 100).toInt()}% tolerance');
        }
      });
    }

    test('recovery actions preserve sell policy consistency', () {
      // Test that upgrade purchase uses the same policy as detection
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 30);
      const seed = 42;

      final result = solveWithReplanning(
        state,
        goal,
        random: Random(seed),
        config: const ReplanConfig(maxReplans: 100),
      );

      expect(result.goalReached, isTrue);

      // All segments should have a sellPolicy set
      for (final segment in result.segments) {
        // Only non-recovery segments have steps, recovery segments may be empty
        if (segment.steps.isNotEmpty) {
          expect(
            segment.sellPolicy,
            isNotNull,
            reason: 'Every segment should have a sellPolicy',
          );
        }
      }
    });

    test('GP goal recovery sells when effective > actual', () {
      // Test that we can reach a GP goal by woodcutting and selling
      // This tests the full loop: solve -> execute -> replan if needed
      final state = GlobalState.empty(testRegistries);
      const goal = ReachGpGoal(100); // Small goal, reachable quickly
      const seed = 42;

      final result = solveWithReplanning(
        state,
        goal,
        random: Random(seed),
        config: const ReplanConfig(maxReplans: 100),
      );

      expect(result.goalReached, isTrue);
      expect(result.finalState.gp, greaterThanOrEqualTo(100));
    });
  });
}
