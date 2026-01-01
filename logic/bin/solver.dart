// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//        dart run bin/solver.dart -s  # Solve for firemaking level 30
//        dart run bin/solver.dart --cliff  # Diagnose FM=55 vs FM=56 cliff
//        dart run bin/solver.dart -d  # Solve with diagnostics enabled
//
// Example: dart run bin/solver.dart 1000
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:args/args.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';
import 'package:logic/src/solver/solver_profile.dart';

final _parser = ArgParser()
  ..addFlag('skill', abbr: 's', help: 'Solve for firemaking level 30')
  ..addOption(
    'skills',
    abbr: 'm',
    help: 'Solve for multiple skills (e.g., "Woodcutting=50,Firemaking=50")',
  )
  ..addFlag(
    'diagnostics',
    abbr: 'd',
    help: 'Collect and print solver diagnostics (works with both modes)',
    negatable: false,
  )
  ..addFlag(
    'offline',
    help: 'Use single-shot solve (debug/benchmark mode, disables segments)',
    negatable: false,
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
  )
  ..addFlag(
    'verbose',
    abbr: 'v',
    help: 'Print step-by-step progress during execution',
    negatable: false,
  );

void main(List<String> args) async {
  final results = _parser.parse(args);

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

  final goal = _parseGoalFromArgs(results);
  print('Goal: ${goal.describe()}');

  final initialState = GlobalState.empty(registries);
  final collectDiagnostics = results['diagnostics'] as bool;
  final useOfflineMode = results['offline'] as bool;
  final verboseExecution = results['verbose'] as bool;

  // Default: segment-based solving. --offline enables single-shot mode.
  if (useOfflineMode) {
    // Single-shot solve (debug/benchmark mode)
    print(
      'Solving (offline/single-shot mode)'
      '${collectDiagnostics ? ' with diagnostics' : ''}...',
    );
    final stopwatch = Stopwatch()..start();
    final result = solve(
      initialState,
      goal,
      collectDiagnostics: collectDiagnostics,
    );
    stopwatch.stop();

    print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
    print('');

    _printSolverResult(
      result,
      initialState: initialState,
      goal: goal,
      registries: registries,
      collectDiagnostics: collectDiagnostics,
    );
  } else {
    // Segment-based solving (default)
    print(
      'Solving via segments'
      '${collectDiagnostics ? ' with diagnostics' : ''}...',
    );
    final stopwatch = Stopwatch()..start();
    final result = solveToGoal(
      initialState,
      goal,
      collectDiagnostics: collectDiagnostics,
    );
    stopwatch.stop();

    print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
    print('');

    _printSegmentedResult(
      result,
      initialState,
      goal,
      registries,
      collectDiagnostics: collectDiagnostics,
      verboseExecution: verboseExecution,
    );
  }
}

void _printSolverResult(
  SolverResult result, {
  required GlobalState initialState,
  required Goal goal,
  required Registries registries,
  required bool collectDiagnostics,
}) {
  if (result is SolverSuccess) {
    _printSuccess(result, initialState, goal, registries);
  } else if (result is SolverFailed) {
    _printFailure(result);
  }

  final profile = result.profile;
  if (profile != null) {
    print('');
    _printSolverProfile(profile, extended: collectDiagnostics);
  }
}

void _printSuccess(
  SolverSuccess result,
  GlobalState initialState,
  Goal goal,
  Registries registries,
) {
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
  print('Executing plan...');
  final stopwatch = Stopwatch()..start();
  final execResult = executePlan(initialState, result.plan, random: Random(42));
  stopwatch.stop();
  print('Execution completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');
  _printFinalState(execResult.finalState);
  if (goal is MultiSkillGoal) {
    _printMultiSkillProgress(execResult.finalState, goal);
  }
  print('');
  print('=== Execution Stats ===');
  print('Planned: ${durationStringWithTicks(execResult.plannedTicks)}');
  print('Actual: ${durationStringWithTicks(execResult.actualTicks)}');
  print('Delta: ${signedDurationStringWithTicks(execResult.ticksDelta)}');
  print(
    'Deaths: ${execResult.totalDeaths} actual, '
    '${result.plan.expectedDeaths} expected',
  );
}

