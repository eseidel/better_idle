// Entry point for the solver - solves for an optimal plan to reach a goal.
//
// Usage: dart run bin/solver.dart [goal_credits]
//        dart run bin/solver.dart -s  # Solve for firemaking level 30
//        dart run bin/solver.dart -a  # Solve all skills to level 99
//        dart run bin/solver.dart --cliff  # Diagnose FM=55 vs FM=56 cliff
//        dart run bin/solver.dart -d  # Solve with diagnostics enabled
//
// Example: dart run bin/solver.dart 1000
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:args/args.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/core/solver_profile.dart';
import 'package:logic/src/solver/execution/execute_plan.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/execution/utils.dart';
import 'package:logic/src/solver/interactions/interaction.dart';

final _parser = ArgParser()
  ..addFlag('skill', abbr: 's', help: 'Solve for firemaking level 30')
  ..addOption(
    'skills',
    abbr: 'm',
    help: 'Solve for multiple skills (e.g., "Woodcutting=50,Firemaking=50")',
  )
  ..addFlag(
    'all',
    abbr: 'a',
    help: 'Solve all skills to level 99',
    negatable: false,
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
  )
  ..addOption(
    'verbose-segment',
    help: 'Show full step list for specific segment number (1-indexed)',
  )
  ..addFlag(
    'dump-stop-triggers',
    help: 'Print full histogram of macro stop triggers (default: top 10)',
    negatable: false,
  )
  ..addFlag(
    'no-execute',
    help: 'Skip plan execution (only output the plan)',
    negatable: false,
  )
  ..addOption(
    'output-plan',
    abbr: 'o',
    help:
        'Write the plan to a JSON file (e.g., plan.json). '
        'Implies --no-execute unless -v is also specified.',
  );

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Skills included in the "All=99" mode.
/// This list can be easily edited to add or remove skills.
const List<Skill> allSkillsFor99 = [
  Skill.woodcutting,
  Skill.fishing,
  Skill.firemaking,
  Skill.cooking,
  // Skill.mining,
  // Skill.smithing,
  // Skill.fletching,
  // Skill.crafting,
  // Skill.runecrafting,
  // Skill.thieving,
  // Skill.herblore,
];

// ---------------------------------------------------------------------------
// Solver Configuration
// ---------------------------------------------------------------------------

/// Configuration for the solver run.
class SolverConfig {
  SolverConfig({
    required this.goal,
    required this.initialState,
    required this.random,
    required this.collectDiagnostics,
    required this.verboseExecution,
    required this.dumpStopTriggers,
    required this.noExecute,
    this.verboseSegment,
    this.outputPlanPath,
  });

  final Goal goal;
  final GlobalState initialState;
  final Random random;
  final bool collectDiagnostics;
  final bool verboseExecution;
  final int? verboseSegment;
  final bool dumpStopTriggers;
  final bool noExecute;
  final String? outputPlanPath;

  Registries get registries => initialState.registries;
}

/// Result of running the solver (either mode).
class SolvedPlan {
  SolvedPlan({required this.plan, required this.profiles, this.segments});

  final Plan plan;
  final List<SolverProfile> profiles;

  /// Segments (only for online/segmented mode).
  final List<Segment>? segments;

  bool get isSegmented => segments != null;
}

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

  // Parse configuration
  final goal = _parseGoalFromArgs(results);
  final verboseSegmentStr = results['verbose-segment'] as String?;
  final outputPlanPath = results['output-plan'] as String?;
  // Skip execution when outputting a plan file (unless verbose execution is
  // requested, which implies the user wants to see execution details)
  final noExecute =
      (results['no-execute'] as bool) ||
      (outputPlanPath != null && !(results['verbose'] as bool));
  final config = SolverConfig(
    goal: goal,
    initialState: GlobalState.empty(registries),
    random: Random(42),
    collectDiagnostics: results['diagnostics'] as bool,
    verboseExecution: results['verbose'] as bool,
    verboseSegment: verboseSegmentStr != null
        ? int.tryParse(verboseSegmentStr)
        : null,
    dumpStopTriggers: results['dump-stop-triggers'] as bool,
    noExecute: noExecute,
    outputPlanPath: outputPlanPath,
  );

  print('Goal: ${goal.describe()}');

  // Run solver (offline or online mode)
  final useOfflineMode = results['offline'] as bool;
  final solvedPlan = useOfflineMode
      ? _runOfflineSolver(config)
      : _runOnlineSolver(config);

  // Handle failure
  if (solvedPlan == null) return;

  // Print the plan
  _printPlan(solvedPlan, config);

  // Execute the plan (unless --no-execute)
  if (!config.noExecute) {
    _executePlan(solvedPlan, config);
  }

  // Print diagnostics
  if (solvedPlan.profiles.isNotEmpty) {
    print('');
    _printDiagnostics(solvedPlan, config);
  }

  // Write plan to JSON if requested
  if (config.outputPlanPath != null) {
    writePlanToJson(solvedPlan.plan, config.outputPlanPath!);
  }
}

