/// Plan execution for the solver.
///
/// Provides [executePlan] and related step execution logic.
library;

import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver_profile.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/execution/prerequisites.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Callback for step progress during plan execution.
///
/// Called after each step with:
/// - stepIndex: 0-based index of the step
/// - step: the PlanStep that was executed
/// - plannedTicks: ticks the step was planned to take (from solver)
/// - estimatedTicksAtExecution: ticks estimated right before execution
/// - actualTicks: ticks the step actually took
/// - cumulativeActualTicks: total actual ticks so far
/// - cumulativePlannedTicks: total planned ticks so far
/// - stateAfter: the state after executing this step (for debugging)
/// - stateBefore: the state before executing this step (for debugging)
/// - boundary: the replan boundary hit, if any
typedef StepProgressCallback =
    void Function({
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
    });

/// Estimates ticks for a step at execution time using current state.
///
/// This recomputes the expected ticks from the current state, which may differ
/// from what was planned if the state has diverged. Comparing planned vs
/// estimated-at-execution vs actual helps diagnose rate model issues:
/// - planned != estimatedAtExec: planning snapshot inconsistent
/// - estimatedAtExec != actual: rate model or termination condition wrong
int _estimateTicksAtExecution(GlobalState state, PlanStep step) {
  switch (step) {
    case InteractionStep():
      return 0; // Interactions are instant

    case WaitStep(:final waitFor, :final expectedAction):
      // Get rates for the action that will be running
      final actionId = expectedAction ?? state.activeAction?.id;
      if (actionId == null) return 0;
      final rates = estimateRatesForAction(state, actionId);
      return waitFor.estimateTicks(state, rates);

    case MacroStep(:final macro, :final waitFor):
      // Get rates for the macro's action
      final actionId = switch (macro) {
        TrainSkillUntil(:final actionId, :final skill) =>
          actionId ??
              findBestActionForSkill(
                state,
                skill,
                ReachSkillLevelGoal(skill, 99),
              ),
        TrainConsumingSkillUntil(:final consumingSkill) =>
          findBestActionForSkill(
            state,
            consumingSkill,
            ReachSkillLevelGoal(consumingSkill, 99),
          ),
        AcquireItem(:final itemId) => findProducerActionForItem(
          state,
          itemId,
          const ReachSkillLevelGoal(Skill.mining, 99),
        ),
        EnsureStock(:final itemId) => findProducerActionForItem(
          state,
          itemId,
          const ReachSkillLevelGoal(Skill.mining, 99),
        ),
        ProduceItem(:final actionId) => actionId,
      };
      if (actionId == null) return 0;
      final rates = estimateRatesForAction(state, actionId);
      return waitFor.estimateTicks(state, rates);
  }
}

/// Context for plan execution that carries default policies.
///
/// This allows executing raw plans (without segment markers) by providing
/// defaults. Segment markers are still supported for per-segment overrides
/// or for debugging/logging purposes.
///
/// Resolution hierarchy for sell policy:
/// 1. Step-level: If the step is a SellItems interaction, use its policy
/// 2. Segment-level: Use the policy from the segment marker (if present)
/// 3. Context default: Use the context's default sell policy
class ExecutionContext {
  /// Creates an execution context with the given defaults.
  const ExecutionContext({this.defaultSellPolicy = const SellAllPolicy()});

  /// Default context with SellAllPolicy.
  static const defaultContext = ExecutionContext();

  /// The default sell policy to use when no step or segment policy is set.
  final SellPolicy defaultSellPolicy;
}

/// Result of resolving a sell policy for execution.
///
/// Contains the resolved policy and metadata about where it came from,
/// useful for debugging and logging.
class ResolvedSellPolicy {
  const ResolvedSellPolicy({required this.policy, required this.source});

  /// The resolved sell policy.
  final SellPolicy policy;

  /// Where this policy came from (for debugging/logging).
  final SellPolicySource source;
}

/// Describes where a resolved sell policy came from.
enum SellPolicySource {
  /// Policy came from the step itself (e.g., SellItems interaction).
  step,

  /// Policy came from the segment marker.
  segment,

