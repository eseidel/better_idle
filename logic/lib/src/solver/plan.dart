/// Plan representation: recorded steps for explanation/debugging.
///
/// ## Purpose
///
/// Plan steps are recorded for explanation, debugging, and UI display.
/// They reconstruct what the solver decided at each point.
///
/// ## Wait Steps
///
/// [WaitStep]s correspond to "interesting events" (goal, unlock, affordability,
/// death, skill/mastery level ups). Each wait may cross level boundaries where
/// rates change, so consecutive waits are NOT merged.
///
/// ## Future: Compression
///
/// A plan may be long if modeling micro-events (e.g., many short waits for
/// mastery gains). Later we may compress repeated cycles (e.g., "thieve until
/// dead, restart" loops) into macro steps for UI display.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/solver/solver.dart';
import 'package:logic/src/solver/wait_for.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Plan Steps
// ---------------------------------------------------------------------------

/// A single step in a plan.
sealed class PlanStep extends Equatable {
  const PlanStep();
}

/// A step that performs an interaction (switch activity, buy upgrade, sell).
@immutable
class InteractionStep extends PlanStep {
  const InteractionStep(this.interaction);

  final Interaction interaction;

  @override
  List<Object?> get props => [interaction];

  @override
  String toString() => 'InteractionStep($interaction)';
}

/// A step that waits for a condition to be met.
///
/// During planning, [deltaTicks] is the expected time to wait based on
/// expected-value modeling. During execution, [waitFor] is used to
/// determine when to stop waiting, which handles variance in actual
/// simulation vs expected values.
@immutable
class WaitStep extends PlanStep {
  const WaitStep(this.deltaTicks, this.waitFor);

  /// Expected ticks to wait (from planning).
  final int deltaTicks;

  /// What we're waiting for.
  final WaitFor waitFor;

  @override
  List<Object?> get props => [deltaTicks, waitFor];

  @override
  String toString() => 'WaitStep($deltaTicks ticks, ${waitFor.describe()})';
}

/// A step that represents executing a macro (train skill until boundary/goal).
///
/// Macros are high-level planning primitives that span many ticks and
/// automatically select the best action for a skill. During execution,
/// the macro is expanded into concrete interactions and waits.
@immutable
class MacroStep extends PlanStep {
  const MacroStep(this.macro, this.deltaTicks, this.waitFor);

  /// The macro candidate that was expanded.
  final MacroCandidate macro;

  /// Expected ticks for this macro (from planning).
  final int deltaTicks;

  /// Composite wait condition (AnyOf the macro's stop conditions).
  final WaitFor waitFor;

  @override
  List<Object?> get props => [macro, deltaTicks, waitFor];

  @override
  String toString() {
    if (macro is TrainSkillUntil) {
      final m = macro as TrainSkillUntil;
      return 'MacroStep(Train ${m.skill.name} for $deltaTicks ticks, '
          '${waitFor.describe()})';
    }
    return 'MacroStep($macro, $deltaTicks ticks, ${waitFor.describe()})';
  }
}

/// The result of running the solver.
@immutable
class Plan {
  const Plan({
    required this.steps,
    required this.totalTicks,
    required this.interactionCount,
    this.expandedNodes = 0,
    this.enqueuedNodes = 0,
    this.expectedDeaths = 0,
  });

  /// An empty plan (goal already satisfied).
  const Plan.empty()
    : steps = const [],
      totalTicks = 0,
      interactionCount = 0,
      expandedNodes = 0,
      enqueuedNodes = 0,
      expectedDeaths = 0;

  /// The sequence of steps to reach the goal.
  final List<PlanStep> steps;

  /// Total ticks required to reach the goal.
  final int totalTicks;

  /// Number of interactions (non-wait steps) in the plan.
  final int interactionCount;

  /// Number of nodes expanded during search (for debugging).
  final int expandedNodes;

  /// Number of nodes enqueued during search (for debugging).
  final int enqueuedNodes;

  /// Expected number of deaths during plan execution (from planning model).
  final int expectedDeaths;

  /// Human-readable total time.
  Duration get totalDuration => durationFromTicks(totalTicks);

  /// Returns a compressed version of this plan for display purposes.
  ///
  /// Compression rules:
  /// 1. Merges consecutive WaitSteps into a single wait with combined ticks
  /// 2. Removes no-op switches (SwitchActivity to the same activity)
  /// 3. Collapses "wake-only" waits where no interaction occurs between wakes
  ///    (e.g., consecutive mastery level-ups with no activity change)
  ///
  /// The compressed plan is for display only - it may not be directly
  /// executable since merged waits lose their intermediate WaitFor conditions.
  Plan compress() {
    if (steps.isEmpty) return this;

    final compressed = <PlanStep>[];
    ActionId? currentActivity;

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];