// ---------------------------------------------------------------------------
// Solver Runners
// ---------------------------------------------------------------------------

/// Runs the offline (single-shot) solver.
SolvedPlan? _runOfflineSolver(SolverConfig config) {
  print(
    'Solving (offline/single-shot mode)'
    '${config.collectDiagnostics ? ' with diagnostics' : ''}...',
  );

  final stopwatch = Stopwatch()..start();
  final result = solve(
    config.initialState,
    config.goal,
    collectDiagnostics: config.collectDiagnostics,
  );
  stopwatch.stop();

  print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  if (result is SolverFailed) {
    _printFailure(result, config);
    return null;
  }

  final success = result as SolverSuccess;
  return SolvedPlan(
    plan: success.plan,
    profiles: result.profile != null ? [result.profile!] : [],
  );
}

/// Runs the online (replanning-based) solver.
SolvedPlan? _runOnlineSolver(SolverConfig config) {
  print(
    'Solving via replanning'
    '${config.collectDiagnostics ? ' with diagnostics' : ''}...',
  );

  final stopwatch = Stopwatch()..start();
  final result = solveWithReplanning(
    config.initialState,
    config.goal,
    random: config.random,
    collectDiagnostics: config.collectDiagnostics,
    config: const ReplanConfig(maxReplans: 100, logReplans: true),
  );
  stopwatch.stop();

  print('Solver completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  if (!result.goalReached) {
    print('=== Replanning Solver FAILED ===');
    print('Reason: ${result.terminatingBoundary?.describe() ?? "Unknown"}');
    print('Completed segments: ${result.segments.length}');
    if (result.segments.isNotEmpty) {
      print('');
      print('--- Completed Segments ---');
      for (var i = 0; i < result.segments.length; i++) {
        final segment = result.segments[i];
        print(
          '  Segment ${i + 1}: ${segment.steps.length} steps, '
          '${segment.actualTicks} ticks -> '
          '${segment.replanBoundary?.describe() ?? "completed"}',
        );
      }
    }
    return null;
  }

  print('=== Replanning Solver Result ===');
  print('Total segments: ${result.segments.length}');
  print('Replan count: ${result.replanCount}');
  print('Total ticks: ${result.totalTicks}');
  print('');

  // Convert ReplanSegmentResult to Segment for printing
  final segments = _convertToSegments(result.segments);
  final profiles = result.segments
      .map((s) => s.profile)
      .whereType<SolverProfile>()
      .toList();

  // Print segment summaries
  _printSegmentSummaries(segments, profiles, config);

  return SolvedPlan(
    plan: Plan.fromSegments(segments),
    profiles: profiles,
    segments: segments,
  );
}

/// Converts ReplanSegmentResult list to Segment list for backward
/// compatibility.
List<Segment> _convertToSegments(List<ReplanSegmentResult> replanSegments) {
  return replanSegments.map((rs) {
    // Convert ReplanBoundary to SegmentBoundary
    final boundary = rs.replanBoundary;
    final segmentBoundary = boundary != null
        ? _convertBoundary(boundary)
        : const GoalReachedBoundary();

    return Segment(
      steps: rs.steps,
      totalTicks: rs.actualTicks,
      interactionCount: rs.steps.whereType<InteractionStep>().length,
      stopBoundary: segmentBoundary,
      sellPolicy: rs.sellPolicy,
    );
  }).toList();
}