  /// Policy came from the execution context's default.
  context,
}

/// Resolves the sell policy for a step during execution.
///
/// Resolution hierarchy (first match wins):
/// 1. Step-level: If the step is a SellItems interaction, use its policy
/// 2. Segment-level: Use the policy from the segment marker
/// 3. Context default: Use the execution context's default sell policy
ResolvedSellPolicy resolveSellPolicy({
  required PlanStep step,
  required Plan plan,
  required int stepIndex,
  required ExecutionContext executionContext,
}) {
  // 1. Step-level: SellItems interactions carry their own policy
  if (step case InteractionStep(interaction: SellItems(:final policy))) {
    return ResolvedSellPolicy(policy: policy, source: SellPolicySource.step);
  }

  // 2. Segment-level: Look up from segment markers
  final segmentPolicy = _findSegmentSellPolicy(plan, stepIndex);
  if (segmentPolicy != null) {
    return ResolvedSellPolicy(
      policy: segmentPolicy,
      source: SellPolicySource.segment,
    );
  }

  // 3. Context default: Use the execution context's default
  return ResolvedSellPolicy(
    policy: executionContext.defaultSellPolicy,
    source: SellPolicySource.context,
  );
}

/// Finds the sell policy for the segment containing step at [stepIndex].
///
/// Walks through segment markers to find which segment the step belongs to,
/// then returns that segment's sell policy.
///
/// Returns null if:
/// - No segment markers exist (legacy plan without segments)
/// - The segment doesn't have a sell policy (legacy segment)
SellPolicy? _findSegmentSellPolicy(Plan plan, int stepIndex) {
  if (plan.segmentMarkers.isEmpty) return null;

  // Find the segment marker for this step index.
  // Segment markers are sorted by stepIndex - find the last marker
  // whose stepIndex is <= our current stepIndex.
  SegmentMarker? currentMarker;
  for (final marker in plan.segmentMarkers) {
    if (marker.stepIndex <= stepIndex) {
      currentMarker = marker;
    } else {
      break; // Markers are sorted, so we're past our segment
    }
  }

  return currentMarker?.sellPolicy;
}

/// Execute a plan and return the result including death count and actual ticks.
///
/// Uses goal-aware waiting: [WaitStep.waitFor] determines when to stop waiting,
/// which handles variance between expected-value planning and full simulation.
/// Deaths are automatically handled by restarting the activity and are counted.
///
/// The [context] provides default policies for execution. If not provided,
/// uses [ExecutionContext.defaultContext] which has a SellAllPolicy default.
/// Segment markers in the plan can override the context's defaults.
PlanExecutionResult executePlan(
  GlobalState originalState,
  Plan plan, {
  required Random random,
  ExecutionContext context = ExecutionContext.defaultContext,
  StepProgressCallback? onStepComplete,
}) {
  var state = originalState;
  var totalDeaths = 0;
  var actualTicks = 0;
  var plannedTicks = 0;
  final boundariesHit = <ReplanBoundary>[];

  // Compute boundaries once for macro execution
  final boundaries = computeUnlockBoundaries(state.registries);

  for (var i = 0; i < plan.steps.length; i++) {
    final step = plan.steps[i];
    final stepPlannedTicks = switch (step) {
      InteractionStep() => 0,
      WaitStep(:final deltaTicks) => deltaTicks,
      MacroStep(:final deltaTicks) => deltaTicks,
    };

    // Resolve the sell policy for this step using the hierarchy:
    // step → segment → context default
    final resolved = resolveSellPolicy(
      step: step,
      plan: plan,
      stepIndex: i,
      executionContext: context,
    );

    // Capture state before execution for diagnostics
    final stateBefore = state;

    // Compute estimated ticks at execution time (recompute from current state)
    final estimatedTicksAtExecution = _estimateTicksAtExecution(state, step);

    try {
      final result = step.apply(
        state,
        random: random,
        boundaries: boundaries,
        segmentSellPolicy: resolved.policy,
      );
      state = result.state;
      totalDeaths += result.deaths;
      actualTicks += result.ticksElapsed;
      plannedTicks += stepPlannedTicks;

      // Report progress if callback provided
      if (onStepComplete != null) {
        onStepComplete(
          stepIndex: i,
          step: step,
          plannedTicks: stepPlannedTicks,
          estimatedTicksAtExecution: estimatedTicksAtExecution,
          actualTicks: result.ticksElapsed,
          cumulativeActualTicks: actualTicks,
          cumulativePlannedTicks: plannedTicks,
          stateAfter: state,
          stateBefore: stateBefore,
          boundary: result.boundary,
        );
      }

      // Collect boundary if one was hit
      if (result.boundary != null) {
        boundariesHit.add(result.boundary!);
      }
    } catch (e) {
      // Rethrow with context for debugging, print is needed for visibility
      // ignore: avoid_print
      print('Error applying step $i: $e');
      rethrow;
    }
  }
  return PlanExecutionResult(
    finalState: state,
    totalDeaths: totalDeaths,
    actualTicks: actualTicks,
    plannedTicks: plan.totalTicks,
    boundariesHit: boundariesHit,
  );
}

