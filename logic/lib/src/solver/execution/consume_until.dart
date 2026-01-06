/// Consume-until logic for executing plans with goal-aware waiting.
///
/// Provides [consumeUntil] which runs the game simulation until a wait
/// condition is satisfied.
library;

import 'dart:math';

import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/core/solver.dart' show findProducersFor;
import 'package:logic/src/solver/execution/state_advance.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/types/equipment.dart';
import 'package:logic/src/types/time_away.dart';

/// Result of consuming ticks until a goal is reached.
class ConsumeUntilResult {
  ConsumeUntilResult({
    required this.state,
    required this.ticksElapsed,
    required this.deathCount,
    this.boundary,
  }) {
    assertValidState(state);
  }

  final GlobalState state;
  final int ticksElapsed;
  final int deathCount;

  /// The boundary that caused execution to pause, or null if the wait
  /// condition was satisfied normally.
  ///
  /// Expected boundaries (like [InputsDepleted]) are part of normal online
  /// execution. Unexpected boundaries may indicate bugs.
  final ReplanBoundary? boundary;
}

/// Advances state until a condition is satisfied.
///
/// Uses [consumeTicksUntil] to efficiently process ticks, checking the
/// condition after each action iteration. Automatically restarts the activity
/// after death and tracks how many deaths occurred.
///
/// Returns the final state, actual ticks elapsed, death count, and any
/// [ReplanBoundary] that caused execution to pause.
///
/// ## Boundary Handling
///
/// - [Death]: Auto-restarts the activity and continues (expected)
/// - [InputsDepleted]: For consuming actions, switches to producer to gather
///   more inputs, then continues (expected)
/// - [InventoryFull]: Returns with boundary set (caller decides what to do)
/// - [WaitConditionSatisfied]: Normal completion, boundary is null
///
/// Unexpected boundaries indicate potential bugs in the planner.
ConsumeUntilResult consumeUntil(
  GlobalState originalState,
  WaitFor waitFor, {
  required Random random,
}) {
  assertValidState(originalState);

  var state = originalState;
  final alreadySatisfied = waitFor.findSatisfied(state);
  if (alreadySatisfied != null) {
    // Already satisfied - return immediately with 0 ticks elapsed.
    // This can happen when a previous step in the plan already satisfied
    // the condition (e.g., multiple macros targeting the same boundary).
    return ConsumeUntilResult(
      state: state,
      ticksElapsed: 0,
      deathCount: 0,
      boundary: WaitConditionSatisfied(satisfiedWaitFor: alreadySatisfied),
    );
  }

  final originalActivityId = state.activeAction?.id;
  final actionRegistry = state.registries.actions;
  var totalTicksElapsed = 0;
  var deathCount = 0;
  var consecutiveZeroTickIterations = 0;
  const maxConsecutiveZeroTickIterations = 3;

  // Keep running until the condition is satisfied, restarting after deaths
  while (true) {
    final builder = StateUpdateBuilder(state);
    final progressBefore = waitFor.progress(state);

    // Use consumeTicksUntil which checks the condition after each action
    final stopReason = consumeTicksUntil(
      builder,
      random: random,
      stopCondition: (s) => waitFor.isSatisfied(s),
    );

    state = builder.build();
    totalTicksElapsed += builder.ticksElapsed;

    // Track consecutive zero-tick iterations to detect infinite loops
    if (builder.ticksElapsed == 0) {
      consecutiveZeroTickIterations++;
      if (consecutiveZeroTickIterations >= maxConsecutiveZeroTickIterations) {
        return ConsumeUntilResult(
          state: state,
          ticksElapsed: totalTicksElapsed,
          deathCount: deathCount,
          boundary: NoProgressPossible(
            reason:
                'No ticks elapsed for $consecutiveZeroTickIterations '
                'consecutive iterations on ${waitFor.describe()}',
          ),
        );
      }
    } else {
      consecutiveZeroTickIterations = 0;
    }

    // If we hit maxTicks without progress, we're stuck
    if (stopReason == ConsumeTicksStopReason.maxTicksReached) {
      final progressAfter = waitFor.progress(state);
      if (progressAfter <= progressBefore) {
        return ConsumeUntilResult(
          state: state,
          ticksElapsed: totalTicksElapsed,
          deathCount: deathCount,
          boundary: NoProgressPossible(
            reason:
                'Hit maxTicks (10h) with no progress on '
                '${waitFor.describe()}',
          ),
        );
      }
      // Made some progress but not enough - continue
    }

    // Check if we're done
    final satisfied = waitFor.findSatisfied(state);
    if (satisfied != null) {
      return ConsumeUntilResult(
        state: state,
        ticksElapsed: totalTicksElapsed,
        deathCount: deathCount,
        boundary: WaitConditionSatisfied(satisfiedWaitFor: satisfied),
      );
    }

    // Check if activity stopped
    if (builder.stopReason != ActionStopReason.stillRunning) {
      if (builder.stopReason == ActionStopReason.playerDied) {
        deathCount++;

        // Return Death boundary immediately with post-death state.
        // The boundary resolver layer handles re-equip/food recovery.
        return ConsumeUntilResult(
          state: state,
          ticksElapsed: totalTicksElapsed,
          deathCount: deathCount,
          boundary: Death(
            actionId: originalActivityId,
            lostItem: builder.lastDeathPenalty?.itemLost,
            slotRolled: builder.lastDeathPenalty?.slotRolled,
          ),
        );
      }

      // For other stop reasons (outOfInputs, inventoryFull), try to adapt.
      // For skill goals with consuming actions, switch to producer to gather
      // inputs.
      if (waitFor is WaitForSkillXp && originalActivityId != null) {
        final currentAction = actionRegistry.byId(originalActivityId);

        // Check if this is a consuming action (has inputs)
        if (currentAction is SkillAction && currentAction.inputs.isNotEmpty) {
          // Find producers for the inputs this action needs
          final producers = findProducersFor(
            state,
            currentAction,
            actionRegistry,
          );

          if (producers.isNotEmpty) {
            final producer = producers.first;
            final inputItemId = currentAction.inputs.keys.first;

            // Calculate buffer: enough to consume for ~5 minutes
            final consumptionRate = currentAction.inputs.values.first;
            final ticksPerConsume =
                (currentAction.minDuration.inMilliseconds /
                        Duration.millisecondsPerSecond *
                        10)
                    .round();
            const bufferTicks = 3000; // 5 minutes at 100ms/tick
            final bufferCount =
                ((bufferTicks / ticksPerConsume) * consumptionRate).ceil();

            // Switch to producer (this is an expected InputsDepleted boundary)
            state = state.startAction(producer, random: random);

            // Gather inputs
            final gatherResult = consumeUntil(
              state,
              WaitForInventoryAtLeast(inputItemId, bufferCount),
              random: random,
            );
            state = gatherResult.state;
            totalTicksElapsed += gatherResult.ticksElapsed;
            deathCount += gatherResult.deathCount;

            // Try to switch back to consumer
            try {
              state = state.startAction(currentAction, random: random);
              continue; // Continue consuming
            } on Exception {
              // Can't restart consumer (still missing inputs) - fall through
              // to return the boundary
            }
          }
        }
      }

      // Cannot adapt - return with the boundary that caused the stop
      final inputItemId = originalActivityId != null
          ? () {
              final action = actionRegistry.byId(originalActivityId);
              if (action is SkillAction && action.inputs.isNotEmpty) {
                return action.inputs.keys.first;
              }
              return null;
            }()
          : null;

      final boundary = boundaryFromStopReason(
        builder.stopReason,
        actionId: originalActivityId,
        missingItemId: inputItemId,
      );

      return ConsumeUntilResult(
        state: state,
        ticksElapsed: totalTicksElapsed,
        deathCount: deathCount,
        boundary: boundary,
      );
    }

    // No progress possible
    if (builder.ticksElapsed == 0 && state.activeAction == null) {
      return ConsumeUntilResult(
        state: state,
        ticksElapsed: totalTicksElapsed,
        deathCount: deathCount,
        boundary: const NoProgressPossible(reason: 'No active action'),
      );
    }
  }
}

/// Creates a [ReplanBoundary] from an [ActionStopReason].
ReplanBoundary boundaryFromStopReason(
  ActionStopReason stopReason, {
  ActionId? actionId,
  MelvorId? missingItemId,
  DeathPenaltyResult? deathPenalty,
}) {
  return switch (stopReason) {
    ActionStopReason.stillRunning => const WaitConditionSatisfied(),
    ActionStopReason.playerDied => Death(
      actionId: actionId,
      lostItem: deathPenalty?.itemLost,
      slotRolled: deathPenalty?.slotRolled,
    ),
    ActionStopReason.outOfInputs =>
      actionId != null && missingItemId != null
          ? InputsDepleted(actionId: actionId, missingItemId: missingItemId)
          : const NoProgressPossible(reason: 'Out of inputs'),
    ActionStopReason.inventoryFull => const InventoryFull(),
  };
}