void _printFailure(SolverFailed result) {
  print('FAILED: ${result.failure.reason}');
  print('  Expanded nodes: ${result.failure.expandedNodes}');
  print('  Enqueued nodes: ${result.failure.enqueuedNodes}');
  if (result.failure.bestCredits != null) {
    print('  Best credits reached: ${result.failure.bestCredits}');
  }
}

/// Prints the final state after executing the plan.
void _printFinalState(GlobalState state) {
  print('=== Final State ===');
  print('GP: ${preciseNumberString(state.gp)}');
  print('');

  // Print skill levels
  print('Skills:');
  for (final skill in Skill.values) {
    final skillState = state.skillState(skill);
    if (skillState.skillLevel > 1 || skillState.xp > 0) {
      print(
        '  ${skill.name}: Level ${skillState.skillLevel} '
        '(${preciseNumberString(skillState.xp)} XP)',
      );
    }
  }

  // Print inventory if not empty
  if (state.inventory.items.isNotEmpty) {
    print('');
    print('Inventory:');
    for (final stack in state.inventory.items) {
      print('  ${stack.item.name}: ${preciseNumberString(stack.count)}');
    }
    final totalValue = state.inventory.items.fold<int>(
      0,
      (sum, stack) => sum + stack.sellsFor,
    );
    print('Total value: ${preciseNumberString(totalValue)} GP');
  }
}

void _printSolverProfile(SolverProfile profile, {bool extended = false}) {
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
  print('  cache key compute: ${profile.cacheKeyPercent.toStringAsFixed(1)}%');
  print('  hashing (_stateKey): ${profile.hashingPercent.toStringAsFixed(1)}%');
  print('Dominance pruning:');
  print('  dominated skipped: ${profile.dominatedSkipped}');
  print('Candidate cache:');
  final cacheTotal = profile.cache.hits + profile.cache.misses;
  final cacheHitRate = cacheTotal > 0
      ? (profile.cache.hits / cacheTotal * 100).toStringAsFixed(1)
      : '0.0';
  print(
    '  hits: ${profile.cache.hits}, '
    'misses: ${profile.cache.misses}, '
    'hit rate: $cacheHitRate%',
  );

  // Extended diagnostics (only when --diagnostics flag is used)
  if (!extended) return;

  print('');
  print('=== Extended Diagnostics ===');
  print('Unique bucket keys: ${profile.uniqueBucketKeys}');
  print('Peak queue size: ${profile.peakQueueSize}');
  print('Frontier inserted: ${profile.frontier.inserted}');
  print('Frontier removed: ${profile.frontier.removed}');

  // Heuristic health
  if (profile.heuristicValues.isNotEmpty) {
    print('');
    print('Heuristic health:');
    print('  Root bestRate: ${profile.rootBestRate?.toStringAsFixed(4)}');
    print(
      '  bestRate range: ${profile.minBestRate.toStringAsFixed(2)} - '
      '${profile.maxBestRate.toStringAsFixed(2)} '
      '(median: ${profile.medianBestRate.toStringAsFixed(2)})',
    );
    final hSorted = List<int>.from(profile.heuristicValues)..sort();
    final minH = hSorted.first;
    final maxH = hSorted.last;
    final medH = hSorted[hSorted.length ~/ 2];
    print('  h() range: $minH - $maxH (median: $medH)');
    if (profile.zeroRateCount > 0) {
      final zeroFrac = profile.zeroRateCount / profile.heuristicValues.length;
      print('  Zero rate fraction: ${zeroFrac.toStringAsFixed(2)}');
    }
  }

  // Why bestRate is zero
  if (profile.rateZeroReasonCounts.isNotEmpty) {
    print('');
    print('Why bestRate == 0:');
    for (final entry in profile.rateZeroReasonCounts.entries) {
      print('  ${entry.key}: ${entry.value}');
    }
  }

  // Consuming skill candidate stats
  if (profile.candidateStatsHistory.isNotEmpty) {
    print('');
    print('Consuming skill candidate stats (last sample):');
    final stats = profile.candidateStatsHistory.last;
    print('  Consumer actions considered: ${stats.consumerActionsConsidered}');
    print('  Producer actions considered: ${stats.producerActionsConsidered}');
    print('  Pairs considered: ${stats.pairsConsidered}');
    print('  Pairs kept: ${stats.pairsKept}');
    if (stats.topPairs.isNotEmpty) {
      print('  Top pairs:');
      for (final pair in stats.topPairs) {
        print(
          '    ${pair.consumerId} + ${pair.producerId}: '
          '${pair.score.toStringAsFixed(4)} XP/tick',
        );
      }
    }
  }

  // Macro stop triggers
  if (profile.macroStopTriggers.isNotEmpty) {
    print('');
    print('Macro stop triggers:');
    final sorted = profile.macroStopTriggers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      print('  ${entry.key}: ${entry.value}');
    }
  }
}

