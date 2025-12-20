// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//        dart run bin/solver.dart -s  # Solve for woodcutting level 70
//
// Example: dart run bin/solver.dart 1000

import 'package:args/args.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';

void main(List<String> args) {
  final parser = ArgParser()
    ..addFlag('skill', abbr: 's', help: 'Solve for woodcutting level 70');

  final results = parser.parse(args);

  final Goal goal;
  if (results['skill'] as bool) {
    goal = const ReachSkillLevelGoal(Skill.woodcutting, 30);
    print('Goal: ${goal.describe()}');
  } else {
    // Parse gold goal from remaining args, default to 100 GP
    final goalCredits = results.rest.isNotEmpty
        ? int.tryParse(results.rest[0]) ?? 100
        : 100;
    goal = ReachGpGoal(goalCredits);
    print('Goal: $goalCredits GP');
  }

  final initialState = GlobalState.empty();

  print('Solving...');
  final stopwatch = Stopwatch()..start();
  final result = solve(initialState, goal);
  stopwatch.stop();

  print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  // Print result
  if (result is SolverSuccess) {
    print('Plan:');
    print(result.plan.prettyPrint());
    print('Total ticks: ${result.plan.totalTicks}');
    print('Interaction count: ${result.plan.interactionCount}');

    // Execute the plan to get the final state
    final execResult = executePlan(initialState, result.plan);
    print('');
    _printFinalState(execResult.finalState);
    print('');
    print('=== Execution Stats ===');
    print('Planned ticks: ${execResult.plannedTicks}');
    print('Actual ticks: ${execResult.actualTicks}');
    final delta = execResult.ticksDelta;
    final deltaSign = delta >= 0 ? '+' : '';
    print('Delta: $deltaSign$delta ticks');
    if (execResult.totalDeaths > 0) {
      print('Deaths: ${execResult.totalDeaths}');
    }

    if (result.profile != null) {
      print('');
      print(result.profile);
    }
  } else if (result is SolverFailed) {
    print('FAILED: ${result.failure.reason}');
    print('  Expanded nodes: ${result.failure.expandedNodes}');
    print('  Enqueued nodes: ${result.failure.enqueuedNodes}');
    if (result.failure.bestCredits != null) {
      print('  Best credits reached: ${result.failure.bestCredits}');
    }
    if (result.profile != null) {
      print('');
      print(result.profile);
    }
  }
}

/// Prints the final state after executing the plan.
void _printFinalState(GlobalState state) {
  print('=== Final State ===');
  print('GP: ${state.gp}');
  print('');

  // Print skill levels
  print('Skills:');
  for (final skill in Skill.values) {
    final skillState = state.skillState(skill);
    if (skillState.skillLevel > 1 || skillState.xp > 0) {
      print(
        '  ${skill.name}: Level ${skillState.skillLevel} (${skillState.xp} XP)',
      );
    }
  }

  // Print inventory if not empty
  if (state.inventory.items.isNotEmpty) {
    print('');
    print('Inventory:');
    for (final stack in state.inventory.items) {
      print('  ${stack.item.name}: ${stack.count}');
    }
  }
}
