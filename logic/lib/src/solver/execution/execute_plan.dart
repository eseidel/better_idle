/// Plan execution for the solver.
///
/// Provides [executePlan] and related step execution logic.
library;

import 'dart:math';

import 'package:logic/src/data/actions.dart' show Skill, SkillAction;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/analysis/watch_set.dart';
import 'package:logic/src/solver/candidates/build_chain.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/execution/consume_until.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/execution/prerequisites.dart';
import 'package:logic/src/solver/interactions/apply_interaction.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Result of applying a single step.
typedef StepResult = ({
  GlobalState state,
  int ticksElapsed,
  int deaths,
  ReplanBoundary? boundary,
});

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

/// Converts a SegmentBoundary to a ReplanBoundary for step return.
///
/// This is used when mid-macro stopping detects a material boundary.
/// Some information may be approximated since SegmentBoundary has less
/// detail than ReplanBoundary in some cases.
ReplanBoundary segmentBoundaryToReplan(SegmentBoundary boundary) {
  return switch (boundary) {
    GoalReachedBoundary() => const GoalReached(),
    UpgradeAffordableBoundary(:final purchaseId) => UpgradeAffordableEarly(
      purchaseId: purchaseId,
      cost: 0,
    ),
    UnlockBoundary() =>
      // UnexpectedUnlock needs an actionId, but UnlockBoundary doesn't have it.
      // Return GoalReached as a signal that we hit a material boundary.
      const GoalReached(),
    InputsDepletedBoundary(:final actionId) => InputsDepleted(
      actionId: actionId,
      // We don't track which item was depleted in SegmentBoundary
      missingItemId: const MelvorId('melvorD:Unknown'),
    ),
    HorizonCapBoundary() =>
      // Horizon cap is a planned stop, not an error. Signal as GoalReached.
      const GoalReached(),
    InventoryPressureBoundary() =>
      // Inventory pressure triggers a replan to sell items.
      const InventoryFull(),
  };
}

