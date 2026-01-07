/// Helper functions for step execution.
///
/// This file contains functions extracted from execute_plan.dart to avoid
/// circular imports between plan.dart (which defines step classes with
/// apply() methods) and execute_plan.dart (which defines executePlan).
library;

import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/analysis/watch_set.dart';
import 'package:logic/src/solver/candidates/build_chain.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/candidates/macro_execute_context.dart';
import 'package:logic/src/solver/execution/consume_until.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/interactions/apply_interaction.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';

/// Converts a SegmentBoundary to a ReplanBoundary for step return.
///
/// This is used when mid-macro stopping detects a material boundary.
/// The mapping preserves the boundary's semantics:
///
/// - **Goal completion**: [GoalReachedBoundary] → [GoalReached]
/// - **Optimization**: [UpgradeAffordableBoundary] → [UpgradeAffordableEarly]
/// - **Resource issues**: [InputsDepletedBoundary] → [InputsDepleted]
/// - **Planned stops**: Other boundaries → [PlannedSegmentStop] or specific
///   types
///
/// ## Key Principle
///
/// We do NOT map planned stops to [GoalReached] - that would cause the outer
/// loop to terminate early. Instead, planned stops signal "continue to next
/// segment" via [PlannedSegmentStop] or specific boundary types.
ReplanBoundary segmentBoundaryToReplan(SegmentBoundary boundary) {
  return switch (boundary) {
    // Goal completion - truly done
    GoalReachedBoundary() => const GoalReached(),

    // Optimization opportunity - replan to take advantage
    UpgradeAffordableBoundary(:final purchaseId) => UpgradeAffordableEarly(
      purchaseId: purchaseId,
    ),

    // Unlock observed - replan to potentially use new actions
    UnlockBoundary(:final skill, :final level, :final unlocks) =>
      UnlockObserved(skill: skill, level: level, unlocks: unlocks),

    // Resource issue - needs handling
    InputsDepletedBoundary(:final actionId, :final missingItemId) =>
      InputsDepleted(actionId: actionId, missingItemId: missingItemId),

    // Planned stop - continue to next segment (not goal reached!)
    HorizonCapBoundary() => PlannedSegmentStop(boundary),

    // Inventory pressure - distinct from InventoryFull
    InventoryPressureBoundary(
      :final usedSlots,
      :final totalSlots,
      :final blockedItemId,
    ) =>
      InventoryPressure(
        usedSlots: usedSlots,
        totalSlots: totalSlots,
        blockedItemId: blockedItemId,
      ),
  };
}