/// Prints aggregate diagnostics for segment-based solving.
void _printSegmentedDiagnostics(
  List<SolverProfile> profiles, {
  bool extended = false,
}) {
  // Aggregate stats across all segments
  final totalNodes = profiles.fold(0, (sum, p) => sum + p.expandedNodes);
  final totalNeighbors = profiles.fold(
    0,
    (sum, p) => sum + p.totalNeighborsGenerated,
  );
  final totalTimeUs = profiles.fold(0, (sum, p) => sum + p.totalTimeUs);

  print('=== Aggregate Solver Profile ===');
  print('Total expanded nodes: $totalNodes');
  print('Total neighbors generated: $totalNeighbors');
  if (totalTimeUs > 0) {
    final nodesPerSec = totalNodes / (totalTimeUs / 1e6);
    print('Overall nodes/sec: ${nodesPerSec.toStringAsFixed(1)}');
  }
  print(
    'Avg branching factor: '
    '${(totalNeighbors / totalNodes).toStringAsFixed(2)}',
  );

  // Extended: per-segment breakdown
  if (!extended) return;

  print('');
  print('=== Per-Segment Diagnostics ===');
  for (var i = 0; i < profiles.length; i++) {
    final p = profiles[i];
    print(
      'Segment ${i + 1}: ${p.expandedNodes} nodes, '
      '${p.nodesPerSecond.toStringAsFixed(0)} nodes/sec, '
      'branching ${p.avgBranchingFactor.toStringAsFixed(2)}',
    );
  }

  // Aggregate heuristic health across segments
  final allBestRates = profiles.expand((p) => p.bestRateSamples).toList();
  if (allBestRates.isNotEmpty) {
    allBestRates.sort();
    final minRate = allBestRates.first;
    final maxRate = allBestRates.last;
    final medRate = allBestRates[allBestRates.length ~/ 2];
    print('');
    print('Aggregate heuristic health:');
    print(
      '  bestRate range: ${minRate.toStringAsFixed(2)} - '
      '${maxRate.toStringAsFixed(2)} (median: ${medRate.toStringAsFixed(2)})',
    );
  }

  // Aggregate macro stop triggers
  final allTriggers = <String, int>{};
  for (final p in profiles) {
    for (final entry in p.macroStopTriggers.entries) {
      allTriggers[entry.key] = (allTriggers[entry.key] ?? 0) + entry.value;
    }
  }
  if (allTriggers.isNotEmpty) {
    print('');
    print('Aggregate macro stop triggers:');
    final sorted = allTriggers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      print('  ${entry.key}: ${entry.value}');
    }
  }
}