/// Converts a ReplanBoundary to a SegmentBoundary.
SegmentBoundary _convertBoundary(ReplanBoundary boundary) {
  // Map ReplanBoundary types to SegmentBoundary types
  return switch (boundary) {
    GoalReached() => const GoalReachedBoundary(),
    UpgradeAffordableEarly(:final purchaseId) => UpgradeAffordableBoundary(
      purchaseId,
      purchaseId.localId,
    ),
    UnlockObserved(:final skill, :final level) =>
      skill != null && level != null
          ? UnlockBoundary(skill, level, '')
          : const GoalReachedBoundary(),
    InputsDepleted(:final actionId, :final missingItemId) =>
      InputsDepletedBoundary(actionId, missingItemId),
    InventoryPressure(:final usedSlots, :final totalSlots) =>
      InventoryPressureBoundary(usedSlots, totalSlots),
    PlannedSegmentStop() => const HorizonCapBoundary(0),
    WaitConditionSatisfied() => const GoalReachedBoundary(),
    _ => const GoalReachedBoundary(),
  };
}

// ---------------------------------------------------------------------------
// Printing
// ---------------------------------------------------------------------------

/// Prints the plan (compressed format).
void _printPlan(SolvedPlan solvedPlan, SolverConfig config) {
  final plan = solvedPlan.plan;
  final compressed = plan.compress();

  print(
    'Plan (compressed ${plan.steps.length} '
    '-> ${compressed.steps.length} steps):',
  );
  print(compressed.prettyPrint(actions: config.registries.actions));
  print('Total ticks: ${compressed.totalTicks}');
  print('Interaction count: ${compressed.interactionCount}');
}

/// Prints skill duration statistics showing time spent per skill.
void _printSkillDurations(
  GlobalState initialState,
  GlobalState finalState,
  Registries registries,
  bool verbose,
) {
  final actionDurations = <ActionId, Tick>{};

  for (final entry in finalState.actionStates.entries) {
    final actionId = entry.key;
    final finalTicks = entry.value.cumulativeTicks;
    final initialTicks = initialState.actionState(actionId).cumulativeTicks;
    final delta = finalTicks - initialTicks;

    if (delta > 0) {
      actionDurations[actionId] = delta;
    }
  }

  if (actionDurations.isEmpty) return;

  // Aggregate by skill
  final skillDurations = <Skill, Tick>{};
  for (final entry in actionDurations.entries) {
    final action = registries.actions.byId(entry.key);
    skillDurations[action.skill] =
        (skillDurations[action.skill] ?? 0) + entry.value;
  }

  print('');
  print('=== Time Spent Per Skill ===');

  final sortedSkills = skillDurations.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  for (final entry in sortedSkills) {
    final timeStr = durationStringWithTicks(entry.value);
    print('  ${entry.key.name}: $timeStr');
  }

  // Print per-action breakdown in verbose mode
  if (verbose) {
    print('');
    print('=== Time Spent Per Action (Verbose) ===');

    final sortedActions = actionDurations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedActions) {
      final action = registries.actions.byId(entry.key);
      final timeStr = durationStringWithTicks(entry.value);
      print('  ${action.name} (${action.skill.name}): $timeStr');
    }
  }
}

