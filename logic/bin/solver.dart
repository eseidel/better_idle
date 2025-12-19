// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//
// Example: dart run bin/solver.dart 1000

import 'package:logic/logic.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';

void main(List<String> args) {
  // Parse gold goal from args, default to 100 GP
  final goalCredits = args.isNotEmpty ? int.tryParse(args[0]) ?? 100 : 100;
  print('Goal: $goalCredits GP');

  var state = GlobalState.empty();

  print('Solving...');
  final stopwatch = Stopwatch()..start();
  final result = solveToCredits(state, goalCredits);
  stopwatch.stop();

  print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  // Print result
  if (result is SolverSuccess) {
    print('Plan:');
    print(result.plan.prettyPrint());
    print('Total ticks: ${result.plan.totalTicks}');
    print('Interaction count: ${result.plan.interactionCount}');
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