/// Parses the goal from command-line arguments.
Goal _parseGoalFromArgs(ArgResults results) {
  if (results['skills'] != null) {
    return _parseMultiSkillGoal(results['skills'] as String);
  } else if (results['skill'] as bool) {
    return const ReachSkillLevelGoal(Skill.firemaking, 30);
  } else {
    // Parse gold goal from remaining args, default to 100 GP
    final goalCredits = results.rest.isNotEmpty
        ? int.tryParse(results.rest[0]) ?? 100
        : 100;
    return ReachGpGoal(goalCredits);
  }
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

/// Prints the result of segment-based solving.
void _printSegmentedResult(
  SegmentedSolverResult result,
  GlobalState initialState,
  Goal goal,
  Registries registries, {
  bool collectDiagnostics = false,
  bool verboseExecution = false,
}) {
  switch (result) {
    case SegmentedSuccess(
      :final segments,
      :final totalTicks,
      :final totalReplanCount,
      :final segmentProfiles,
    ):
      print('=== Segment-Based Solver Result ===');
      print('Total segments: ${segments.length}');
      print('Replan count: $totalReplanCount');
      print('Total ticks: $totalTicks');
      print('');

      // Print segment summaries with optional per-segment diagnostics
      print('--- Segment Boundaries ---');
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final boundary = segment.stopBoundary;
        final ticks = segment.totalTicks;
        final steps = segment.steps.length;

        // Include expanded nodes if diagnostics available
        final profile = i < segmentProfiles.length ? segmentProfiles[i] : null;
        final nodeInfo = profile != null
            ? ' (${profile.expandedNodes} nodes)'
            : '';

        print(
          '  Segment ${i + 1}: $steps steps, $ticks ticks$nodeInfo '
          '-> ${boundary.describe()}',
        );
        // Print step details
        ActionId? currentAction;
        for (var j = 0; j < segment.steps.length; j++) {
          final step = segment.steps[j];
          final formatted = _formatStepForSegment(
            step,
            registries,
            currentAction,
          );
          print('    Step ${j + 1}: $formatted');
          // Track current action for context in wait steps
          if (step case InteractionStep(:final interaction)) {
            if (interaction case SwitchActivity(:final actionId)) {
              currentAction = actionId;
            }
          } else if (step case MacroStep(:final macro)) {
            if (macro case TrainSkillUntil(:final actionId)) {
              currentAction = actionId;
            }
          }
        }
      }
      print('');

      // Stitch segments into a full plan
      final plan = Plan.fromSegments(segments);

      // Print full plan
      print('=== Stitched Plan ===');
      print(plan.prettyPrint(actions: registries.actions));
      print('');

      // Execute the stitched plan
      print('Executing stitched plan...');
      final stopwatch = Stopwatch()..start();

      // Track current action for step formatting
      ActionId? currentAction;

      final execResult = executePlan(
        initialState,
        plan,
        random: Random(42),
        onStepComplete: verboseExecution
            ? ({
                required stepIndex,
                required step,
                required plannedTicks,
                required actualTicks,
                required cumulativeActualTicks,
                required cumulativePlannedTicks,
              }) {
                // Update current action tracking
                if (step case InteractionStep(:final interaction)) {
                  if (interaction case SwitchActivity(:final actionId)) {
                    currentAction = actionId;
                  }
                } else if (step case MacroStep(:final macro)) {
                  if (macro case TrainSkillUntil(:final actionId)) {
                    currentAction = actionId;
                  }
                }

                final stepDesc = _formatStepForSegment(
                  step,
                  registries,
                  currentAction,
                );
                final delta = actualTicks - plannedTicks;
                final deltaStr = delta >= 0 ? '+$delta' : '$delta';
                final cumDelta = cumulativeActualTicks - cumulativePlannedTicks;
                final cumDeltaStr = cumDelta >= 0 ? '+$cumDelta' : '$cumDelta';

                // Only print if significant deviation (>10% or >100 ticks)
                final significantDeviation =
                    delta.abs() > 100 ||
                    (plannedTicks > 0 && delta.abs() / plannedTicks > 0.1);

                if (significantDeviation || stepIndex < 5) {
                  print(
                    '  Step ${stepIndex + 1}: $stepDesc '
                    '[actual: $actualTicks, planned: $plannedTicks, '
                    'delta: $deltaStr, cumulative delta: $cumDeltaStr]',
                  );
                }
              }
            : null,
      );
      stopwatch.stop();
      print('Execution completed in ${stopwatch.elapsedMilliseconds}ms');
      print('');

      _printFinalState(execResult.finalState);
      if (goal is MultiSkillGoal) {
        _printMultiSkillProgress(execResult.finalState, goal);
      }
      print('');
      print('=== Execution Stats ===');
      print('Planned: ${durationStringWithTicks(execResult.plannedTicks)}');
      print('Actual: ${durationStringWithTicks(execResult.actualTicks)}');
      print('Delta: ${signedDurationStringWithTicks(execResult.ticksDelta)}');
      print('Deaths: ${execResult.totalDeaths}');

      // Print aggregate diagnostics if collected
      if (segmentProfiles.isNotEmpty) {
        print('');
        _printSegmentedDiagnostics(
          segmentProfiles,
          extended: collectDiagnostics,
        );
      }

    case SegmentedFailed(:final failure, :final completedSegments):
      print('=== Segment-Based Solver FAILED ===');
      print('Reason: ${failure.reason}');
      print('Completed segments before failure: ${completedSegments.length}');
      if (completedSegments.isNotEmpty) {
        print('');
        print('--- Completed Segments ---');
        for (var i = 0; i < completedSegments.length; i++) {
          final segment = completedSegments[i];
          print(
            '  Segment ${i + 1}: ${segment.steps.length} steps, '
            '${segment.totalTicks} ticks -> ${segment.stopBoundary.describe()}',
          );
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Cliff Diagnostic Mode
// ---------------------------------------------------------------------------

/// Result of running the solver with timing information.
class _TimedSolverResult {
  _TimedSolverResult({
    required this.goal,
    required this.state,
    required this.result,
    required this.elapsedMs,
  });

  final Goal goal;
  final GlobalState state;
  final SolverResult result;
  final int elapsedMs;

  /// The solver profile (requires collectDiagnostics: true).
  SolverProfile? get profile => result.profile;

  /// Macro stop trigger keys from the profile.
  Iterable<String> get macroStopTriggerKeys =>
      profile?.macroStopTriggers.keys ?? const [];

  /// Get a macro stop trigger count by key.
  int macroStopTrigger(String key) => profile?.macroStopTriggers[key] ?? 0;

  /// Rate zero reason types from the profile.
  Iterable<Type> get rateZeroReasonTypes =>
      profile?.rateZeroReasonCounts.keys ?? const [];

  /// The last candidate stats sample, if any.
  CandidateStats? get lastCandidateStats =>
      profile?.candidateStatsHistory.lastOrNull;

  /// Root best rate from the profile.
  double? get rootBestRate => profile?.rootBestRate;
}

/// Runs the solver for a skill level goal and returns the result with timing.
_TimedSolverResult _solveWithTiming(
  Registries registries,
  Skill skill,
  int level,
) {
  final goal = ReachSkillLevelGoal(skill, level);
  final state = GlobalState.empty(registries);

  final stopwatch = Stopwatch()..start();
  final result = solve(state, goal, collectDiagnostics: true);
  stopwatch.stop();

  return _TimedSolverResult(
    goal: goal,
    state: state,
    result: result,
    elapsedMs: stopwatch.elapsedMilliseconds,
  );
}

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
  final lower = _solveWithTiming(registries, skill, lowerLevel);

  // Run solver for upper level
  print('--- Running ${skill.name}=$upperLevel ---');
  final upper = _solveWithTiming(registries, skill, upperLevel);

  // Verify profiles exist
  if (lower.profile == null || upper.profile == null) {
    print('ERROR: Missing profile data');
    return;
  }

  // Local helpers that capture the profiles.
  void compare(String label, int Function(SolverProfile) selector) =>
      _printComparison(label, lower.profile!, upper.profile!, selector);
  void compareDouble(String label, double Function(SolverProfile) selector) =>
      _printComparisonDouble(label, lower.profile!, upper.profile!, selector);
  void compareTrigger(String trigger) => _printComparisonRaw(
    trigger,
    lower.macroStopTrigger(trigger),
    upper.macroStopTrigger(trigger),
  );

  // Print comparison
  print('');
  print('=== COMPARISON ===');
  print('');

  // Timing
  print('--- Timing ---');
  print(
    'Wall time: ${lower.elapsedMs}ms -> ${upper.elapsedMs}ms '
    '(${_formatDelta(upper.elapsedMs - lower.elapsedMs)}ms, '
    '${_formatRatio(upper.elapsedMs, lower.elapsedMs)}x)',
  );
  print('');

  // Node expansion
  print('--- Node Expansion ---');
  compare('Expanded nodes', (p) => p.expandedNodes);
  compare('Unique bucket keys', (p) => p.uniqueBucketKeys);
  compare('Dominated skipped', (p) => p.dominatedSkipped);
  compare('Peak frontier size', (p) => p.peakQueueSize);
  compare('Frontier inserted', (p) => p.frontier.inserted);
  compare('Frontier removed', (p) => p.frontier.removed);
  print('');

  // Branching
  print('--- Branching ---');
  compareDouble('Avg branching factor', (p) => p.avgBranchingFactor);
  compare('Total neighbors', (p) => p.totalNeighborsGenerated);
  print('');

  // Heuristic health
  print('--- Heuristic Health ---');
  compare('Min h', (p) => p.minHeuristic);
  compare('Median h', (p) => p.medianHeuristic);
  compare('Max h', (p) => p.maxHeuristic);
  compare('h spread', (p) => p.heuristicSpread);
  compareDouble('Zero rate fraction', (p) => p.zeroRateFraction);
  print('');

  // Best rate diagnostics
  print('--- Best Rate (heuristic input) ---');
  print(
    'Root bestRate: ${lower.rootBestRate?.toStringAsFixed(4) ?? "?"} '
    '-> ${upper.rootBestRate?.toStringAsFixed(4) ?? "?"}',
  );
  compareDouble('Min bestRate', (p) => p.minBestRate);
  compareDouble('Median bestRate', (p) => p.medianBestRate);
  compareDouble('Max bestRate', (p) => p.maxBestRate);
  print('');

  // Why bestRate is zero counters
  final zeroReasonTypes = <Type>{
    ...lower.rateZeroReasonTypes,
    ...upper.rateZeroReasonTypes,
  };
  if (zeroReasonTypes.isNotEmpty) {
    print('--- Why bestRate == 0 ---');
    for (final type in zeroReasonTypes) {
      compare('$type', (p) => p.rateZeroReasonCounts[type] ?? 0);
    }
    print('');
  }

  // Decision deltas
  print('--- Decision Deltas ---');
  compare('Min delta', (p) => p.minDelta);
  compare('Median delta', (p) => p.medianDelta);
  compare('P95 delta', (p) => p.p95Delta);
  print('');

  // Time breakdown
  print('--- Time Breakdown ---');
  compareDouble('Advance %', (p) => p.advancePercent);
  compareDouble('Enumerate %', (p) => p.enumeratePercent);
  compareDouble('Hashing %', (p) => p.hashingPercent);
  print('');

  // Macro stop triggers
  final triggers = <String>{
    ...lower.macroStopTriggerKeys,
    ...upper.macroStopTriggerKeys,
  };
  if (triggers.isNotEmpty) {
    print('--- Macro Stop Triggers ---');
    triggers.forEach(compareTrigger);
    print('');
  }

  // Candidate stats summary
  final lowerStats = lower.lastCandidateStats;
  final upperStats = upper.lastCandidateStats;
  if (lowerStats != null || upperStats != null) {
    print('--- Candidate Stats (last sample) ---');

    void compareStats(String label, int? Function(CandidateStats?) selector) =>
        _printComparisonRaw(
          label,
          selector(lowerStats) ?? 0,
          selector(upperStats) ?? 0,
        );

    compareStats(
      'Consumer actions considered',
      (s) => s?.consumerActionsConsidered,
    );
    compareStats(
      'Producer actions considered',
      (s) => s?.producerActionsConsidered,
    );
    compareStats('Pairs considered', (s) => s?.pairsConsidered);
    compareStats('Pairs kept', (s) => s?.pairsKept);
    print('');

    void printTopPairs(CandidateStats? stats, int level) {
      if (stats == null) return;
      if (stats.topPairs.isNotEmpty) {
        print('Top pairs at level $level:');
        for (final pair in stats.topPairs) {
          print(
            '  ${pair.consumerId} + ${pair.producerId}: '
            '${pair.score.toStringAsFixed(4)} XP/tick',
          );
        }
      }
    }

    // Print top pairs for each
    printTopPairs(lowerStats, lowerLevel);
    printTopPairs(upperStats, upperLevel);
    print('');
  }

  // Newly eligible actions at level boundary
  print('--- Actions Eligible at Level $upperLevel ---');
  _printNewlyEligibleActions(registries, skill, lowerLevel, upperLevel);
  print('');

  // Result summary
  print('--- Result Summary ---');
  _printResultSummary('Level $lowerLevel', lower.result);
  _printResultSummary('Level $upperLevel', upper.result);
}

void _printComparison(
  String label,
  SolverProfile lower,
  SolverProfile upper,
  int Function(SolverProfile) selector,
) {
  final lowerVal = selector(lower);
  final upperVal = selector(upper);
  final delta = upperVal - lowerVal;
  print(
    '$label: $lowerVal -> $upperVal '
    '(${_formatDelta(delta)}, ${_formatRatio(upperVal, lowerVal)}x)',
  );
}

void _printComparisonDouble(
  String label,
  SolverProfile lower,
  SolverProfile upper,
  double Function(SolverProfile) selector,
) {
  final lowerVal = selector(lower);
  final upperVal = selector(upper);
  final delta = upperVal - lowerVal;
  print(
    '$label: ${lowerVal.toStringAsFixed(2)} -> ${upperVal.toStringAsFixed(2)} '
    '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)})',
  );
}

void _printComparisonRaw(String label, int lower, int upper) {
  final delta = upper - lower;
  print(
    '$label: $lower -> $upper '
    '(${_formatDelta(delta)}, ${_formatRatio(upper, lower)}x)',
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

/// Formats a sell policy for display.
String _formatSellPolicy(SellPolicy policy) {
  return switch (policy) {
    SellAllPolicy() => 'Sell all',
    SellExceptPolicy(:final keepItems) => () {
      final names = keepItems.map((id) => id.name).toList()..sort();
      if (names.length <= 3) {
        return 'Sell all except ${names.join(', ')}';
      }
      return 'Sell all except ${names.length} items '
          '(${names.take(3).join(', ')}, ...)';
    }(),
  };
}

/// Formats a plan step for segment display.
String _formatStepForSegment(
  PlanStep step,
  Registries registries,
  ActionId? currentAction,
) {
  return switch (step) {
    InteractionStep(:final interaction) => switch (interaction) {
      SwitchActivity(:final actionId) => () {
        final action = registries.actions.byId(actionId);
        final actionName = action.name;
        return 'Switch to $actionName';
      }(),
      BuyShopItem(:final purchaseId) => 'Buy ${purchaseId.name}',
      SellItems(:final policy) => _formatSellPolicy(policy),
    },
    WaitStep(:final deltaTicks, :final waitFor) => () {
      final actionName = currentAction != null
          ? registries.actions.byId(currentAction).name
          : null;
      final prefix = actionName ?? 'Wait';
      return '$prefix $deltaTicks ticks -> ${waitFor.shortDescription}';
    }(),
    MacroStep(:final macro, :final deltaTicks) => switch (macro) {
      TrainSkillUntil(:final skill) => '${skill.name} for $deltaTicks ticks',
      TrainConsumingSkillUntil(:final consumingSkill) =>
        '${consumingSkill.name} for $deltaTicks ticks',
      AcquireItem(:final itemId, :final quantity) =>
        'Acquire ${quantity}x $itemId ($deltaTicks ticks)',
      EnsureStock(:final itemId, :final minTotal) =>
        'EnsureStock ${itemId.name}: $minTotal ($deltaTicks ticks)',
    },
  };
}