/// Executes the plan and prints results.
void _executePlan(SolvedPlan solvedPlan, SolverConfig config) {
  print('');
  print('Executing plan...');

  final stepCompleteContext = _StepCompleteContext();
  final stopwatch = Stopwatch()..start();
  final execResult = executePlan(
    config.initialState,
    solvedPlan.plan,
    random: Random(42),
    onStepComplete: config.verboseExecution
        ? stepCompleteContext.printStepComplete
        : null,
  );
  stopwatch.stop();

  print('Execution completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  printFinalState(execResult.finalState);
  if (config.goal is MultiSkillGoal) {
    _printMultiSkillProgress(
      execResult.finalState,
      config.goal as MultiSkillGoal,
    );
  }
  print('');
  printExecutionStats(
    execResult,
    expectedDeaths: solvedPlan.plan.expectedDeaths,
  );

  // Print skill duration statistics
  _printSkillDurations(
    config.initialState,
    execResult.finalState,
    config.registries,
    config.verboseExecution,
  );
}

/// Prints solver diagnostics/profiles.
void _printDiagnostics(SolvedPlan solvedPlan, SolverConfig config) {
  if (solvedPlan.isSegmented) {
    _printSegmentedDiagnostics(
      solvedPlan.profiles,
      extended: config.collectDiagnostics,
      dumpStopTriggers: config.dumpStopTriggers,
    );
  } else if (solvedPlan.profiles.isNotEmpty) {
    _printSolverProfile(
      solvedPlan.profiles.first,
      extended: config.collectDiagnostics,
      dumpStopTriggers: config.dumpStopTriggers,
    );
  }
}

/// Prints segment summaries for online mode.
void _printSegmentSummaries(
  List<Segment> segments,
  List<SolverProfile> profiles,
  SolverConfig config,
) {
  print('--- Segments ---');
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final profile = i < profiles.length ? profiles[i] : null;

    // Determine if this segment should show full step details
    final isVerboseSegment = config.verboseSegment == i + 1;
    final isWeirdSegment = _isWeirdSegment(segment);
    final showDetails = isVerboseSegment || isWeirdSegment;

    // Print one-line summary
    final summary = _formatSegmentSummary(
      i + 1,
      segment,
      profile,
      config.registries,
    );
    print(summary);

    // Print full step details if requested or weird
    if (showDetails) {
      if (isWeirdSegment && !isVerboseSegment) {
        print('    [auto-expanded: weird segment]');
      }
      ActionId? currentAction;
      for (var j = 0; j < segment.steps.length; j++) {
        final step = segment.steps[j];
        final formatted = describeStep(
          step,
          config.registries,
          currentAction: currentAction,
        );
        print('    ${j + 1}. $formatted');
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
  }
  print('');

  // Print full plan (compact format)
  final plan = Plan.fromSegments(segments);
  print(plan.prettyPrintCompact(actions: config.registries.actions));
}

void _printFailure(SolverFailed result, SolverConfig config) {
  print('FAILED: ${result.failure.reason}');
  print('  Expanded nodes: ${result.failure.expandedNodes}');
  print('  Enqueued nodes: ${result.failure.enqueuedNodes}');
  if (result.failure.bestCredits != null) {
    print('  Best credits reached: ${result.failure.bestCredits}');
  }
}

void _printSolverProfile(
  SolverProfile profile, {
  bool extended = false,
  bool dumpStopTriggers = false,
}) {
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
    print('  Consumer-producer pairs considered: ${stats.pairsConsidered}');
    print('  Consumer-producer pairs kept: ${stats.pairsKept}');
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
    _printMacroStopTriggers(profile.macroStopTriggers, dump: dumpStopTriggers);
  }

  // Prerequisite diagnostics
  _printPrereqDiagnostics(profile);
}

/// Prints prerequisite cache and macro diagnostics.
void _printPrereqDiagnostics(SolverProfile profile) {
  final hasPrereqData =
      profile.prereqCacheHits > 0 ||
      profile.prereqCacheMisses > 0 ||
      profile.prereqMacrosByType.isNotEmpty ||
      profile.blockedChainsByItem.isNotEmpty;

  if (!hasPrereqData) return;

  print('');
  print('=== Prerequisite Diagnostics ===');
  print(
    'Forbidden cache: ${profile.prereqCacheHits} hits, '
    '${profile.prereqCacheMisses} misses',
  );

  if (profile.prereqMacrosByType.isNotEmpty) {
    print('Prerequisite macros by type:');
    for (final entry in profile.prereqMacrosByType.entries) {
      print('  ${entry.key}: ${entry.value}');
    }
  }

  if (profile.blockedChainsByItem.isNotEmpty) {
    print('Blocked chains by item:');
    final sorted = profile.blockedChainsByItem.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted.take(10)) {
      print('  ${entry.key}: ${entry.value}');
    }
    if (sorted.length > 10) {
      print('  ... and ${sorted.length - 10} more');
    }
  }
}

