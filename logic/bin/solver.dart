// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//
// Example: dart run bin/solver.dart 1000

import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';

void main(List<String> args) {
  // Parse goal from args, default to 1000
  final goalCredits = args.isNotEmpty ? int.tryParse(args[0]) ?? 1000 : 1000;

  // Demo state with some progress and an active action
  var state = GlobalState.empty().copyWith(
    gp: 40,
    skillStates: {
      Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
      // Level 20 = 4470 XP
      Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.fishing: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.mining: const SkillState(xp: 4470, masteryPoolXp: 0),
    },
  );

  // Start an action so we have gold rate
  final action = actionRegistry.byName('Willow Tree');
  state = state.startAction(action, random: Random(0));

  print('=== Solver ===');
  print('');
  print('Initial State:');
  print('  GP: ${state.gp}');
  print('  Active: ${state.activeAction?.name}');
  print('  Skills: Level 20 woodcutting/fishing/mining');
  print('');
  print('Goal: $goalCredits GP');
  print('');

  // Solve
  final stopwatch = Stopwatch()..start();
  final result = solveToCredits(state, goalCredits);
  stopwatch.stop();

  print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  // Print result
  if (result is SolverSuccess) {
    print(result.plan.prettyPrint());
  } else if (result is SolverFailed) {
    print('FAILED: ${result.failure.reason}');
    print('  Expanded nodes: ${result.failure.expandedNodes}');
    print('  Enqueued nodes: ${result.failure.enqueuedNodes}');
    if (result.failure.bestCredits != null) {
      print('  Best credits reached: ${result.failure.bestCredits}');
    }
  }
}