      switch (step) {
        case InteractionStep(:final interaction):
          switch (interaction) {
            case SwitchActivity(:final actionId):
              // Remove no-op switches (switching to same activity)
              if (actionId == currentActivity) continue;
              currentActivity = actionId;
              compressed.add(step);

            case BuyShopItem():
            case SellItems():
              compressed.add(step);
          }

        case WaitStep(:final deltaTicks, :final waitFor):
          // Check if we can merge with the previous step
          if (compressed.isNotEmpty && compressed.last is WaitStep) {
            // Check if there's no meaningful interaction between these waits
            // A meaningful interaction is anything except the wait itself
            // Since we're iterating in order, if the last compressed step
            // is a WaitStep, we can try to merge.
            final lastWait = compressed.last as WaitStep;

            // Merge consecutive waits - keep the final waitFor since that's
            // what we're ultimately waiting for
            compressed[compressed.length - 1] = WaitStep(
              lastWait.deltaTicks + deltaTicks,
              waitFor, // Use the later wait's condition
            );
          } else {
            compressed.add(step);
          }

        case MacroStep():
          // Macros are kept as-is, no compression
          compressed.add(step);
      }
    }

    // Recalculate interaction count (non-wait steps)
    final newInteractionCount = compressed.whereType<InteractionStep>().length;

    return Plan(
      steps: compressed,
      totalTicks: totalTicks,
      interactionCount: newInteractionCount,
      expandedNodes: expandedNodes,
      enqueuedNodes: enqueuedNodes,
      expectedDeaths: expectedDeaths,
    );
  }

  /// Pretty-prints the plan for debugging.
  String prettyPrint({int maxSteps = 30, ActionRegistry? actions}) {
    final buffer = StringBuffer()
      ..writeln('=== Plan ===')
      ..writeln('Total ticks: $totalTicks (${_formatDuration(totalDuration)})')
      ..writeln('Interactions: $interactionCount')
      ..writeln('Expanded nodes: $expandedNodes')
      ..writeln('Enqueued nodes: $enqueuedNodes')
      ..writeln('Steps (${steps.length} total):');

    final stepsToShow = steps.take(maxSteps).toList();
    for (var i = 0; i < stepsToShow.length; i++) {
      final step = stepsToShow[i];
      buffer.writeln('  ${i + 1}. ${_formatStep(step, actions)}');
    }

    if (steps.length > maxSteps) {
      buffer.writeln('  ... and ${steps.length - maxSteps} more steps');
    }

    return buffer.toString();
  }

  String _formatStep(PlanStep step, ActionRegistry? actions) {
    return switch (step) {
      InteractionStep(:final interaction) => switch (interaction) {
        SwitchActivity(:final actionId) => () {
          final action = actions?.byId(actionId);
          final actionName = action?.name ?? actionId.toString();
          final skillName = action?.skill.name.toLowerCase() ?? '';
          return skillName.isNotEmpty
              ? 'Switch to $actionName ($skillName)'
              : 'Switch to $actionName';
        }(),
        BuyShopItem(:final purchaseId) => 'Buy upgrade: $purchaseId',
        SellItems(:final policy) => 'Sell items ($policy)',
      },
      WaitStep(:final deltaTicks, :final waitFor) =>
        'Wait ${_formatDuration(durationFromTicks(deltaTicks))} '
            '-> ${waitFor.shortDescription}',
      MacroStep(:final macro, :final deltaTicks, :final waitFor) =>
        'Macro: ${_formatMacro(macro)} '
            '(${_formatDuration(durationFromTicks(deltaTicks))}) '
            '-> ${waitFor.shortDescription}',
    };
  }

  String _formatMacro(MacroCandidate macro) {
    return switch (macro) {
      TrainSkillUntil(:final skill) => 'Train ${skill.name}',
      TrainConsumingSkillUntil(:final consumingSkill) =>
        'Train ${consumingSkill.name}',
    };
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final hours = d.inHours;
      final minutes = d.inMinutes.remainder(60);
      return '${hours}h ${minutes}m';
    } else if (d.inMinutes > 0) {
      final minutes = d.inMinutes;
      final seconds = d.inSeconds.remainder(60);
      return '${minutes}m ${seconds}s';
    } else {
      return '${d.inSeconds}s';
    }
  }
}

/// Failure result when the solver cannot find a solution.
@immutable
class SolverFailure {
  const SolverFailure({
    required this.reason,
    this.expandedNodes = 0,
    this.enqueuedNodes = 0,
    this.bestCredits,
  });

  /// Human-readable reason for failure.
  final String reason;

  /// Number of nodes expanded before failure.
  final int expandedNodes;

  /// Number of nodes enqueued before failure.
  final int enqueuedNodes;

  /// Best credits achieved during search (if any).
  final int? bestCredits;

  @override
  String toString() =>
      'SolverFailure($reason, expanded=$expandedNodes, '
      'enqueued=$enqueuedNodes, bestCredits=$bestCredits)';
}

/// Result of the solver - either a plan or a failure.
sealed class SolverResult {
  const SolverResult();
}

// Forward declaration - SolverProfile is defined in solver.dart
// We use dynamic here to avoid circular imports; callers should cast.
class SolverSuccess extends SolverResult {
  const SolverSuccess(this.plan, [this.profile]);

  final Plan plan;
  final SolverProfile? profile;
}

class SolverFailed extends SolverResult {
  const SolverFailed(this.failure, [this.profile]);

  final SolverFailure failure;
  final SolverProfile? profile;
}

/// Result of executing a plan via [executePlan()].
@immutable
class PlanExecutionResult {
  const PlanExecutionResult({
    required this.finalState,
    required this.totalDeaths,
    required this.actualTicks,
    required this.plannedTicks,
  });

  /// The final game state after executing the plan.
  final GlobalState finalState;

  /// Total number of deaths that occurred during plan execution.
  /// Deaths are automatically handled by restarting the activity.
  final int totalDeaths;

  /// Actual ticks elapsed during execution.
  final int actualTicks;

  /// Planned ticks from the solver (for comparison).
  final int plannedTicks;

  /// Difference between actual and planned ticks.
  int get ticksDelta => actualTicks - plannedTicks;
}