/// Counts inventory items by MelvorId.
int countItem(GlobalState state, MelvorId itemId) {
  return state.inventory.items
      .where((s) => s.item.id == itemId)
      .map((s) => s.count)
      .fold(0, (a, b) => a + b);
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
    return StepResult(
      state: state,
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
    return StepResult(
      state: result.state,
      ticksElapsed: result.ticksElapsed,
      deaths: result.deathCount,
      boundary: segmentBoundaryToReplan(materialBoundary),
    );
  }

  // If consumeUntil returned a boundary, check if it's material
  if (result.boundary != null && watchSet.isMaterial(result.boundary!)) {
    return StepResult(
      state: result.state,
      ticksElapsed: result.ticksElapsed,
      deaths: result.deathCount,
      boundary: result.boundary,
    );
  }

  return StepResult(
    state: result.state,
    ticksElapsed: result.ticksElapsed,
    deaths: result.deathCount,
    boundary: result.boundary,
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

  /// Creates a result indicating normal completion (goal reached, etc.).
  const RecoveryResult.completed(
    this.state, {
    required this.boundary,
    required int attemptCount,
  }) : outcome = RecoveryOutcome.completed,
       newAttemptCount = attemptCount;

  /// Creates a result indicating a replan is required.
  const RecoveryResult.replan(
    this.state, {
    required this.boundary,
    required int attemptCount,
  }) : outcome = RecoveryOutcome.replanRequired,
       newAttemptCount = attemptCount;

  /// Creates a result indicating recovery succeeded, retry the current phase.
  const RecoveryResult.retry(this.state, {required int attemptCount})
    : outcome = RecoveryOutcome.recoveredRetry,
      newAttemptCount = attemptCount,
      boundary = null;

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

/// Handles a boundary by determining the appropriate recovery outcome.
///
/// This function classifies boundaries and attempts recovery where applicable.
/// It maps each boundary type to one of three outcomes:
///
/// - **completed**: Normal completion, stop execution successfully
/// - **recoveredRetry**: Recovery succeeded (or not needed), retry current
///   phase
/// - **replanRequired**: Cannot continue, need to replan
///
/// ## Boundary Classification
///
/// | Boundary Type | Outcome | Recovery Action |
/// |--------------|---------|-----------------|
/// | WaitConditionSatisfied | completed | None |
/// | GoalReached | completed | None |
/// | InventoryFull | recoveredRetry* | Sell items per policy |
/// | InventoryPressure | recoveredRetry* | Sell items per policy |
/// | Death | recoveredRetry | None (simulator handles) |
/// | InputsDepleted | replanRequired | None |
/// | NoProgressPossible | replanRequired | None |
/// | UpgradeAffordableEarly | replanRequired | None |
/// | UnlockObserved | replanRequired | None |
/// | UnexpectedUnlock | replanRequired | None |
/// | PlannedSegmentStop | replanRequired | None |
/// | CannotAfford | replanRequired | None |
/// | ActionUnavailable | replanRequired | None |
///
/// *Inventory boundaries trigger replan if no sell policy or selling fails.
///
/// ## Guardrails
///
/// - Max recovery attempts per macro invocation prevents infinite loops.
/// - State-change detection: if selling doesn't free space, triggers replan.
///
/// ## Policy Hierarchy
///
/// The [sellPolicy] parameter should be resolved by the caller using:
/// 1. Macro's sell policy (if the macro specifies one)
/// 2. Segment's sell policy (from segment markers)
/// 3. Plan's default policy
///
/// The executor NEVER infers policy from goal during execution.
RecoveryResult handleBoundary(
  GlobalState state,
  ReplanBoundary boundary, {
  required Random random,
  required int currentAttempts,
  required int maxAttempts,
  SellPolicy? sellPolicy,
}) {
  // Handle completion boundaries first (no recovery needed)
  if (boundary is WaitConditionSatisfied || boundary is GoalReached) {
    return RecoveryResult.completed(
      state,
      boundary: boundary,
      attemptCount: currentAttempts,
    );
  }

  // Check recovery limit before attempting any recovery
  if (currentAttempts >= maxAttempts) {
    return RecoveryResult.replan(
      state,
      boundary: NoProgressPossible(
        reason: 'Recovery limit ($maxAttempts) exceeded - triggering replan',
      ),
      attemptCount: currentAttempts,
    );
  }

  // Handle InventoryFull or InventoryPressure: sell using plan-authorized
  // policy. InventoryPressure is a softer version - we sell a bit and continue
  // rather than requiring a full reset.
  if (boundary is InventoryFull || boundary is InventoryPressure) {
    if (sellPolicy == null) {
      final boundaryName = boundary is InventoryPressure
          ? 'InventoryPressure'
          : 'InventoryFull';
      return RecoveryResult.replan(
        state,
        boundary: NoProgressPossible(
          reason:
              '$boundaryName but no sell policy provided - '
              'planner must specify sellPolicySpec',
        ),
        attemptCount: currentAttempts + 1,
      );
    }

    // Check if selling would actually free up space
    final gpBefore = state.gp;
    final inventoryUsedBefore = state.inventoryUsed;
    final sellableValue = effectiveCredits(state, sellPolicy) - gpBefore;

    if (sellableValue <= 0) {
      // For InventoryPressure, if we can't sell, that's ok - we can continue
      // until truly full. For InventoryFull, we're stuck.
      if (boundary is InventoryPressure) {
        // Don't increment - pressure without sellable items is ok
        return RecoveryResult.retry(state, attemptCount: currentAttempts);
      }
      return RecoveryResult.replan(
        state,
        boundary: const NoProgressPossible(
          reason:
              'InventoryFull with nothing to sell per policy - '
              'triggering replan',
        ),
        attemptCount: currentAttempts + 1,
      );
    }

    // Perform the sell
    final newState = applyInteraction(
      state,
      SellItems(sellPolicy),
      random: random,
    );

    // State-change detection: verify we actually freed inventory space
    if (newState.inventoryUsed >= inventoryUsedBefore) {
      // Selling didn't free any space - this would loop forever
      // For pressure, this is ok to continue without incrementing attempts
      if (boundary is InventoryPressure) {
        return RecoveryResult.retry(newState, attemptCount: currentAttempts);
      }
      return RecoveryResult.replan(
        newState,
        boundary: const NoProgressPossible(
          reason: 'Selling did not free inventory space - triggering replan',
        ),
        attemptCount: currentAttempts + 1,
      );
    }

    // Recovery succeeded, retry the current phase
    return RecoveryResult.retry(newState, attemptCount: currentAttempts + 1);
  }

  // Handle Death: attempt recovery (re-equip lost item, restart activity)
  if (boundary is Death) {
    var newState = state;

    // Attempt to re-equip lost item from inventory if available
    final lostItem = boundary.lostItem;
    final slotRolled = boundary.slotRolled;
    if (lostItem != null && slotRolled != null) {
      final item = lostItem.item;
      final hasInInventory = newState.inventory.countOfItem(item) >= 1;
      if (hasInInventory && item.canEquipInSlot(slotRolled)) {
        // Re-equip the lost item
        newState = newState.equipGear(item, slotRolled);
      }
      // If we can't re-equip, increment attempts (potential escalation)
      if (!hasInInventory || !item.canEquipInSlot(slotRolled)) {
        // Track this as a recovery attempt since we couldn't fully recover
        final newAttempts = currentAttempts + 1;
        if (newAttempts >= maxAttempts) {
          return RecoveryResult.replan(
            newState,
            boundary: NoProgressPossible(
              reason:
                  'Death recovery limit ($maxAttempts) exceeded - '
                  'lost ${lostItem.item.name} cannot be re-equipped',
            ),
            attemptCount: newAttempts,
          );
        }
        return RecoveryResult.retry(newState, attemptCount: newAttempts);
      }
    }

    // Restart the activity if we know what was running
    final actionId = boundary.actionId;
    if (actionId != null) {
      try {
        newState = applyInteraction(
          newState,
          SwitchActivity(actionId),
          random: random,
        );
      } on Exception {
        // Can't restart the action - trigger replan
        return RecoveryResult.replan(
          newState,
          boundary: NoProgressPossible(
            reason:
                'Death recovery failed - cannot restart action '
                '${actionId.localId.name}',
          ),
          attemptCount: currentAttempts + 1,
        );
      }
    }

    // Successfully recovered - retry without incrementing attempts
    // (deaths with successful recovery are expected in risky actions)
    return RecoveryResult.retry(newState, attemptCount: currentAttempts);
  }

  // Handle InputsDepleted: trigger replan
  // The executor does NOT pick alternate producers - that's the planner's job
  if (boundary is InputsDepleted) {
    return RecoveryResult.replan(
      state,
      boundary: boundary,
      attemptCount: currentAttempts,
    );
  }

  // Handle NoProgressPossible: trigger replan
  if (boundary is NoProgressPossible) {
    return RecoveryResult.replan(
      state,
      boundary: boundary,
      attemptCount: currentAttempts,
    );
  }

  // Handle optimization opportunities: trigger replan to take advantage
  if (boundary is UpgradeAffordableEarly ||
      boundary is UnexpectedUnlock ||
      boundary is UnlockObserved) {
    return RecoveryResult.replan(
      state,
      boundary: boundary,
      attemptCount: currentAttempts,
    );
  }

  // Handle planned segment stops: trigger replan to continue to next segment
  if (boundary is PlannedSegmentStop) {
    return RecoveryResult.replan(
      state,
      boundary: boundary,
      attemptCount: currentAttempts,
    );
  }

  // Handle error boundaries: trigger replan
  if (boundary is CannotAfford || boundary is ActionUnavailable) {
    return RecoveryResult.replan(
      state,
      boundary: boundary,
      attemptCount: currentAttempts,
    );
  }

  // Fallback for any unhandled boundary types: trigger replan
  return RecoveryResult.replan(
    state,
    boundary: boundary,
    attemptCount: currentAttempts,
  );
}

// ---------------------------------------------------------------------------
// Multi-tier chain production helper
// ---------------------------------------------------------------------------

/// Result of producing a multi-tier chain.
typedef ChainProductionResult = ({
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
ChainProductionResult produceChainBottomUp(
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
      final childResult = produceChainBottomUp(
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
          random: random,
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
        final recovery = handleBoundary(
          currentState,
          const InventoryFull(),
          sellPolicy: segmentSellPolicy,
          random: random,
          currentAttempts: recoveryAttempts,
          maxAttempts: maxRecoveryAttempts,
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
      random: random,
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
    final recovery = handleBoundary(
      currentState,
      const InventoryFull(),
      sellPolicy: segmentSellPolicy,
      random: random,
      currentAttempts: recoveryAttempts,
      maxAttempts: maxRecoveryAttempts,
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
///     if (boundary) handleBoundary or return
///   }
///
///   // CONSUME PHASE
///   SwitchActivity(macro.consumeActionId)  // Fixed ID
///   consumeUntil(WaitForAnyOf([
///     primaryStopWait,
///     InputsDepleted(consumeActionId),
///     InventoryPressure,  // Stop early if nearly full
///   ]))
///   if (boundary) handleBoundary or return
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
  MacroExecuteContext context,
  TrainConsumingSkillUntil macro,
) {
  var state = context.state;
  var totalTicks = 0;
  var totalDeaths = 0;
  var recoveryAttempts = 0;

  // ---------------------------------------------------------------------------
  // VALIDATION: Require all plan-specified fields (no fallbacks)
  // ---------------------------------------------------------------------------

  final consumeActionId = macro.consumeActionId ?? macro.actionId;
  if (consumeActionId == null) {
    return StepResult(
      state: state,
      boundary: const NoProgressPossible(
        reason: 'Macro missing consumeActionId - solver must specify',
      ),
    );
  }

  final consumeAction = state.registries.actions.byId(consumeActionId);
  if (consumeAction is! SkillAction || consumeAction.inputs.isEmpty) {
    return StepResult(
      state: state,
      boundary: const NoProgressPossible(
        reason: 'Consume action has no inputs',
      ),
    );
  }

  final bufferTarget = macro.bufferTarget;
  if (bufferTarget == null) {
    return StepResult(
      state: state,
      boundary: const NoProgressPossible(
        reason: 'Macro missing bufferTarget - solver must specify',
      ),
    );
  }

  final producerByInputItem = macro.producerByInputItem;
  if (producerByInputItem == null) {
    return StepResult(
      state: state,
      boundary: const NoProgressPossible(
        reason: 'Macro missing producerByInputItem - solver must specify',
      ),
    );
  }

  // Compute primary stop condition
  final primaryStop = context.boundaries != null
      ? macro.primaryStop.toWaitFor(state, context.boundaries!)
      : context.waitFor;

  // Inventory pressure threshold (stop consume phase early if nearly full)
  const inventoryPressureThreshold = 0.9;

  // ---------------------------------------------------------------------------
  // MAIN LOOP: Repeat produce-consume cycles until primary stop
  // ---------------------------------------------------------------------------

  while (true) {
    // -------------------------------------------------------------------------
    // CHECKPOINT: Start of cycle - check if done
    // -------------------------------------------------------------------------

    if (primaryStop.isSatisfied(state)) {
      return StepResult(
        state: state,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: const WaitConditionSatisfied(),
      );
    }

    // Check for material boundary (upgrade affordable, unlock, etc.)
    if (context.watchSet != null) {
      final boundary = context.watchSet!.detectBoundary(
        state,
        elapsedTicks: totalTicks,
      );
      if (boundary != null) {
        return StepResult(
          state: state,
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
      final currentCount = state.inventory.countOfItem(
        state.registries.items.byId(inputItemId),
      );

      if (currentCount >= bufferTarget) {
        continue; // Have enough, skip to next input
      }

      // Check if this input has a multi-tier chain
      final inputChain = macro.inputChains?[inputItemId];
      if (inputChain != null && inputChain.children.isNotEmpty) {
        // Multi-tier chain: produce inputs bottom-up
        final chainResult = produceChainBottomUp(
          state,
          inputChain,
          bufferTarget,
          context.random,
          context.watchSet,
          context.segmentSellPolicy,
          totalTicks,
          totalDeaths,
          recoveryAttempts,
          macro.maxRecoveryAttempts,
        );
        state = chainResult.state;
        totalTicks = chainResult.totalTicks;
        totalDeaths = chainResult.totalDeaths;
        recoveryAttempts = chainResult.recoveryAttempts;

        if (chainResult.boundary != null) {
          return StepResult(
            state: state,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: chainResult.boundary,
          );
        }
      } else {
        // Simple single-tier production
        // Get producer from plan (no runtime search)
        final producerId = producerByInputItem[inputItemId];
        if (producerId == null) {
          return StepResult(
            state: state,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: NoProgressPossible(
              reason: 'No producer for ${inputItemId.localId} - needs replan',
            ),
          );
        }

        // CHECKPOINT: Switch to producer (fixed ID from plan)
        try {
          state = applyInteraction(
            state,
            SwitchActivity(producerId),
            random: context.random,
          );
        } on Exception catch (e) {
          // Producer not feasible (missing its own inputs) - replan
          return StepResult(
            state: state,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: NoProgressPossible(
              reason: 'Cannot start producer $producerId: $e',
            ),
          );
        }

        // Produce until buffer target reached
        final produceResult = consumeUntil(
          state,
          WaitForInventoryAtLeast(inputItemId, bufferTarget),
          random: context.random,
        );
        state = produceResult.state;
        totalTicks += produceResult.ticksElapsed;
        totalDeaths += produceResult.deathCount;

        // CHECKPOINT: Handle production boundaries
        if (produceResult.boundary is InventoryFull) {
          final recovery = handleBoundary(
            state,
            const InventoryFull(),
            sellPolicy: context.segmentSellPolicy,
            random: context.random,
            currentAttempts: recoveryAttempts,
            maxAttempts: macro.maxRecoveryAttempts,
          );
          if (recovery.shouldStop) {
            return StepResult(
              state: recovery.state,
              ticksElapsed: totalTicks,
              deaths: totalDeaths,
              boundary: recovery.boundary,
            );
          }
          state = recovery.state;
          recoveryAttempts = recovery.newAttemptCount;
          // Retry this input's production by breaking to outer loop
          break;
        }

        // Check for material boundary after producing
        if (context.watchSet != null) {
          final boundary = context.watchSet!.detectBoundary(
            state,
            elapsedTicks: totalTicks,
          );
          if (boundary != null) {
            return StepResult(
              state: state,
              ticksElapsed: totalTicks,
              deaths: totalDeaths,
              boundary: segmentBoundaryToReplan(boundary),
            );
          }
        }
      }
    }

    // CHECKPOINT: After produce phase - check stop again
    if (primaryStop.isSatisfied(state)) {
      return StepResult(
        state: state,
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
      state = applyInteraction(
        state,
        SwitchActivity(consumeActionId),
        random: context.random,
      );
    } on Exception catch (e) {
      return StepResult(
        state: state,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: NoProgressPossible(
          reason: 'Cannot start consumer $consumeActionId: $e',
        ),
      );
    }

    // Consume until: primary stop OR inputs depleted OR inventory pressure
    final consumeResult = consumeUntil(
      state,
      WaitForAnyOf([
        primaryStop,
        WaitForInputsDepleted(consumeActionId),
        const WaitForInventoryThreshold(inventoryPressureThreshold),
      ]),
      random: context.random,
    );
    state = consumeResult.state;
    totalTicks += consumeResult.ticksElapsed;
    totalDeaths += consumeResult.deathCount;

    // CHECKPOINT: Handle consumption boundaries
    // Check if we need inventory recovery. This can happen two ways:
    // 1. consumeUntil returned InventoryFull boundary
    // 2. WaitForInventoryThreshold was satisfied (via satisfiedWaitFor)
    final satisfiedCondition = switch (consumeResult.boundary) {
      WaitConditionSatisfied(:final satisfiedWaitFor) => satisfiedWaitFor,
      _ => null,
    };
    final needsInventoryRecovery =
        consumeResult.boundary is InventoryFull ||
        satisfiedCondition is WaitForInventoryThreshold;

    if (needsInventoryRecovery) {
      final recovery = handleBoundary(
        state,
        const InventoryFull(),
        sellPolicy: context.segmentSellPolicy,
        random: context.random,
        currentAttempts: recoveryAttempts,
        maxAttempts: macro.maxRecoveryAttempts,
      );
      if (recovery.shouldStop) {
        return StepResult(
          state: recovery.state,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: recovery.boundary,
        );
      }
      state = recovery.state;
      recoveryAttempts = recovery.newAttemptCount;
      // Continue to next cycle (will produce more inputs)
      continue;
    }

    // Check for material boundary after consuming
    if (context.watchSet != null) {
      final boundary = context.watchSet!.detectBoundary(
        state,
        elapsedTicks: totalTicks,
      );
      if (boundary != null) {
        return StepResult(
          state: state,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: segmentBoundaryToReplan(boundary),
        );
      }
    }

    // Loop continues: next iteration will produce more inputs if needed
  }
}