/// Prints macro stop triggers in a compact grouped format.
///
/// Groups triggers by item name and shows:
/// - Top 10 items by count (default)
/// - Percentage of total
/// - Example quantities for each item
///
/// If [dump] is true, prints the full histogram instead.
void _printMacroStopTriggers(Map<String, int> triggers, {bool dump = false}) {
  if (triggers.isEmpty) return;

  final total = triggers.values.fold(0, (sum, v) => sum + v);

  if (dump) {
    // Full histogram mode
    print('Macro stop triggers (full):');
    final sorted = triggers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      final percent = (entry.value / total * 100).toStringAsFixed(1);
      print('  ${entry.key}: ${entry.value} ($percent%)');
    }
    return;
  }

  // Group by item name
  // Triggers are like: "Stock 358x Coal_Ore", "Acquired 10x Oak_Logs"
  final byItem = <String, List<_TriggerEntry>>{};
  for (final entry in triggers.entries) {
    final parsed = _parseTrigger(entry.key);
    byItem
        .putIfAbsent(parsed.itemName, () => [])
        .add(_TriggerEntry(parsed.quantity, entry.value));
  }

  // Sum counts per item
  final itemCounts = <String, int>{};
  for (final entry in byItem.entries) {
    itemCounts[entry.key] = entry.value.fold(0, (sum, e) => sum + e.count);
  }

  // Sort by total count
  final sortedItems = itemCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  print('Stop triggers (top):');

  // Show top 10
  final topItems = sortedItems.take(10);
  for (final item in topItems) {
    final percent = (item.value / total * 100).toStringAsFixed(0);

    // Get example quantities for this item (top 3 by count)
    final examples = byItem[item.key]!
      ..sort((a, b) => b.count.compareTo(a.count));
    final exampleStrings = examples
        .take(3)
        .map((e) => '${e.qty}x:${e.count}')
        .join(', ');

    print('  ${item.key}: $percent% (e.g., $exampleStrings)');
  }

  if (sortedItems.length > 10) {
    final remaining = sortedItems.length - 10;
    final remainingCount = sortedItems
        .skip(10)
        .fold(0, (sum, e) => sum + e.value);
    final remainingPercent = (remainingCount / total * 100).toStringAsFixed(0);
    print('  ... $remaining more items ($remainingPercent%)');
  }
}

/// Parsed trigger info.
class _TriggerEntry {
  _TriggerEntry(this.qty, this.count);
  final String qty;
  final int count;
}

/// Parsed trigger with item name and quantity.
({String itemName, String quantity}) _parseTrigger(String trigger) {
  // Patterns: "Stock 358x Coal_Ore", "Acquired 10x Oak_Logs", "Level 30"
  final stockMatch = RegExp(r'^Stock (\d+)x (\S+)$').firstMatch(trigger);
  if (stockMatch != null) {
    return (itemName: stockMatch.group(2)!, quantity: stockMatch.group(1)!);
  }

  final acquiredMatch = RegExp(r'^Acquired (\d+)x (\S+)$').firstMatch(trigger);
  if (acquiredMatch != null) {
    return (
      itemName: acquiredMatch.group(2)!,
      quantity: acquiredMatch.group(1)!,
    );
  }

  // Fallback: use the whole trigger as item name
  return (itemName: trigger, quantity: '?');
}

