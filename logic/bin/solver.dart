// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//        dart run bin/solver.dart -s  # Solve for woodcutting level 70
//
// Example: dart run bin/solver.dart 1000
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:args/args.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('skill', abbr: 's', help: 'Solve for firemaking level 30')
    ..addOption(
      'skills',
      abbr: 'm',
      help: 'Solve for multiple skills (e.g., "Woodcutting=50,Firemaking=50")',
    );

  final results = parser.parse(args);

  final registries = await loadRegistries();

  final Goal goal;
  if (results['skills'] != null) {
    goal = _parseMultiSkillGoal(results['skills'] as String);
    print('Goal: ${goal.describe()}');
  } else if (results['skill'] as bool) {
    goal = const ReachSkillLevelGoal(Skill.firemaking, 30);
    print('Goal: ${goal.describe()}');
  } else {
    // Parse gold goal from remaining args, default to 100 GP
    final goalCredits = results.rest.isNotEmpty
        ? int.tryParse(results.rest[0]) ?? 100
        : 100;
    goal = ReachGpGoal(goalCredits);
    print('Goal: $goalCredits GP');
  }

  final initialState = GlobalState.empty(registries);

  print('Solving...');
  final stopwatch = Stopwatch()..start();
  final result = solve(initialState, goal);
  stopwatch.stop();

  print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  // Print result
  if (result is SolverSuccess) {
    print('Uncompressed plan (${result.plan.steps.length} steps):');
    print(result.plan.prettyPrint(actions: registries.actions));
    print('');
    final compressed = result.plan.compress();
    print(
      'Plan (compressed ${result.plan.steps.length} '
      '-> ${compressed.steps.length} steps):',
    );
    print(compressed.prettyPrint(actions: registries.actions));
    print('Total ticks: ${compressed.totalTicks}');
    print('Interaction count: ${compressed.interactionCount}');

    // Execute the plan to get the final state
    final execResult = executePlan(
      initialState,
      result.plan,
      random: Random(42),
    );
    print('');
    _printFinalState(execResult.finalState);
    if (goal is MultiSkillGoal) {
      _printMultiSkillProgress(execResult.finalState, goal);
    }
    print('');
    print('=== Execution Stats ===');
    print('Planned ticks: ${execResult.plannedTicks}');
    print('Actual ticks: ${execResult.actualTicks}');
    final delta = execResult.ticksDelta;
    final deltaSign = delta >= 0 ? '+' : '';
    print('Delta: $deltaSign$delta ticks');
    print(
      'Deaths: ${execResult.totalDeaths} actual, '
      '${result.plan.expectedDeaths} expected',
    );

    final profile = result.profile;
    if (profile != null) {
      print('');
      _printSolverProfile(profile);
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
    final totalValue = state.inventory.items.fold<int>(
      0,
      (sum, stack) => sum + stack.sellsFor,
    );
    print('Total value: $totalValue gp');
  }
}

void _printSolverProfile(SolverProfile profile) {
  print('=== Solver Profile ===');
  print('Expanded nodes: ${profile.expandedNodes}');
  print('Nodes/sec: ${profile.nodesPerSecond.toStringAsFixed(1)}');
  print(
    'Avg branching factor: ${profile.avgBranchingFactor.toStringAsFixed(2)}',
  );
  print(
    'nextDecisionDelta: min=${profile.minDelta}, '
    'median=${profile.medianDelta}, p95=${profile.p95Delta}',
  );
  print('Time breakdown:');
  print(
    '  advance/consumeTicks: ${profile.advancePercent.toStringAsFixed(1)}%',
  );
  print(
    '  enumerateCandidates: ${profile.enumeratePercent.toStringAsFixed(1)}%',
  );
  print('  hashing (_stateKey): ${profile.hashingPercent.toStringAsFixed(1)}%');
  print('Dominance pruning:');
  print('  dominated skipped: ${profile.dominatedSkipped}');
}

/// Parses "Skill=Level,Skill=Level,..." into a MultiSkillGoal or single goal.
Goal _parseMultiSkillGoal(String input) {
  final skillMap = <Skill, int>{};
  for (final part in input.split(',')) {
    final kv = part.trim().split('=');
    if (kv.length != 2) {
      throw FormatException('Invalid skill format: $part');
    }
    final skillName = kv[0].trim().toLowerCase();
    final level = int.parse(kv[1].trim());

    final skill = Skill.values.firstWhere(
      (s) => s.name.toLowerCase() == skillName,
      orElse: () => throw FormatException('Unknown skill: ${kv[0]}'),
    );
    skillMap[skill] = level;
  }

  if (skillMap.length == 1) {
    // Single skill: use simpler goal type
    final entry = skillMap.entries.first;
    return ReachSkillLevelGoal(entry.key, entry.value);
  }
  return MultiSkillGoal.fromMap(skillMap);
}

/// Prints per-skill progress for multi-skill goals.
void _printMultiSkillProgress(GlobalState state, MultiSkillGoal goal) {
  print('');
  print('=== Multi-Skill Progress ===');

  var totalRemainingXp = 0.0;
  for (final subgoal in goal.subgoals) {
    final skillState = state.skillState(subgoal.skill);
    final targetXp = subgoal.targetXp;
    final remaining = subgoal.remaining(state);
    totalRemainingXp += remaining;

    final status = subgoal.isSatisfied(state) ? '✓' : ' ';
    print(
      '  $status ${subgoal.skill.name}: '
      'Level ${skillState.skillLevel}/${subgoal.targetLevel} '
      '(${skillState.xp}/$targetXp XP, '
      '${remaining.toInt()} remaining)',
    );
  }
  print('  Total remaining: ${totalRemainingXp.toInt()} XP');
}
