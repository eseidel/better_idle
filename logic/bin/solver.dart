// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//        dart run bin/solver.dart -s  # Solve for woodcutting level 70
//        dart run bin/solver.dart --cliff  # Diagnose FM=55 vs FM=56 cliff
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
    )
    ..addFlag(
      'cliff',
      help: 'Run cliff diagnostic comparing FM=55 vs FM=56',
      negatable: false,
    )
    ..addOption(
      'cliff-skill',
      help: 'Skill for cliff diagnostic (default: Firemaking)',
      defaultsTo: 'Firemaking',
    )
    ..addOption(
      'cliff-level',
      help: 'Lower level for cliff diagnostic (default: 55)',
      defaultsTo: '55',
    );

  final results = parser.parse(args);

  final registries = await loadRegistries();

  // Handle cliff diagnostic mode
  if (results['cliff'] as bool) {
    final skillName = (results['cliff-skill'] as String).toLowerCase();
    final skill = Skill.values.firstWhere(
      (s) => s.name.toLowerCase() == skillName,
      orElse: () => throw FormatException('Unknown skill: $skillName'),
    );
    final lowerLevel = int.parse(results['cliff-level'] as String);
    final upperLevel = lowerLevel + 1;

    await _runCliffDiagnostic(registries, skill, lowerLevel, upperLevel);
    return;
  }

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
    final profile = result.profile;
    if (profile != null) {
      print('');
      _printSolverProfile(profile);
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

// ---------------------------------------------------------------------------
// Cliff Diagnostic Mode
// ---------------------------------------------------------------------------

/// Runs cliff diagnostic comparing two adjacent skill levels.
Future<void> _runCliffDiagnostic(
  Registries registries,
  Skill skill,
  int lowerLevel,
  int upperLevel,
) async {
  print('=== CLIFF DIAGNOSTIC ===');
  print('Comparing ${skill.name}=$lowerLevel vs ${skill.name}=$upperLevel');
  print('');

  // Run solver for lower level
  print('--- Running ${skill.name}=$lowerLevel ---');
  final lowerGoal = ReachSkillLevelGoal(skill, lowerLevel);
  final lowerState = GlobalState.empty(registries);

  final lowerStopwatch = Stopwatch()..start();
  final lowerResult = solve(lowerState, lowerGoal, collectDiagnostics: true);
  lowerStopwatch.stop();
  final lowerTimeMs = lowerStopwatch.elapsedMilliseconds;

  // Run solver for upper level
  print('--- Running ${skill.name}=$upperLevel ---');
  final upperGoal = ReachSkillLevelGoal(skill, upperLevel);
  final upperState = GlobalState.empty(registries);

  final upperStopwatch = Stopwatch()..start();
  final upperResult = solve(upperState, upperGoal, collectDiagnostics: true);
  upperStopwatch.stop();
  final upperTimeMs = upperStopwatch.elapsedMilliseconds;

  // Get profiles from results
  final lowerProfile = switch (lowerResult) {
    SolverSuccess(:final profile) => profile,
    SolverFailed(:final profile) => profile,
  };
  final upperProfile = switch (upperResult) {
    SolverSuccess(:final profile) => profile,
    SolverFailed(:final profile) => profile,
  };

  if (lowerProfile == null || upperProfile == null) {
    print('ERROR: Missing profile data');
    return;
  }

  // Print comparison
  print('');
  print('=== COMPARISON ===');
  print('');

  // Timing
  print('--- Timing ---');
  print(
    'Wall time: ${lowerTimeMs}ms -> ${upperTimeMs}ms '
    '(${_formatDelta(upperTimeMs - lowerTimeMs)}ms, '
    '${_formatRatio(upperTimeMs, lowerTimeMs)}x)',
  );
  print('');

  // Node expansion
  print('--- Node Expansion ---');
  _printComparison(
    'Expanded nodes',
    lowerProfile.expandedNodes,
    upperProfile.expandedNodes,
  );
  _printComparison(
    'Unique bucket keys',
    lowerProfile.uniqueBucketKeys,
    upperProfile.uniqueBucketKeys,
  );
  _printComparison(
    'Dominated skipped',
    lowerProfile.dominatedSkipped,
    upperProfile.dominatedSkipped,
  );
  _printComparison(
    'Peak frontier size',
    lowerProfile.peakQueueSize,
    upperProfile.peakQueueSize,
  );
  _printComparison(
    'Frontier inserted',
    lowerProfile.frontierInserted,
    upperProfile.frontierInserted,
  );
  _printComparison(
    'Frontier removed',
    lowerProfile.frontierRemoved,
    upperProfile.frontierRemoved,
  );
  print('');

  // Branching
  print('--- Branching ---');
  _printComparisonDouble(
    'Avg branching factor',
    lowerProfile.avgBranchingFactor,
    upperProfile.avgBranchingFactor,
  );
  _printComparison(
    'Total neighbors',
    lowerProfile.totalNeighborsGenerated,
    upperProfile.totalNeighborsGenerated,
  );
  print('');

  // Heuristic health
  print('--- Heuristic Health ---');
  _printComparison(
    'Min h',
    lowerProfile.minHeuristic,
    upperProfile.minHeuristic,
  );
  _printComparison(
    'Median h',
    lowerProfile.medianHeuristic,
    upperProfile.medianHeuristic,
  );
  _printComparison(
    'Max h',
    lowerProfile.maxHeuristic,
    upperProfile.maxHeuristic,
  );
  _printComparison(
    'h spread',
    lowerProfile.heuristicSpread,
    upperProfile.heuristicSpread,
  );
  _printComparisonDouble(
    'Zero rate fraction',
    lowerProfile.zeroRateFraction,
    upperProfile.zeroRateFraction,
  );
  print('');

  // Decision deltas
  print('--- Decision Deltas ---');
  _printComparison('Min delta', lowerProfile.minDelta, upperProfile.minDelta);
  _printComparison(
    'Median delta',
    lowerProfile.medianDelta,
    upperProfile.medianDelta,
  );
  _printComparison('P95 delta', lowerProfile.p95Delta, upperProfile.p95Delta);
  print('');

  // Time breakdown
  print('--- Time Breakdown ---');
  _printComparisonDouble(
    'Advance %',
    lowerProfile.advancePercent,
    upperProfile.advancePercent,
  );
  _printComparisonDouble(
    'Enumerate %',
    lowerProfile.enumeratePercent,
    upperProfile.enumeratePercent,
  );
  _printComparisonDouble(
    'Hashing %',
    lowerProfile.hashingPercent,
    upperProfile.hashingPercent,
  );
  print('');

  // Macro stop triggers
  if (lowerProfile.macroStopTriggers.isNotEmpty ||
      upperProfile.macroStopTriggers.isNotEmpty) {
    print('--- Macro Stop Triggers ---');
    final allTriggers = <String>{
      ...lowerProfile.macroStopTriggers.keys,
      ...upperProfile.macroStopTriggers.keys,
    };
    for (final trigger in allTriggers) {
      final lower = lowerProfile.macroStopTriggers[trigger] ?? 0;
      final upper = upperProfile.macroStopTriggers[trigger] ?? 0;
      _printComparison(trigger, lower, upper);
    }
    print('');
  }

  // Candidate stats summary
  if (lowerProfile.candidateStatsHistory.isNotEmpty ||
      upperProfile.candidateStatsHistory.isNotEmpty) {
    print('--- Candidate Stats (last sample) ---');
    final lowerStats = lowerProfile.candidateStatsHistory.isNotEmpty
        ? lowerProfile.candidateStatsHistory.last
        : null;
    final upperStats = upperProfile.candidateStatsHistory.isNotEmpty
        ? upperProfile.candidateStatsHistory.last
        : null;

    if (lowerStats != null || upperStats != null) {
      _printComparison(
        'Burn actions considered',
        lowerStats?.burnActionsConsidered ?? 0,
        upperStats?.burnActionsConsidered ?? 0,
      );
      _printComparison(
        'Producer actions considered',
        lowerStats?.producerActionsConsidered ?? 0,
        upperStats?.producerActionsConsidered ?? 0,
      );
      _printComparison(
        'Pairs considered',
        lowerStats?.pairsConsidered ?? 0,
        upperStats?.pairsConsidered ?? 0,
      );
      _printComparison(
        'Pairs kept',
        lowerStats?.pairsKept ?? 0,
        upperStats?.pairsKept ?? 0,
      );
      print('');

      // Print top pairs for each
      if (lowerStats != null && lowerStats.topPairs.isNotEmpty) {
        print('Top pairs at level $lowerLevel:');
        for (final pair in lowerStats.topPairs) {
          print(
            '  ${pair.burnId} + ${pair.producerId}: '
            '${pair.score.toStringAsFixed(4)} XP/tick',
          );
        }
      }
      if (upperStats != null && upperStats.topPairs.isNotEmpty) {
        print('Top pairs at level $upperLevel:');
        for (final pair in upperStats.topPairs) {
          print(
            '  ${pair.burnId} + ${pair.producerId}: '
            '${pair.score.toStringAsFixed(4)} XP/tick',
          );
        }
      }
      print('');
    }
  }

  // Newly eligible actions at level boundary
  print('--- Actions Eligible at Level $upperLevel ---');
  _printNewlyEligibleActions(registries, skill, lowerLevel, upperLevel);
  print('');

  // Result summary
  print('--- Result Summary ---');
  _printResultSummary('Level $lowerLevel', lowerResult);
  _printResultSummary('Level $upperLevel', upperResult);
}

void _printComparison(String label, int lower, int upper) {
  final delta = upper - lower;
  print(
    '$label: $lower -> $upper '
    '(${_formatDelta(delta)}, ${_formatRatio(upper, lower)}x)',
  );
}

void _printComparisonDouble(String label, double lower, double upper) {
  final delta = upper - lower;
  print(
    '$label: ${lower.toStringAsFixed(2)} -> ${upper.toStringAsFixed(2)} '
    '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)})',
  );
}

String _formatDelta(int delta) => delta >= 0 ? '+$delta' : '$delta';

String _formatRatio(int upper, int lower) {
  if (lower == 0) return upper == 0 ? '1.00' : 'inf';
  return (upper / lower).toStringAsFixed(2);
}

void _printResultSummary(String label, SolverResult result) {
  if (result is SolverSuccess) {
    final plan = result.plan;
    print(
      '$label: SUCCESS - ${plan.totalTicks} ticks, '
      '${plan.steps.length} steps',
    );
  } else if (result is SolverFailed) {
    print('$label: FAILED - ${result.failure.reason}');
  }
}

void _printNewlyEligibleActions(
  Registries registries,
  Skill skill,
  int lowerLevel,
  int upperLevel,
) {
  // Find actions that unlock at upperLevel
  final newlyUnlocked = <String>[];

  for (final action in registries.actions.forSkill(skill)) {
    if (action.unlockLevel > lowerLevel && action.unlockLevel <= upperLevel) {
      newlyUnlocked.add('${action.name} (unlocks at ${action.unlockLevel})');
    }
  }

  if (newlyUnlocked.isEmpty) {
    print('  No new actions unlock at level $upperLevel');
  } else {
    for (final action in newlyUnlocked) {
      print('  NEW: $action');
    }
  }

  // For consuming skills, also check producers
  if (skill.isConsuming) {
    // Find the producer skill (woodcutting for firemaking)
    final producerSkill = skill == Skill.firemaking
        ? Skill.woodcutting
        : skill == Skill.cooking
        ? Skill.fishing
        : null;

    if (producerSkill != null) {
      print('  (Producer skill: ${producerSkill.name})');
    }
  }
}
