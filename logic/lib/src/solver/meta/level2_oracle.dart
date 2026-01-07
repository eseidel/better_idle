/// Level 2 Oracle wrapper for the meta planner.
///
/// Wraps the existing Level 2 A* solver to provide a clean interface for
/// the Level 3 meta planner. Does NOT modify the existing solver - gates
/// by restricting the goal passed to the solver.
///
/// ## Design Notes
///
/// This wrapper:
/// - Calls existing `solve()` unchanged
/// - Converts milestones to Level 2 Goals
/// - Computes PhaseResult by comparing initial vs terminal state
/// - Tracks solver performance stats
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/core/solver_profile.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/meta/milestone.dart';
import 'package:logic/src/solver/meta/phase_result.dart';
import 'package:logic/src/state.dart';

/// Default configuration for oracle calls.
class OracleConfig {
  const OracleConfig({
    this.maxExpandedNodes = 200000,
    this.maxQueueSize = 500000,
    this.collectDiagnostics = false,
  });

  /// Maximum A* nodes to expand per oracle call.
  /// Default matches the Level 2 solver defaults.
  final int maxExpandedNodes;

  /// Maximum queue size for A* search.
  /// Default matches the Level 2 solver defaults.
  final int maxQueueSize;

  /// Whether to collect extended diagnostics.
  final bool collectDiagnostics;
}

/// Wraps Level 2 solver as an oracle for the meta planner.
///
/// The oracle evaluates phase candidates by:
/// 1. Converting milestone targets to Level 2 Goals
/// 2. Calling the existing solve() function unchanged
/// 3. Computing PhaseResult from the solver output
class Level2Oracle {
  Level2Oracle({this.config = const OracleConfig()});

  final OracleConfig config;

  /// Evaluate a phase by running Level 2 solver.
  ///
  /// Returns [PhaseResult] on success, or null if solver fails to find a plan.
  PhaseResult? evaluate(
    GlobalState state,
    List<Milestone> targets, {
    OracleConfig? overrideConfig,
  }) {
    if (targets.isEmpty) return null;

    final effectiveConfig = overrideConfig ?? config;
    final stopwatch = Stopwatch()..start();

    // Convert milestones to Level 2 goal
    final goal = _convertToGoal(targets);
    if (goal == null) return null;

    // Call existing solver unchanged
    final result = solve(
      state,
      goal,
      maxExpandedNodes: effectiveConfig.maxExpandedNodes,
      maxQueueSize: effectiveConfig.maxQueueSize,
      collectDiagnostics: effectiveConfig.collectDiagnostics,
    );

    stopwatch.stop();

    // Handle failure
    if (result is SolverFailed) {
      return null;
    }

    final success = result as SolverSuccess;

    // Compute phase result
    return _buildPhaseResult(
      initialState: state,
      terminalState: success.terminalState,
      plan: success.plan,
      targets: targets,
      wallTimeMs: stopwatch.elapsedMilliseconds,
      profile: success.profile,
    );
  }

  /// Evaluate with a pre-built Goal (for direct Level 2 goal usage).
  PhaseResult? evaluateWithGoal(
    GlobalState state,
    Goal goal, {
    List<Milestone>? associatedMilestones,
    OracleConfig? overrideConfig,
  }) {
    final effectiveConfig = overrideConfig ?? config;
    final stopwatch = Stopwatch()..start();

    final result = solve(
      state,
      goal,
      maxExpandedNodes: effectiveConfig.maxExpandedNodes,
      maxQueueSize: effectiveConfig.maxQueueSize,
      collectDiagnostics: effectiveConfig.collectDiagnostics,
    );

    stopwatch.stop();

    if (result is SolverFailed) {
      return null;
    }

    final success = result as SolverSuccess;

    return _buildPhaseResult(
      initialState: state,
      terminalState: success.terminalState,
      plan: success.plan,
      targets: associatedMilestones ?? [],
      wallTimeMs: stopwatch.elapsedMilliseconds,
      profile: success.profile,
    );
  }

  /// Convert milestones to a Level 2 Goal.
  Goal? _convertToGoal(List<Milestone> targets) {
    // Extract skill level milestones
    final skillGoals = <ReachSkillLevelGoal>[];

    for (final target in targets) {
      if (target is SkillLevelMilestone) {
        skillGoals.add(ReachSkillLevelGoal(target.skill, target.level));
      }
      // Future: handle other milestone types (GP, items, etc.)
    }

    if (skillGoals.isEmpty) return null;

    if (skillGoals.length == 1) {
      return skillGoals.first;
    }

    return MultiSkillGoal(skillGoals);
  }

  /// Build PhaseResult from solver output.
  PhaseResult _buildPhaseResult({
    required GlobalState initialState,
    required GlobalState terminalState,
    required Plan plan,
    required List<Milestone> targets,
    required int wallTimeMs,
    SolverProfile? profile,
  }) {
    // Compute skill deltas
    final skillDeltas = PhaseResult.computeSkillDeltas(
      initialState,
      terminalState,
    );

    // Determine which milestones were satisfied
    final milestonesSatisfied = targets
        .where((m) => m.isSatisfied(terminalState))
        .map((m) => m.id)
        .toList();

    // Extract events from plan execution
    final events = _extractEvents(initialState, terminalState, plan);

    // Determine end boundary (from plan's segment markers if available)
    final endBoundary = _extractEndBoundary(plan);

    // Build solver stats
    final solverStats = SolverStats(
      nodesExpanded: plan.expandedNodes,
      wallTimeMs: wallTimeMs,
      nodesEnqueued: plan.enqueuedNodes,
      queuePeakSize: profile?.peakQueueSize,
    );

    return PhaseResult(
      plan: plan,
      initialState: initialState,
      terminalState: terminalState,
      ticksElapsed: plan.totalTicks,
      endBoundary: endBoundary,
      skillDeltas: skillDeltas,
      milestonesSatisfied: milestonesSatisfied,
      events: events,
      solverStats: solverStats,
    );
  }

  /// Extract events from state changes.
  List<PhaseEvent> _extractEvents(
    GlobalState initial,
    GlobalState terminal,
    Plan plan,
  ) {
    final events = <PhaseEvent>[];

    // Track deaths from plan
    if (plan.expectedDeaths > 0) {
      events.add(
        PhaseEvent(
          type: PhaseEventType.death,
          details: '${plan.expectedDeaths} deaths expected',
        ),
      );
    }

    // Track level ups
    for (final skill in Skill.values) {
      final initialLevel = initial.skillState(skill).skillLevel;
      final terminalLevel = terminal.skillState(skill).skillLevel;
      if (terminalLevel > initialLevel) {
        events.add(
          PhaseEvent(
            type: PhaseEventType.actionUnlocked,
            details: '${skill.name} $initialLevel -> $terminalLevel',
          ),
        );
      }
    }

    // Track inventory pressure (compare slot usage)
    final initialUsed = initial.inventoryUsed;
    final terminalUsed = terminal.inventoryUsed;
    final terminalTotal = terminal.inventoryCapacity;
    if (terminalUsed > terminalTotal * 0.9 && terminalUsed > initialUsed) {
      events.add(
        const PhaseEvent(
          type: PhaseEventType.inventoryPressure,
          details: 'Inventory near capacity',
        ),
      );
    }

    return events;
  }

  /// Extract end boundary from plan.
  SegmentBoundary? _extractEndBoundary(Plan plan) {
    // Check segment markers for boundary info
    if (plan.segmentMarkers.isNotEmpty) {
      return plan.segmentMarkers.last.boundary;
    }
    return null;
  }
}