// ---------------------------------------------------------------------------
// Controlled Replanning Infrastructure
// ---------------------------------------------------------------------------

/// Configuration for controlled replanning during execution.
///
/// When execution hits a boundary that requires replanning (e.g., inputs
/// depleted, inventory full with nothing sellable), the executor can
/// trigger a replan using the same solver infrastructure.
///
/// This provides robustness to randomness while keeping strategy decisions
/// in the planner, not the executor.
@immutable
class ReplanConfig {
  const ReplanConfig({
    this.maxReplans = 10,
    this.maxTotalTicks = 1000000,
    this.logReplans = false,
  });

  /// Maximum number of replans allowed per run.
  ///
  /// Prevents infinite replan loops. If exceeded, execution stops with
  /// a [ReplanLimitExceeded] boundary.
  final int maxReplans;

  /// Maximum total ticks across all segments.
  ///
  /// Provides a time budget for the entire run. If exceeded, execution
  /// stops with a [TimeBudgetExceeded] boundary.
  final int maxTotalTicks;

  /// Whether to log replan events for debugging.
  final bool logReplans;
}

/// Tracks state across replanning cycles.
///
/// Maintains:
/// - Running totals (ticks, deaths, replans)
/// - History of replan events for debugging
/// - Budget enforcement
@immutable
class ReplanContext {
  const ReplanContext({
    required this.config,
    this.replanCount = 0,
    this.totalTicks = 0,
    this.totalDeaths = 0,
    this.replanHistory = const [],
  });

  final ReplanConfig config;
  final int replanCount;
  final int totalTicks;
  final int totalDeaths;
  final List<ReplanEvent> replanHistory;

  /// Whether we've hit the replan limit.
  bool get replanLimitExceeded => replanCount >= config.maxReplans;

  /// Whether we've hit the time budget.
  bool get timeBudgetExceeded => totalTicks >= config.maxTotalTicks;

  /// Whether we can continue with another replan.
  bool get canReplan => !replanLimitExceeded && !timeBudgetExceeded;

  /// Creates a new context after a replan event.
  ReplanContext afterReplan({
    required ReplanEvent event,
    required int ticksElapsed,
    required int deaths,
  }) {
    return ReplanContext(
      config: config,
      replanCount: replanCount + 1,
      totalTicks: totalTicks + ticksElapsed,
      totalDeaths: totalDeaths + deaths,
      replanHistory: [...replanHistory, event],
    );
  }

  /// Creates a new context after segment completion (no replan).
  ReplanContext afterSegment({required int ticksElapsed, required int deaths}) {
    return ReplanContext(
      config: config,
      replanCount: replanCount,
      totalTicks: totalTicks + ticksElapsed,
      totalDeaths: totalDeaths + deaths,
      replanHistory: replanHistory,
    );
  }

  /// Creates a [ReplanExecutionResult] from this context.
  ReplanExecutionResult toResult({
    required GlobalState finalState,
    required List<ReplanSegmentResult> segments,
    ReplanBoundary? terminatingBoundary,
  }) {
    return ReplanExecutionResult(
      finalState: finalState,
      totalTicks: totalTicks,
      totalDeaths: totalDeaths,
      replanCount: replanCount,
      segments: segments,
      terminatingBoundary: terminatingBoundary,
    );
  }