/// Executes a coupled produce/consume loop for consuming skills.
///
/// ## Deterministic Checkpointed Execution
///
/// The macro MUST be fully specified by the solver. Missing fields trigger
/// immediate failure (NoProgressPossible) rather than legacy fallbacks.
///
/// ### Required fields:
/// - `consumeActionId`: fixed consuming action ID
/// - `producerByInputItem`: map from input item ID to producer action ID
/// - `bufferTarget`: quantized batch size for production
///
/// ### Execution Model: "Repeat Cycles Until Stop"
///
/// ```dart
/// while (!primaryStop.isSatisfied) {
///   // PRODUCE PHASE
///   for (inputItem in consumeAction.inputs) {
///     producerId = macro.producerByInputItem[inputItem]  // Fixed ID
///     SwitchActivity(producerId)
///     consumeUntil(WaitForInventoryAtLeast(input, bufferTarget) OR boundary)
///     if (boundary) attemptRecovery or return
///   }
///
///   // CONSUME PHASE
///   SwitchActivity(macro.consumeActionId)  // Fixed ID
///   consumeUntil(WaitForAnyOf([
///     primaryStopWait,
///     InputsDepleted(consumeActionId),
///     InventoryPressure,  // Stop early if nearly full
///   ]))
///   if (boundary) attemptRecovery or return
/// }
/// ```
///
/// ### Key Invariants
///
/// - **No action searching**: All action IDs come from the macro
/// - **No recursion**: Producers must be immediately feasible
/// - **No hidden switches**: Activity only changes via explicit SwitchActivity
/// - **Deterministic**: Same inputs produce same execution trace
/// - **Checkpointed**: Each phase boundary is a valid checkpoint
StepResult executeCoupledLoop(
  GlobalState state,
  TrainConsumingSkillUntil macro,
  WaitFor waitFor,
  Map<Skill, SkillBoundaries>? boundaries,
  Random random, {
  WatchSet? watchSet,
  SellPolicy? segmentSellPolicy,
}) {
  var currentState = state;
  var totalTicks = 0;
  var totalDeaths = 0;
  var recoveryAttempts = 0;

  // ---------------------------------------------------------------------------
  // VALIDATION: Require all plan-specified fields (no fallbacks)
  // ---------------------------------------------------------------------------

  final consumeActionId = macro.consumeActionId ?? macro.actionId;
  if (consumeActionId == null) {
    return (
      state: state,
      ticksElapsed: 0,
      deaths: 0,
      boundary: const NoProgressPossible(
        reason: 'Macro missing consumeActionId - solver must specify',
      ),
    );
  }

  final consumeAction = currentState.registries.actions.byId(consumeActionId);
  if (consumeAction is! SkillAction || consumeAction.inputs.isEmpty) {
    return (
      state: currentState,
      ticksElapsed: 0,
      deaths: 0,
      boundary: const NoProgressPossible(
        reason: 'Consume action has no inputs',
      ),
    );
  }

  final bufferTarget = macro.bufferTarget;
  if (bufferTarget == null) {
    return (
      state: state,
      ticksElapsed: 0,
      deaths: 0,
      boundary: const NoProgressPossible(
        reason: 'Macro missing bufferTarget - solver must specify',
      ),
    );
  }

  final producerByInputItem = macro.producerByInputItem;
  if (producerByInputItem == null) {
    return (
      state: state,
      ticksElapsed: 0,
      deaths: 0,
      boundary: const NoProgressPossible(
        reason: 'Macro missing producerByInputItem - solver must specify',
      ),
    );
  }

  // Compute primary stop condition
  final primaryStop = boundaries != null
      ? macro.primaryStop.toWaitFor(currentState, boundaries)
      : waitFor;

  // Inventory pressure threshold (stop consume phase early if nearly full)
  const inventoryPressureThreshold = 0.9;

  // ---------------------------------------------------------------------------
  // MAIN LOOP: Repeat produce-consume cycles until primary stop
  // ---------------------------------------------------------------------------

  while (true) {
    // -------------------------------------------------------------------------
    // CHECKPOINT: Start of cycle - check if done
    // -------------------------------------------------------------------------

    if (primaryStop.isSatisfied(currentState)) {
      return (
        state: currentState,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: const WaitConditionSatisfied(),
      );
    }

    // Check for material boundary (upgrade affordable, unlock, etc.)
    if (watchSet != null) {
      final boundary = watchSet.detectBoundary(
        currentState,
        elapsedTicks: totalTicks,
      );
      if (boundary != null) {
        return (
          state: currentState,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: segmentBoundaryToReplan(boundary),
        );
      }
    }

    // -------------------------------------------------------------------------
    // PRODUCE PHASE: Acquire inputs for consume action
    // -------------------------------------------------------------------------

    for (final inputEntry in consumeAction.inputs.entries) {
      final inputItemId = inputEntry.key;

      // Check current stock
      final currentCount = currentState.inventory.countOfItem(
        currentState.registries.items.byId(inputItemId),
      );

      if (currentCount >= bufferTarget) {
        continue; // Have enough, skip to next input
      }

      // Check if this input has a multi-tier chain
      final inputChain = macro.inputChains?[inputItemId];
      if (inputChain != null && inputChain.children.isNotEmpty) {
        // Multi-tier chain: produce inputs bottom-up
        final chainResult = _produceChainBottomUp(
          currentState,
          inputChain,
          bufferTarget,
          random,
          watchSet,
          segmentSellPolicy,
          totalTicks,
          totalDeaths,
          recoveryAttempts,
          macro.maxRecoveryAttempts,
        );
        currentState = chainResult.state;
        totalTicks = chainResult.totalTicks;
        totalDeaths = chainResult.totalDeaths;
        recoveryAttempts = chainResult.recoveryAttempts;

        if (chainResult.boundary != null) {
          return (
            state: currentState,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: chainResult.boundary!,
          );
        }
      } else {
        // Simple single-tier production
        // Get producer from plan (no runtime search)
        final producerId = producerByInputItem[inputItemId];
        if (producerId == null) {
          return (
            state: currentState,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: NoProgressPossible(
              reason: 'No producer for ${inputItemId.localId} - needs replan',
            ),
          );
        }

        // CHECKPOINT: Switch to producer (fixed ID from plan)
        try {
          currentState = applyInteraction(
            currentState,
            SwitchActivity(producerId),
          );
        } on Exception catch (e) {
          // Producer not feasible (missing its own inputs) - replan
          return (
            state: currentState,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: NoProgressPossible(
              reason: 'Cannot start producer $producerId: $e',
            ),
          );
        }

        // Produce until buffer target reached
        final produceResult = consumeUntil(
          currentState,
          WaitForInventoryAtLeast(inputItemId, bufferTarget),
          random: random,
        );
        currentState = produceResult.state;
        totalTicks += produceResult.ticksElapsed;
        totalDeaths += produceResult.deathCount;

        // CHECKPOINT: Handle production boundaries
        if (produceResult.boundary is InventoryFull) {
          final recovery = attemptRecovery(
            currentState,
            const InventoryFull(),
            segmentSellPolicy,
            recoveryAttempts,
            macro.maxRecoveryAttempts,
          );
          if (recovery.shouldStop) {
            return (
              state: recovery.state,
              ticksElapsed: totalTicks,
              deaths: totalDeaths,
              boundary: recovery.boundary,
            );
          }
          currentState = recovery.state;
          recoveryAttempts = recovery.newAttemptCount;
          // Retry this input's production by breaking to outer loop
          break;
        }

        // Check for material boundary after producing
        if (watchSet != null) {
          final boundary = watchSet.detectBoundary(
            currentState,
            elapsedTicks: totalTicks,
          );
          if (boundary != null) {
            return (
              state: currentState,
              ticksElapsed: totalTicks,
              deaths: totalDeaths,
              boundary: segmentBoundaryToReplan(boundary),
            );
          }
        }
      }
    }

    // CHECKPOINT: After produce phase - check stop again
    if (primaryStop.isSatisfied(currentState)) {
      return (
        state: currentState,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: const WaitConditionSatisfied(),
      );
    }

    // -------------------------------------------------------------------------
    // CONSUME PHASE: Use inputs to train skill
    // -------------------------------------------------------------------------

    // CHECKPOINT: Switch to consumer (fixed ID from plan)
    try {
      currentState = applyInteraction(
        currentState,
        SwitchActivity(consumeActionId),
      );
    } on Exception catch (e) {
      return (
        state: currentState,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: NoProgressPossible(
          reason: 'Cannot start consumer $consumeActionId: $e',
        ),
      );
    }

    // Consume until: primary stop OR inputs depleted OR inventory pressure
    final consumeResult = consumeUntil(
      currentState,
      WaitForAnyOf([
        primaryStop,
        WaitForInputsDepleted(consumeActionId),
        const WaitForInventoryThreshold(inventoryPressureThreshold),
      ]),
      random: random,
    );
    currentState = consumeResult.state;
    totalTicks += consumeResult.ticksElapsed;
    totalDeaths += consumeResult.deathCount;

    // CHECKPOINT: Handle consumption boundaries
    if (consumeResult.boundary is InventoryFull) {
      final recovery = attemptRecovery(
        currentState,
        const InventoryFull(),
        segmentSellPolicy,
        recoveryAttempts,
        macro.maxRecoveryAttempts,
      );
      if (recovery.shouldStop) {
        return (
          state: recovery.state,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: recovery.boundary,
        );
      }
      currentState = recovery.state;
      recoveryAttempts = recovery.newAttemptCount;
      // Continue to next cycle (will produce more inputs)
      continue;
    }

    // Check for material boundary after consuming
    if (watchSet != null) {
      final boundary = watchSet.detectBoundary(
        currentState,
        elapsedTicks: totalTicks,
      );
      if (boundary != null) {
        return (
          state: currentState,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: segmentBoundaryToReplan(boundary),
        );
      }
    }

    // Loop continues: next iteration will produce more inputs if needed
  }
}

