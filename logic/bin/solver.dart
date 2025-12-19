// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//
// Example: dart run bin/solver.dart 1000

import 'package:logic/logic.dart';
import 'package:logic/src/solver/apply_interaction.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';

void main(List<String> args) {
  // Parse gold goal from args, default to 100 GP
  final goalCredits = args.isNotEmpty ? int.tryParse(args[0]) ?? 100 : 100;
  print('Goal: $goalCredits GP');

  final initialState = GlobalState.empty();

  print('Solving...');
  final stopwatch = Stopwatch()..start();
  final result = solveToCredits(initialState, goalCredits);
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
    final finalState = _executePlan(initialState, result.plan);
    print('');
    _printFinalState(finalState);

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

/// Executes a plan and returns the final state.
GlobalState _executePlan(GlobalState state, Plan plan) {
  for (final step in plan.steps) {
    switch (step) {
      case InteractionStep(:final interaction):
        state = applyInteraction(state, interaction);
      case WaitStep(:final deltaTicks):
        state = advance(state, deltaTicks);
    }
  }
  return state;
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
