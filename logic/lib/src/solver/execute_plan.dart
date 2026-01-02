/// Plan execution for the solver.
///
/// Provides [executePlan] and related step execution logic.
library;

import 'dart:math';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart' show Skill, SkillAction;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/apply_interaction.dart';
import 'package:logic/src/solver/consume_until.dart';
import 'package:logic/src/solver/estimate_rates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/prerequisites.dart';
import 'package:logic/src/solver/replan_boundary.dart';
import 'package:logic/src/solver/unlock_boundaries.dart';
import 'package:logic/src/solver/wait_for.dart';
import 'package:logic/src/solver/watch_set.dart';
import 'package:logic/src/state.dart';

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
/// Alternates between:
/// 1. Produce inputs (e.g., cut logs, catch fish) until buffer threshold
/// 2. Consume inputs (e.g., burn logs, cook fish) until depleted or stop
/// 3. Repeat until primary stop condition is met
StepResult executeCoupledLoop(
  GlobalState state,
  TrainConsumingSkillUntil macro,
  WaitFor waitFor,
  Map<Skill, SkillBoundaries>? boundaries,
  Random random, {
  WatchSet? watchSet,
}) {
  var currentState = state;
  var totalTicks = 0;
  var totalDeaths = 0;

  final goal = ReachSkillLevelGoal(macro.consumingSkill, 99);

  // Regenerate actual wait condition from primary stop
  final actualWaitFor = boundaries != null
      ? macro.primaryStop.toWaitFor(currentState, boundaries)
      : waitFor;

  // Execute coupled loop
  while (true) {
    // Check if primary stop condition is met
    if (actualWaitFor.isSatisfied(currentState)) {
      break;
    }

    // Check for material boundary (mid-macro stopping)
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

    // Re-evaluate best actions each iteration as levels may have changed
    final bestConsumeAction = findBestActionForSkill(
      currentState,
      macro.consumingSkill,
      goal,
    );
    if (bestConsumeAction == null) {
      return (
        state: currentState,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: const NoProgressPossible(reason: 'No consuming action found'),
      );
    }

    final consumeAction = currentState.registries.actions.byId(
      bestConsumeAction,
    );
    if (consumeAction is! SkillAction || consumeAction.inputs.isEmpty) {
      return (
        state: currentState,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: const NoProgressPossible(reason: 'Action has no inputs'),
      );
    }

    // Phase 1: Produce ALL inputs until we have a buffer of each.
    // This handles multi-input actions like Bronze Bar (Copper + Tin).
    // For multi-tier chains (e.g., Bronze Dagger needs Bronze Bar which needs
    // ores), we recursively ensure the producer's inputs are available first.
    const bufferTarget = 10;
    for (final inputEntry in consumeAction.inputs.entries) {
      final inputItem = inputEntry.key;
      final producerId = findProducerActionForItem(
        currentState,
        inputItem,
        goal,
      );
      if (producerId == null) {
        return (
          state: currentState,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: NoProgressPossible(
            reason: 'No producer action found for $inputItem',
          ),
        );
      }

      final currentCount = currentState.inventory.countOfItem(
        currentState.registries.items.byId(inputItem),
      );
      if (currentCount < bufferTarget) {
        // Check if the producer itself needs inputs (multi-tier chain)
        final producerAction = currentState.registries.actions.byId(producerId);
        if (producerAction is SkillAction && producerAction.inputs.isNotEmpty) {
          // Producer needs inputs - ensure those are available first
          for (final prodInput in producerAction.inputs.entries) {
            final prodInputCount = currentState.inventory.countOfItem(
              currentState.registries.items.byId(prodInput.key),
            );
            // Need enough to produce one batch at least
            if (prodInputCount < prodInput.value) {
              // Find the raw producer for this intermediate input
              final rawProducerId = findProducerActionForItem(
                currentState,
                prodInput.key,
                goal,
              );
              if (rawProducerId != null) {
                currentState = applyInteraction(
                  currentState,
                  SwitchActivity(rawProducerId),
                );
                // Produce enough for multiple batches
                final targetCount = prodInput.value * bufferTarget;
                final produceResult = consumeUntil(
                  currentState,
                  WaitForInventoryAtLeast(prodInput.key, targetCount),
                  random: random,
                );
                currentState = produceResult.state;
                totalTicks += produceResult.ticksElapsed;
                totalDeaths += produceResult.deathCount;

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
          }
        }

        currentState = applyInteraction(
          currentState,
          SwitchActivity(producerId),
        );

        final produceResult = consumeUntil(
          currentState,
          WaitForInventoryAtLeast(inputItem, bufferTarget),
          random: random,
        );
        currentState = produceResult.state;
        totalTicks += produceResult.ticksElapsed;
        totalDeaths += produceResult.deathCount;

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

    // Check stop condition again after producing
    if (actualWaitFor.isSatisfied(currentState)) {
      break;
    }

    // Phase 2: Consume inputs until depleted or stop condition
    try {
      currentState = applyInteraction(
        currentState,
        SwitchActivity(bestConsumeAction),
      );
    } on Exception catch (e) {
      // Cannot start consuming action (missing inputs)
      return (
        state: currentState,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: NoProgressPossible(
          reason: 'Cannot start consuming action: $e',
        ),
      );
    }

    final consumeResult = consumeUntil(
      currentState,
      WaitForAnyOf([actualWaitFor, WaitForInputsDepleted(bestConsumeAction)]),
      random: random,
    );
    currentState = consumeResult.state;
    totalTicks += consumeResult.ticksElapsed;
    totalDeaths += consumeResult.deathCount;

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

    // If we hit the stop condition, we're done
    if (actualWaitFor.isSatisfied(currentState)) {
      break;
    }

    // Otherwise, loop back to produce more inputs
  }

  // After the loop, switch to a producer action so subsequent steps can
  // produce items.
  final finalBestConsume = findBestActionForSkill(
    currentState,
    macro.consumingSkill,
    goal,
  );
  if (finalBestConsume != null) {
    final finalConsumeAction = currentState.registries.actions.byId(
      finalBestConsume,
    );
    if (finalConsumeAction is SkillAction &&
        finalConsumeAction.inputs.isNotEmpty) {
      // Find a producer we can actually start
      ActionId? targetProducer;
      var itemToCheck = finalConsumeAction.inputs.keys.first;

      // Walk up the production chain to find a feasible producer
      for (var depth = 0; depth < 5; depth++) {
        final producer = findProducerActionForItem(
          currentState,
          itemToCheck,
          goal,
        );
        if (producer == null) break;

        final producerAction = currentState.registries.actions.byId(producer);
        if (producerAction is! SkillAction) {
          targetProducer = producer;
          break;
        }

        // Check if this producer has all its inputs
        var hasAllInputs = true;
        MelvorId? missingInput;
        for (final input in producerAction.inputs.entries) {
          final count = currentState.inventory.countOfItem(
            currentState.registries.items.byId(input.key),
          );
          if (count < input.value) {
            hasAllInputs = false;
            missingInput = input.key;
            break;
          }
        }

        if (hasAllInputs || producerAction.inputs.isEmpty) {
          targetProducer = producer;
          break;
        }

        // Producer needs inputs, try to produce those instead
        if (missingInput != null) {
          itemToCheck = missingInput;
        } else {
          break;
        }
      }

      if (targetProducer != null &&
          currentState.activeAction?.id != targetProducer) {
        currentState = applyInteraction(
          currentState,
          SwitchActivity(targetProducer),
        );
      }
    }
  }

  return (
    state: currentState,
    ticksElapsed: totalTicks,
    deaths: totalDeaths,
    boundary: const WaitConditionSatisfied(),
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