// ---------------------------------------------------------------------------
// Multi-tier chain production helper
// ---------------------------------------------------------------------------

/// Result of producing a multi-tier chain.
typedef _ChainProductionResult = ({
  GlobalState state,
  int totalTicks,
  int totalDeaths,
  int recoveryAttempts,
  ReplanBoundary? boundary,
});

/// Produces items for a multi-tier chain by walking bottom-up.
///
/// For a chain like: Bronze Bar (needs Copper Ore + Tin Ore)
/// This will:
/// 1. Mine Copper Ore until we have enough
/// 2. Mine Tin Ore until we have enough
/// 3. Smelt Bronze Bars until we have bufferTarget
///
/// The chain structure captures the full production tree, and this function
/// executes each level in dependency order (leaves first, root last).
_ChainProductionResult _produceChainBottomUp(
  GlobalState state,
  PlannedChain chain,
  int bufferTarget,
  Random random,
  WatchSet? watchSet,
  SellPolicy? segmentSellPolicy,
  int initialTicks,
  int initialDeaths,
  int initialRecoveryAttempts,
  int maxRecoveryAttempts,
) {
  var currentState = state;
  var totalTicks = initialTicks;
  var totalDeaths = initialDeaths;
  var recoveryAttempts = initialRecoveryAttempts;

  // First, recursively produce all children (leaf inputs first)
  for (final child in chain.children) {
    // Check if we already have enough of this child item
    final childItem = currentState.registries.items.byId(child.itemId);
    final childCount = currentState.inventory.countOfItem(childItem);

    // Calculate how many we need for producing bufferTarget of the parent
    final parentAction =
        currentState.registries.actions.byId(chain.actionId) as SkillAction;
    final inputsPerAction = parentAction.inputs[child.itemId] ?? 1;
    final outputsPerAction = parentAction.outputs[chain.itemId] ?? 1;
    final actionsNeeded = (bufferTarget / outputsPerAction).ceil();
    final childNeeded = actionsNeeded * inputsPerAction;

    if (childCount >= childNeeded) {
      continue; // Have enough of this input
    }

    if (child.children.isNotEmpty) {
      // Recursively produce this child's inputs
      final childResult = _produceChainBottomUp(
        currentState,
        child,
        childNeeded,
        random,
        watchSet,
        segmentSellPolicy,
        totalTicks,
        totalDeaths,
        recoveryAttempts,
        maxRecoveryAttempts,
      );
      currentState = childResult.state;
      totalTicks = childResult.totalTicks;
      totalDeaths = childResult.totalDeaths;
      recoveryAttempts = childResult.recoveryAttempts;

      if (childResult.boundary != null) {
        return childResult;
      }
    } else {
      // Leaf node: produce directly
      try {
        currentState = applyInteraction(
          currentState,
          SwitchActivity(child.actionId),
        );
      } on Exception catch (e) {
        return (
          state: currentState,
          totalTicks: totalTicks,
          totalDeaths: totalDeaths,
          recoveryAttempts: recoveryAttempts,
          boundary: NoProgressPossible(
            reason: 'Cannot start leaf producer ${child.actionId}: $e',
          ),
        );
      }

      final produceResult = consumeUntil(
        currentState,
        WaitForInventoryAtLeast(child.itemId, childNeeded),
        random: random,
      );
      currentState = produceResult.state;
      totalTicks += produceResult.ticksElapsed;
      totalDeaths += produceResult.deathCount;

      // Handle production boundaries
      if (produceResult.boundary is InventoryFull) {
        final recovery = attemptRecovery(
          currentState,
          const InventoryFull(),
          segmentSellPolicy,
          recoveryAttempts,
          maxRecoveryAttempts,
        );
        if (recovery.shouldStop) {
          return (
            state: recovery.state,
            totalTicks: totalTicks,
            totalDeaths: totalDeaths,
            recoveryAttempts: recovery.newAttemptCount,
            boundary: recovery.boundary,
          );
        }
        currentState = recovery.state;
        recoveryAttempts = recovery.newAttemptCount;
      }

      // Check for material boundary after producing
      if (watchSet != null) {
        final boundary = watchSet.detectBoundary(
          currentState,
          elapsedTicks: totalTicks,
        );
        if (boundary != null) {
          return (
            state: currentState,
            totalTicks: totalTicks,
            totalDeaths: totalDeaths,
            recoveryAttempts: recoveryAttempts,
            boundary: segmentBoundaryToReplan(boundary),
          );
        }
      }
    }
  }

  // All children produced - now produce the root item
  try {
    currentState = applyInteraction(
      currentState,
      SwitchActivity(chain.actionId),
    );
  } on Exception catch (e) {
    return (
      state: currentState,
      totalTicks: totalTicks,
      totalDeaths: totalDeaths,
      recoveryAttempts: recoveryAttempts,
      boundary: NoProgressPossible(
        reason: 'Cannot start chain root producer ${chain.actionId}: $e',
      ),
    );
  }

  final produceResult = consumeUntil(
    currentState,
    WaitForInventoryAtLeast(chain.itemId, bufferTarget),
    random: random,
  );
  currentState = produceResult.state;
  totalTicks += produceResult.ticksElapsed;
  totalDeaths += produceResult.deathCount;

  // Handle production boundaries for root
  if (produceResult.boundary is InventoryFull) {
    final recovery = attemptRecovery(
      currentState,
      const InventoryFull(),
      segmentSellPolicy,
      recoveryAttempts,
      maxRecoveryAttempts,
    );
    if (recovery.shouldStop) {
      return (
        state: recovery.state,
        totalTicks: totalTicks,
        totalDeaths: totalDeaths,
        recoveryAttempts: recovery.newAttemptCount,
        boundary: recovery.boundary,
      );
    }
    currentState = recovery.state;
    recoveryAttempts = recovery.newAttemptCount;
  }

  // Check for material boundary after producing root
  if (watchSet != null) {
    final boundary = watchSet.detectBoundary(
      currentState,
      elapsedTicks: totalTicks,
    );
    if (boundary != null) {
      return (
        state: currentState,
        totalTicks: totalTicks,
        totalDeaths: totalDeaths,
        recoveryAttempts: recoveryAttempts,
        boundary: segmentBoundaryToReplan(boundary),
      );
    }
  }

  return (
    state: currentState,
    totalTicks: totalTicks,
    totalDeaths: totalDeaths,
    recoveryAttempts: recoveryAttempts,
    boundary: null,
  );
}

