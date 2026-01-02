// Reproduces solver failures from a saved repro bundle.
//
// Usage: dart run bin/repro.dart [path/to/repro.json]
//        dart run bin/repro.dart  # Uses repro.json in current directory
//
// The repro bundle contains the game state and goal at the point of failure,
// allowing you to reproduce and debug solver issues.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/execution/execute_plan.dart';
import 'package:logic/src/solver/execution/plan.dart';

void main(List<String> args) async {
  // Determine the repro file path
  final reproPath = args.isNotEmpty ? args[0] : 'repro.json';
  final reproFile = File(reproPath);

  if (!reproFile.existsSync()) {
    print('Error: Repro file not found: $reproPath');
    print('');
    print('Usage: dart run bin/repro.dart [path/to/repro.json]');
    exit(1);
  }

  print('Loading repro bundle from: $reproPath');
  print('');

  // Load registries
  final registries = await loadRegistries();

  // Parse the repro bundle
  final jsonString = reproFile.readAsStringSync();
  final bundle = ReproBundle.fromJsonString(jsonString, registries);

  // Print bundle info
  print('=== Repro Bundle ===');
  print('Goal: ${bundle.goal.describe()}');
  if (bundle.reason != null) {
    print('Original failure reason: ${bundle.reason}');
  }
  print('');

  // Print state summary
  _printStateSummary(bundle.state);

  // Check if goal is already satisfied
  if (bundle.goal.isSatisfied(bundle.state)) {
    print('Note: Goal is already satisfied in this state!');
    print('');
  }

  // Run the solver
  print('=== Running Solver ===');
  final stopwatch = Stopwatch()..start();
  final result = solve(
    bundle.state,
    bundle.goal,
    random: Random(42),
    collectDiagnostics: true,
  );
  stopwatch.stop();

  print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  // Print result
  switch (result) {
    case SolverSuccess(:final plan):
      print('=== SUCCESS ===');
      print('Plan found with ${plan.steps.length} steps');
      print('Total ticks: ${plan.totalTicks}');
      print('');
      print(plan.prettyPrint(actions: registries.actions));

      // Execute the plan
      print('');
      print('=== Executing Plan ===');
      final execStopwatch = Stopwatch()..start();
      final execResult = executePlan(bundle.state, plan, random: Random(42));
      execStopwatch.stop();
      print('Execution completed in ${execStopwatch.elapsedMilliseconds}ms');
      print('');
      print('Planned: ${durationStringWithTicks(execResult.plannedTicks)}');
      print('Actual: ${durationStringWithTicks(execResult.actualTicks)}');
      print('Delta: ${signedDurationStringWithTicks(execResult.ticksDelta)}');
      print('Deaths: ${execResult.totalDeaths}');

      // Verify goal is satisfied
      if (bundle.goal.isSatisfied(execResult.finalState)) {
        print('');
        print('Goal satisfied after execution.');
      } else {
        print('');
        print('WARNING: Goal NOT satisfied after execution!');
      }

    case SolverFailed(:final failure):
      print('=== FAILED ===');
      print('Reason: ${failure.reason}');
      print('Expanded nodes: ${failure.expandedNodes}');
      print('Enqueued nodes: ${failure.enqueuedNodes}');
      if (failure.bestCredits != null) {
        print('Best credits reached: ${failure.bestCredits}');
      }
  }

  // Print profile if available
  final profile = result.profile;
  if (profile != null) {
    print('');
    print('=== Solver Profile ===');
    print('Expanded nodes: ${profile.expandedNodes}');
    print('Nodes/sec: ${profile.nodesPerSecond.toStringAsFixed(1)}');
    print(
      'Avg branching factor: ${profile.avgBranchingFactor.toStringAsFixed(2)}',
    );
  }
}

/// Prints a summary of the game state.
void _printStateSummary(GlobalState state) {
  print('=== State Summary ===');
  print('GP: ${preciseNumberString(state.gp)}');

  // Print skill levels
  final skills = Skill.values.where((s) {
    final ss = state.skillState(s);
    return ss.skillLevel > 1 || ss.xp > 0;
  }).toList();

  if (skills.isNotEmpty) {
    print('');
    print('Skills:');
    for (final skill in skills) {
      final ss = state.skillState(skill);
      print('  ${skill.name}: Level ${ss.skillLevel} (${ss.xp} XP)');
    }
  }

  // Print inventory summary
  if (state.inventory.items.isNotEmpty) {
    print('');
    print('Inventory: ${state.inventory.items.length} item types');
    final totalValue = state.inventory.items.fold<int>(
      0,
      (sum, stack) => sum + stack.sellsFor,
    );
    print('Total value: ${preciseNumberString(totalValue)} GP');
  }

  print('');
}