  /// Checks if execution should terminate early.
  ///
  /// Returns a result if termination is needed (replan limit exceeded,
  /// time budget exceeded, or goal already satisfied), null otherwise.
  ReplanExecutionResult? checkTermination({
    required GlobalState currentState,
    required Goal goal,
    required List<ReplanSegmentResult> segments,
  }) {
    if (replanLimitExceeded) {
      return toResult(
        finalState: currentState,
        segments: segments,
        terminatingBoundary: ReplanLimitExceeded(config.maxReplans),
      );
    }

    if (timeBudgetExceeded) {
      return toResult(
        finalState: currentState,
        segments: segments,
        terminatingBoundary: TimeBudgetExceeded(
          config.maxTotalTicks,
          totalTicks,
        ),
      );
    }

    if (goal.isSatisfied(currentState)) {
      return toResult(finalState: currentState, segments: segments);
    }

    return null;
  }
}

/// Records a replan event for debugging.
@immutable
class ReplanEvent {
  const ReplanEvent({
    required this.boundary,
    required this.stateHash,
    required this.ticksAtReplan,
    required this.reason,
  });

  /// The boundary that triggered the replan.
  final ReplanBoundary boundary;

  /// Hash of the state at replan time (for repro).
  final int stateHash;

  /// Total ticks elapsed when replan was triggered.
  final int ticksAtReplan;

  /// Human-readable reason for the replan.
  final String reason;

  @override
  String toString() =>
      'ReplanEvent(${boundary.runtimeType}, ticks=$ticksAtReplan, $reason)';
}

/// Result of execution with replanning.
@immutable
class ReplanExecutionResult {
  const ReplanExecutionResult({
    required this.finalState,
    required this.totalTicks,
    required this.totalDeaths,
    required this.replanCount,
    required this.segments,
    this.terminatingBoundary,
  });

  /// Final state after all segments.
  final GlobalState finalState;

  /// Total ticks across all segments.
  final int totalTicks;

  /// Total deaths across all segments.
  final int totalDeaths;

  /// Number of replans that occurred.
  final int replanCount;

  /// Results from each segment (for diagnostics).
  final List<ReplanSegmentResult> segments;

  /// The boundary that terminated execution (null if goal reached).
  final ReplanBoundary? terminatingBoundary;

  /// Whether the goal was reached.
  bool get goalReached => terminatingBoundary == null;
}

/// Result of a single segment execution during replanning.
@immutable
class ReplanSegmentResult {
  const ReplanSegmentResult({
    required this.steps,
    required this.plannedTicks,
    required this.actualTicks,
    required this.deaths,
    required this.triggeredReplan,
    this.replanBoundary,
    this.sellPolicy,
    this.profile,
  });

  /// The steps in this segment (for inspection/replay).
  final List<PlanStep> steps;

  /// Ticks the solver planned for this segment.
  final int plannedTicks;

  /// Ticks the segment actually took during execution.
  final int actualTicks;

  /// Deaths that occurred during this segment.
  final int deaths;

  /// Whether this segment triggered a replan.
  final bool triggeredReplan;

  /// The boundary that triggered the replan (if any).
  final ReplanBoundary? replanBoundary;

  /// The sell policy used for this segment.
  ///
  /// This is the policy computed at segment start and used for:
  /// - Deciding which items to sell during execution
  /// - Computing effectiveCredits for boundary detection
  /// - Handling upgrade purchases that require selling first
  final SellPolicy? sellPolicy;

  /// Solver profile for this segment (if diagnostics enabled).
  final SolverProfile? profile;
}

/// Computes a simple state hash for replan logging.
///
/// Not cryptographically secure - just for debugging/repro.
int computeStateHash(GlobalState state) {
  var hash = state.gp.hashCode;
  hash ^= state.inventoryUsed.hashCode;
  for (final skill in Skill.values) {
    hash ^= state.skillState(skill).xp.hashCode;
  }
  return hash ^ (state.activeAction?.id.hashCode ?? 0);
}