/// Result of a recovery attempt.
///
/// Contains the new state (possibly modified by recovery action), whether
/// the executor should stop and trigger a replan, and tracking info.
class RecoveryResult {
  const RecoveryResult({
    required this.state,
    required this.outcome,
    required this.newAttemptCount,
    this.boundary,
  });

  /// The state after recovery (may be modified if recovery succeeded).
  final GlobalState state;

  /// What happened during recovery.
  final RecoveryOutcome outcome;

  /// Updated attempt count for tracking.
  final int newAttemptCount;

  /// The boundary to report if stopping (null if continuing).
  final ReplanBoundary? boundary;

  /// Whether the executor should stop and potentially replan.
  bool get shouldStop =>
      outcome == RecoveryOutcome.replanRequired ||
      outcome == RecoveryOutcome.completed;

  /// Whether execution can continue (retry the current phase).
  bool get canContinue => outcome == RecoveryOutcome.recoveredRetry;
}

/// Outcome of a recovery attempt.
enum RecoveryOutcome {
  /// Recovery succeeded, retry the current micro-phase.
  recoveredRetry,

  /// Boundary indicates normal completion, stop execution.
  completed,

  /// Boundary requires replanning, stop execution.
  replanRequired,
}

/// Attempts plan-authorized recovery for a boundary.
///
/// ## Recovery Philosophy
///
/// The executor adapts to randomness ONLY via explicitly authorized actions.
/// Recovery is strictly limited to what the plan specifies - the executor
/// never makes autonomous strategic decisions.
///
/// ## Supported Recoveries
///
/// - **InventoryFull**: Sell using the provided sell policy, then retry.
///   The policy comes from: macro → segment → plan default.
///   If no policy is available, triggers replan.
///
/// - **WaitConditionSatisfied**: Stop (normal completion).
///
/// - **GoalReached**: Stop (plan succeeded).
///
/// - **InputsDepleted**: Stop and trigger replan. The executor does NOT
///   pick alternate producers - that's the planner's job via EnsureStock.
///
/// - **NoProgressPossible**: Stop and trigger replan.
///
/// - **Death**: Continue (deaths are handled by the simulator automatically).
///
/// - **All other boundaries**: Stop and trigger replan.
///
/// ## Guardrails
///
/// - Max recovery attempts per macro invocation prevents infinite loops.
/// - State-change detection: if recovery doesn't meaningfully change state
///   (e.g., selling produced 0 GP), it triggers replan to avoid loops.
///
/// ## Policy Hierarchy
///
/// The [sellPolicy] parameter should be resolved by the caller using:
/// 1. Macro's sell policy (if the macro specifies one)
/// 2. Segment's sell policy (from segment markers)
/// 3. Plan's default policy
///
/// The executor NEVER infers policy from goal during execution.
RecoveryResult attemptRecovery(
  GlobalState state,
  ReplanBoundary boundary,
  SellPolicy? sellPolicy,
  int currentAttempts,
  int maxAttempts,
) {
  // Handle completion boundaries first (no recovery needed)
  if (boundary is WaitConditionSatisfied || boundary is GoalReached) {
    return RecoveryResult(
      state: state,
      outcome: RecoveryOutcome.completed,
      newAttemptCount: currentAttempts,
      boundary: boundary,
    );
  }

  // Check recovery limit before attempting any recovery
  if (currentAttempts >= maxAttempts) {
    return RecoveryResult(
      state: state,
      outcome: RecoveryOutcome.replanRequired,
      newAttemptCount: currentAttempts,
      boundary: NoProgressPossible(
        reason: 'Recovery limit ($maxAttempts) exceeded - triggering replan',
      ),
    );
  }

  // Handle InventoryFull: sell using plan-authorized policy
  if (boundary is InventoryFull) {
    if (sellPolicy == null) {
      return RecoveryResult(
        state: state,
        outcome: RecoveryOutcome.replanRequired,
        newAttemptCount: currentAttempts + 1,
        boundary: const NoProgressPossible(
          reason:
              'InventoryFull but no sell policy provided - '
              'planner must specify sellPolicySpec',
        ),
      );
    }

    // Check if selling would actually free up space
    final gpBefore = state.gp;
    final inventoryUsedBefore = state.inventoryUsed;
    final sellableValue = effectiveCredits(state, sellPolicy) - gpBefore;

    if (sellableValue <= 0) {
      return RecoveryResult(
        state: state,
        outcome: RecoveryOutcome.replanRequired,
        newAttemptCount: currentAttempts + 1,
        boundary: const NoProgressPossible(
          reason:
              'InventoryFull with nothing to sell per policy - '
              'triggering replan',
        ),
      );
    }

    // Perform the sell
    final newState = applyInteraction(state, SellItems(sellPolicy));

    // State-change detection: verify we actually freed inventory space
    if (newState.inventoryUsed >= inventoryUsedBefore) {
      // Selling didn't free any space - this would loop forever
      return RecoveryResult(
        state: newState,
        outcome: RecoveryOutcome.replanRequired,
        newAttemptCount: currentAttempts + 1,
        boundary: const NoProgressPossible(
          reason: 'Selling did not free inventory space - triggering replan',
        ),
      );
    }

    // Recovery succeeded, retry the current phase
    return RecoveryResult(
      state: newState,
      outcome: RecoveryOutcome.recoveredRetry,
      newAttemptCount: currentAttempts + 1,
    );
  }

  // Handle Death: continue (simulator handles restart automatically)
  if (boundary is Death) {
    return RecoveryResult(
      state: state,
      outcome: RecoveryOutcome.recoveredRetry,
      newAttemptCount: currentAttempts,
      // Don't increment attempts for deaths - they're expected
    );
  }

  // Handle InputsDepleted: trigger replan
  // The executor does NOT pick alternate producers - that's the planner's job
  if (boundary is InputsDepleted) {
    return RecoveryResult(
      state: state,
      outcome: RecoveryOutcome.replanRequired,
      newAttemptCount: currentAttempts,
      boundary: boundary,
    );
  }

  // Handle NoProgressPossible: trigger replan
  if (boundary is NoProgressPossible) {
    return RecoveryResult(
      state: state,
      outcome: RecoveryOutcome.replanRequired,
      newAttemptCount: currentAttempts,
      boundary: boundary,
    );
  }

  // Handle optimization opportunities: trigger replan to take advantage
  if (boundary is UpgradeAffordableEarly || boundary is UnexpectedUnlock) {
    return RecoveryResult(
      state: state,
      outcome: RecoveryOutcome.replanRequired,
      newAttemptCount: currentAttempts,
      boundary: boundary,
    );
  }

  // Handle error boundaries: trigger replan
  if (boundary is CannotAfford || boundary is ActionUnavailable) {
    return RecoveryResult(
      state: state,
      outcome: RecoveryOutcome.replanRequired,
      newAttemptCount: currentAttempts,
      boundary: boundary,
    );
  }

  // Fallback for any unhandled boundary types: trigger replan
  return RecoveryResult(
    state: state,
    outcome: RecoveryOutcome.replanRequired,
    newAttemptCount: currentAttempts,
    boundary: boundary,
  );
}