/// Parses the goal from command-line arguments.
Goal _parseGoalFromArgs(ArgResults results) {
  if (results['all'] as bool) {
    // Create a MultiSkillGoal with all skills set to level 99
    final skillMap = <Skill, int>{
      for (final skill in allSkillsFor99) skill: 99,
    };
    return MultiSkillGoal.fromMap(skillMap);
  } else if (results['skills'] != null) {
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

class _StepCompleteContext {
  // Track current action for step formatting
  ActionId? currentAction;

  void printStepComplete({
    required int stepIndex,
    required PlanStep step,
    required int plannedTicks,
    required int estimatedTicksAtExecution,
    required int actualTicks,
    required int cumulativeActualTicks,
    required int cumulativePlannedTicks,
    required GlobalState stateAfter,
    required GlobalState stateBefore,
    required ReplanBoundary? boundary,
  }) {
    // Registries can't change between states, so use the same one.
    final registries = stateBefore.registries;
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

    final stepDesc = describeStep(
      step,
      registries,
      currentAction: currentAction,
    );

    // Compare: planned vs estimated-at-execution vs actual
    // - planned != estimatedAtExec: planning snapshot inconsistent
    // - estimatedAtExec != actual: rate model/termination wrong
    final planVsEstDelta = plannedTicks - estimatedTicksAtExecution;
    final estVsActDelta = estimatedTicksAtExecution - actualTicks;
    final delta = actualTicks - plannedTicks;
    final deltaStr = delta >= 0 ? '+$delta' : '$delta';
    final cumDelta = cumulativeActualTicks - cumulativePlannedTicks;
    final cumDeltaStr = cumDelta >= 0 ? '+$cumDelta' : '$cumDelta';

    // Only print if significant deviation (>10% or >100 ticks)
    final significantDeviation =
        delta.abs() > 100 ||
        (plannedTicks > 0 && delta.abs() / plannedTicks > 0.1);

    if (significantDeviation || stepIndex < 5) {
      print('  Step ${stepIndex + 1}: $stepDesc');
      print(
        '    planned=$plannedTicks, '
        'estAtExec=$estimatedTicksAtExecution, '
        'actual=$actualTicks',
      );
      print(
        '    plan-vs-est: ${_formatDelta(planVsEstDelta)}, '
        'est-vs-actual: ${_formatDelta(estVsActDelta)}, '
        'total delta: $deltaStr, cumulative: $cumDeltaStr',
      );

      // Diagnose the source of discrepancy
      if (delta.abs() > 100) {
        if (planVsEstDelta.abs() > 50 &&
            planVsEstDelta.abs() > estVsActDelta.abs()) {
          print(
            '    >> SNAPSHOT INCONSISTENCY: state at execution '
            'differs from planning snapshot',
          );
        } else if (estVsActDelta.abs() > 50) {
          print(
            '    >> RATE/TERMINATION ISSUE: estimateTicks() '
            'vs actual execution mismatch',
          );
        }
      }

      String toCheck(WaitFor waitFor, GlobalState state) {
        return waitFor.isSatisfied(state) ? '✓' : '✗';
      }

      // Enhanced diagnostics for steps with large deviations
      if (delta.abs() > 1000) {
        // Print wait condition details
        if (step case WaitStep(:final waitFor)) {
          print('    Wait condition: ${waitFor.describe()}');
          if (waitFor case WaitForAnyOf(:final conditions)) {
            print('    Sub-conditions:');
            for (final cond in conditions) {
              print(
                '      before:${toCheck(cond, stateBefore)} '
                'after:${toCheck(cond, stateAfter)} '
                '${cond.describe()}',
              );
            }
          }
        }
        if (step case MacroStep(:final macro, :final waitFor)) {
          print('    Macro: $macro');
          print('    Wait condition: ${waitFor.describe()}');
          if (waitFor case WaitForAnyOf(:final conditions)) {
            print('    Sub-conditions:');
            for (final cond in conditions) {
              print(
                '      before:${toCheck(cond, stateBefore)} '
                'after:${toCheck(cond, stateAfter)} '
                '${cond.describe()}',
              );
            }
          }
          // For EnsureStock, show inventory count
          if (macro is EnsureStock) {
            final item = registries.items.byId(macro.itemId);
            final countBefore = stateBefore.inventory.countOfItem(item);
            final countAfter = stateAfter.inventory.countOfItem(item);
            print(
              '    Inventory: ${macro.itemId.localId} '
              '$countBefore -> $countAfter (target: ${macro.minTotal})',
            );
          }
        }
        // Show boundary if hit
        print('    Boundary: $boundary');
      }
    }
  }
}

/// Prints aggregate diagnostics for segment-based solving.
void _printSegmentedDiagnostics(
  List<SolverProfile> profiles, {
  bool extended = false,
  bool dumpStopTriggers = false,
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
    _printMacroStopTriggers(allTriggers, dump: dumpStopTriggers);
  }
}

// ---------------------------------------------------------------------------
// Segment Summary Formatting
// ---------------------------------------------------------------------------

/// Formats a one-line summary for a segment.
///
/// Format: `Seg N: ticks, nodes -> boundary reason`
///         `  Do: primary action + stock: Item1 X, Item2 Y | switches: N`
String _formatSegmentSummary(
  int segmentNum,
  Segment segment,
  SolverProfile? profile,
  Registries registries,
) {
  final ticks = segment.totalTicks;
  final nodes = profile?.expandedNodes ?? 0;
  final boundary = segment.stopBoundary.describe();

  // Extract primary action and stocking info from steps
  String? primaryAction;
  final stockEntries = <String>[];
  var switchCount = 0;
  var sellCount = 0;

  for (final step in segment.steps) {
    switch (step) {
      case InteractionStep(:final interaction):
        switch (interaction) {
          case SwitchActivity(:final actionId):
            switchCount++;
            // Use the first switch as primary action
            if (primaryAction == null) {
              final action = registries.actions.byId(actionId);
              final skill = action.skill.name.toLowerCase();
              primaryAction = '${action.name} ($skill)';
            }
          case SellItems():
            sellCount++;
          case BuyShopItem():
            break;
        }
      case MacroStep(:final macro):
        switch (macro) {
          case TrainSkillUntil(:final skill, :final actionId):
            if (primaryAction == null) {
              if (actionId != null) {
                final action = registries.actions.byId(actionId);
                final skillLower = skill.name.toLowerCase();
                primaryAction = '${action.name} ($skillLower)';
              } else {
                primaryAction = skill.name;
              }
            }
          case TrainConsumingSkillUntil(:final consumingSkill):
            primaryAction ??= consumingSkill.name;
          case EnsureStock(:final itemId, :final minTotal):
            stockEntries.add('${itemId.name} $minTotal');
          case AcquireItem(:final itemId, :final quantity):
            stockEntries.add('${itemId.name} $quantity');
          case ProduceItem(:final itemId, :final minTotal):
            stockEntries.add('Produce ${itemId.name} $minTotal');
        }
      case WaitStep():
        break;
    }
  }

  // Build the summary line
  final buffer = StringBuffer()
    ..write('Seg $segmentNum: ')
    ..write('${_formatTicksCompact(ticks)}, ')
    ..write('$nodes nodes -> $boundary');

  // Build the detail line if we have useful info
  final details = <String>[];
  if (primaryAction != null) {
    details.add('Do: $primaryAction');
  }
  if (stockEntries.isNotEmpty) {
    // Show top 2 stock entries
    final stockSummary = stockEntries.take(2).join(', ');
    if (stockEntries.length > 2) {
      details.add('stock: $stockSummary, +${stockEntries.length - 2} more');
    } else {
      details.add('stock: $stockSummary');
    }
  }

  // Add interaction counts
  final interactions = <String>[];
  if (switchCount > 0) interactions.add('switches: $switchCount');
  if (sellCount > 0) interactions.add('sells: $sellCount');
  if (interactions.isNotEmpty) {
    details.add(interactions.join(', '));
  }

  if (details.isNotEmpty) {
    buffer
      ..writeln()
      ..write('  ${details.join(' | ')}');
  }

  return buffer.toString();
}

/// Formats ticks in a compact form with proper number formatting.
String _formatTicksCompact(int ticks) {
  if (ticks >= 1000000) {
    return '${(ticks / 1000000).toStringAsFixed(1)}M ticks';
  } else if (ticks >= 1000) {
    return '${(ticks / 1000).toStringAsFixed(1)}k ticks';
  }
  return '${preciseNumberString(ticks)} ticks';
}

/// Determines if a segment is "weird" and should be auto-expanded.
///
/// A segment is weird if:
/// - It has many switches (>5) suggesting something unusual
/// - It has very few ticks (<100) suggesting a degenerate case
bool _isWeirdSegment(Segment segment) {
  // Count switches
  var switchCount = 0;
  for (final step in segment.steps) {
    if (step case InteractionStep(:final interaction)) {
      if (interaction is SwitchActivity) switchCount++;
    }
  }

  // Weird if too many switches or too few ticks
  return switchCount > 5 || segment.totalTicks < 100;
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
      'Consumer-producer pairs considered',
      (s) => s?.pairsConsidered,
    );
    compareStats('Consumer-producer pairs kept', (s) => s?.pairsKept);
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
    '(${_formatDoubleDelta(delta)})',
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

String _formatDoubleDelta(double delta) =>
    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}';

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