/// Executes a TrainSkillUntil macro with boundary checking.
///
/// This allows mid-macro stopping when a material boundary (upgrade affordable,
/// unlock reached, etc.) is detected during execution.
StepResult executeTrainSkillWithBoundaryChecks(
  GlobalState state,
  WaitFor waitFor,
  Random random,
  WatchSet watchSet,
) {
  // Check for material boundary before starting
  final initialBoundary = watchSet.detectBoundary(state, elapsedTicks: 0);
  if (initialBoundary != null) {
    return (
      state: state,
      ticksElapsed: 0,
      deaths: 0,
      boundary: segmentBoundaryToReplan(initialBoundary),
    );
  }

  // Execute until the wait condition is satisfied
  final result = consumeUntil(state, waitFor, random: random);

  // Check for material boundary after execution
  final materialBoundary = watchSet.detectBoundary(
    result.state,
    elapsedTicks: result.ticksElapsed,
  );
  if (materialBoundary != null) {
    return (
      state: result.state,
      ticksElapsed: result.ticksElapsed,
      deaths: result.deathCount,
      boundary: segmentBoundaryToReplan(materialBoundary),
    );
  }

  // If consumeUntil returned a boundary, check if it's material
  if (result.boundary != null && watchSet.isMaterial(result.boundary!)) {
    return (
      state: result.state,
      ticksElapsed: result.ticksElapsed,
      deaths: result.deathCount,
      boundary: result.boundary,
    );
  }

  return (
    state: result.state,
    ticksElapsed: result.ticksElapsed,
    deaths: result.deathCount,
    boundary: result.boundary,
  );
}

/// Counts inventory items by MelvorId.
int countItem(GlobalState state, MelvorId itemId) {
  return state.inventory.items
      .where((s) => s.item.id == itemId)
      .map((s) => s.count)
      .fold(0, (a, b) => a + b);
}

/// Applies a single plan step.
///
/// If [segmentSellPolicy] is provided, it is used for selling decisions
/// (e.g., when handling inventory full during EnsureStock). If not provided,
/// a fallback policy is computed on-demand.
StepResult applyStep(
  GlobalState state,
  PlanStep step, {
  required Random random,
  Map<Skill, SkillBoundaries>? boundaries,
  WatchSet? watchSet,
  SellPolicy? segmentSellPolicy,
}) {
  switch (step) {
    case InteractionStep(:final interaction):
      try {
        return (
          state: applyInteraction(state, interaction),
          ticksElapsed: 0,
          deaths: 0,
          boundary: null, // Interactions are instant, no boundary
        );
      } on Exception catch (e) {
        // Interaction failed (e.g., can't start action due to missing inputs)
        return (
          state: state,
          ticksElapsed: 0,
          deaths: 0,
          boundary: NoProgressPossible(reason: e.toString()),
        );
      }
    case WaitStep(:final waitFor, :final expectedAction):
      var waitState = state;
      // Switch to expected action if specified and not already active
      if (expectedAction != null &&
          waitState.activeAction?.id != expectedAction) {
        try {
          waitState = applyInteraction(
            waitState,
            SwitchActivity(expectedAction),
          );
        } on Exception catch (e) {
          return (
            state: state,
            ticksElapsed: 0,
            deaths: 0,
            boundary: NoProgressPossible(
              reason: 'Cannot start expected action: $e',
            ),
          );
        }
      }

      // Run until the wait condition is satisfied
      final result = consumeUntil(waitState, waitFor, random: random);

      // Check for material boundary after waiting (mid-step stopping)
      if (watchSet != null) {
        final materialBoundary = watchSet.detectBoundary(
          result.state,
          elapsedTicks: result.ticksElapsed,
        );
        if (materialBoundary != null) {
          return (
            state: result.state,
            ticksElapsed: result.ticksElapsed,
            deaths: result.deathCount,
            boundary: segmentBoundaryToReplan(materialBoundary),
          );
        }
      }

      return (
        state: result.state,
        ticksElapsed: result.ticksElapsed,
        deaths: result.deathCount,
        boundary: result.boundary,
      );
    case MacroStep(:final macro, :final waitFor):
      // Execute the macro by running until the composite wait condition
      var executionState = state;
      var executionWaitFor = waitFor;

      if (macro is TrainSkillUntil) {
        // Use the action that was determined during planning
        final actionToUse =
            macro.actionId ??
            findBestActionForSkill(
              state,
              macro.skill,
              ReachSkillLevelGoal(macro.skill, 99),
            );
        if (actionToUse != null && state.activeAction?.id != actionToUse) {
          executionState = applyInteraction(state, SwitchActivity(actionToUse));
        }

        // Regenerate WaitFor based on actual execution state and action
        if (boundaries != null) {
          final waitConditions = macro.allStops
              .map((rule) => rule.toWaitFor(executionState, boundaries))
              .toList();
          executionWaitFor = waitConditions.length == 1
              ? waitConditions.first
              : WaitForAnyOf(waitConditions);
        }

        // Execute with mid-macro boundary checking if watchSet provided
        if (watchSet != null) {
          return executeTrainSkillWithBoundaryChecks(
            executionState,
            executionWaitFor,
            random,
            watchSet,
          );
        }
      } else if (macro is TrainConsumingSkillUntil) {
        // Execute coupled produce/consume loop until stop condition
        return executeCoupledLoop(
          state,
          macro,
          waitFor,
          boundaries,
          random,
          watchSet: watchSet,
          segmentSellPolicy: segmentSellPolicy,
        );
      } else if (macro is AcquireItem) {
        // Execute AcquireItem by finding producer and running until target
        final startCount = countItem(executionState, macro.itemId);

        const goal = ReachSkillLevelGoal(Skill.mining, 99); // Placeholder goal
        final producer = findProducerActionForItem(
          executionState,
          macro.itemId,
          goal,
        );
        if (producer == null) {
          return (
            state: executionState,
            ticksElapsed: 0,
            deaths: 0,
            boundary: NoProgressPossible(
              reason: 'No producer for ${macro.itemId}',
            ),
          );
        }

        // Switch to producer action
        if (executionState.activeAction?.id != producer) {
          executionState = applyInteraction(
            executionState,
            SwitchActivity(producer),
          );
        }

        // Use delta-based wait condition: acquire quantity MORE items
        final acquireWaitFor = WaitForInventoryDelta(
          macro.itemId,
          macro.quantity,
          startCount: startCount,
        );

        final result = consumeUntil(
          executionState,
          acquireWaitFor,
          random: random,
        );

        return (
          state: result.state,
          ticksElapsed: result.ticksElapsed,
          deaths: result.deathCount,
          boundary: result.boundary,
        );
      } else if (macro is EnsureStock) {
        // Execute EnsureStock by finding producer and running until target
        // Handles inventory full by selling and continuing in a loop
        var currentState = executionState;
        var totalTicks = 0;
        var totalDeaths = 0;

        while (true) {
          final currentCount = countItem(currentState, macro.itemId);

          // If we already have enough, done
          if (currentCount >= macro.minTotal) {
            return (
              state: currentState,
              ticksElapsed: totalTicks,
              deaths: totalDeaths,
              boundary: const WaitConditionSatisfied(),
            );
          }

          const goal = ReachSkillLevelGoal(Skill.mining, 99);
          final producer = findProducerActionForItem(
            currentState,
            macro.itemId,
            goal,
          );
          if (producer == null) {
            return (
              state: currentState,
              ticksElapsed: totalTicks,
              deaths: totalDeaths,
              boundary: NoProgressPossible(
                reason: 'No producer for ${macro.itemId}',
              ),
            );
          }

          // Switch to producer action
          if (currentState.activeAction?.id != producer) {
            try {
              currentState = applyInteraction(
                currentState,
                SwitchActivity(producer),
              );
            } on Exception catch (e) {
              return (
                state: currentState,
                ticksElapsed: totalTicks,
                deaths: totalDeaths,
                boundary: NoProgressPossible(
                  reason: 'Cannot switch to producer for ${macro.itemId}: $e',
                ),
              );
            }
          }

          // Use absolute wait condition: wait until inventory has minTotal
          final stockWaitFor = WaitForInventoryAtLeast(
            macro.itemId,
            macro.minTotal,
          );

          final result = consumeUntil(
            currentState,
            stockWaitFor,
            random: random,
          );

          currentState = result.state;
          totalTicks += result.ticksElapsed;
          totalDeaths += result.deathCount;

          // Check if we hit inventory full - sell and continue
          if (result.boundary is InventoryFull) {
            // Use segment's sell policy. If not provided, this is an error -
            // callers should resolve policy before calling applyStep.
            if (segmentSellPolicy == null) {
              return (
                state: currentState,
                ticksElapsed: totalTicks,
                deaths: totalDeaths,
                boundary: NoProgressPossible(
                  reason:
                      'Inventory full during EnsureStock '
                      '${macro.itemId.name} but no sell policy provided',
                ),
              );
            }

            final sellableValue =
                effectiveCredits(currentState, segmentSellPolicy) -
                currentState.gp;

            if (sellableValue > 0) {
              currentState = applyInteraction(
                currentState,
                SellItems(segmentSellPolicy),
              );
              // Continue the loop to produce more
              continue;
            } else {
              // Nothing to sell - truly stuck
              return (
                state: currentState,
                ticksElapsed: totalTicks,
                deaths: totalDeaths,
                boundary: result.boundary,
              );
            }
          }

          // For any other boundary or success, return
          return (
            state: currentState,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: result.boundary,
          );
        }
      }

      final result = consumeUntil(
        executionState,
        executionWaitFor,
        random: random,
      );
      return (
        state: result.state,
        ticksElapsed: result.ticksElapsed,
        deaths: result.deathCount,
        boundary: result.boundary,
      );
  }
}

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
      };
      if (actionId == null) return 0;
      final rates = estimateRatesForAction(state, actionId);
      return waitFor.estimateTicks(state, rates);
  }
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

  /// Fallback policy computed because no segment policy was available.
  fallback,
}

/// Resolves the sell policy for a step during execution.
///
/// Resolution hierarchy (first match wins):
/// 1. Step-level: If the step is a SellItems interaction, use its policy
/// 2. Segment-level: Use the policy from the segment marker
/// 3. Fallback: Compute a conservative policy based on context
///
/// The [fallbackPolicy] function is called only if no step or segment policy
/// is available. This allows the caller to provide context-specific fallbacks.
ResolvedSellPolicy resolveSellPolicy({
  required PlanStep step,
  required Plan plan,
  required int stepIndex,
  required SellPolicy Function() fallbackPolicy,
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

  // 3. Fallback: Use provided fallback function
  return ResolvedSellPolicy(
    policy: fallbackPolicy(),
    source: SellPolicySource.fallback,
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

/// Creates a fallback sell policy for a given state.
///
/// This is used when no segment-level policy is available (legacy plans).
/// The fallback policy keeps items that are inputs to unlocked consuming
/// actions, which is a conservative default.
SellPolicy createFallbackSellPolicy(GlobalState state) {
  // Keep all inputs for unlocked consuming actions
  final keepItems = <MelvorId>{};
  for (final action in state.registries.actions.all) {
    if (action is SkillAction) {
      final skillLevel = state.skillState(action.skill).skillLevel;
      final isUnlocked = skillLevel >= action.unlockLevel;
      if (isUnlocked) {
        keepItems.addAll(action.inputs.keys);
      }
    }
  }
  return SellExceptPolicy(keepItems);
}

/// Execute a plan and return the result including death count and actual ticks.
///
/// Uses goal-aware waiting: [WaitStep.waitFor] determines when to stop waiting,
/// which handles variance between expected-value planning and full simulation.
/// Deaths are automatically handled by restarting the activity and are counted.
PlanExecutionResult executePlan(
  GlobalState originalState,
  Plan plan, {
  required Random random,
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
    // step → segment → fallback
    final currentState = state; // Capture for fallback closure
    final resolved = resolveSellPolicy(
      step: step,
      plan: plan,
      stepIndex: i,
      fallbackPolicy: () {
        // Warn when using fallback - indicates legacy plan without segment
        // policies. This helps diagnose when plans need to be regenerated.
        // ignore: avoid_print
        print('[WARN] No segment sellPolicy at step $i; using fallback');
        return createFallbackSellPolicy(currentState);
      },
    );

    // Capture state before execution for diagnostics
    final stateBefore = state;

    // Compute estimated ticks at execution time (recompute from current state)
    final estimatedTicksAtExecution = _estimateTicksAtExecution(state, step);

    try {
      final result = applyStep(
        state,
        step,
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
    required this.plannedTicks,
    required this.actualTicks,
    required this.deaths,
    required this.triggeredReplan,
    this.replanBoundary,
  });

  final int plannedTicks;
  final int actualTicks;
  final int deaths;
  final bool triggeredReplan;
  final ReplanBoundary? replanBoundary;
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
