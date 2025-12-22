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

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'goal.dart';
import 'interaction.dart';

// ---------------------------------------------------------------------------
// Wait For (what we're waiting for)
// ---------------------------------------------------------------------------

/// Describes what a [WaitStep] is waiting for.
///
/// During planning, the solver uses expected-value modeling which may differ
/// from actual simulation due to randomness. WaitFor types allow plan
/// execution to continue until the condition is actually met, rather than
/// stopping after a fixed number of ticks.
///
/// Each WaitFor type has:
/// - [isSatisfied] - check if condition is met (for execution)
/// - [describe] - human-readable description with values
/// - [shortDescription] - brief label for plan display (e.g., "Skill +1")
sealed class WaitFor {
  const WaitFor();

  /// Returns true if this wait condition is satisfied in the given state.
  bool isSatisfied(GlobalState state);

  /// Human-readable description of what we're waiting for (with values).
  String describe();

  /// Short description for plan display (e.g., "Skill +1", "Upgrade affordable").
  String get shortDescription;
}

/// Wait until effective value (GP + inventory sell value) reaches a target.
/// Used for: upgrade becomes affordable, GP goal reached.
@immutable
class WaitForInventoryValue extends WaitFor {
  const WaitForInventoryValue(this.targetValue, {this.reason = 'Upgrade'});

  final int targetValue;

  /// Why we're waiting for this value (for display).
  final String reason;

  @override
  bool isSatisfied(GlobalState state) {
    var total = state.gp;
    for (final stack in state.inventory.items) {
      total += stack.sellsFor;
    }
    return total >= targetValue;
  }

  @override
  String describe() => 'value >= $targetValue';

  @override
  String get shortDescription => '$reason affordable';

  @override
  bool operator ==(Object other) =>
      other is WaitForInventoryValue && other.targetValue == targetValue;

  @override
  int get hashCode => targetValue.hashCode;
}

/// Wait until a skill reaches a target XP amount.
/// Used for: skill level up, activity unlock, goal reached.
@immutable
class WaitForSkillXp extends WaitFor {
  const WaitForSkillXp(this.skill, this.targetXp, {this.reason});

  final Skill skill;
  final int targetXp;

  /// Optional reason (e.g., 'Oak Tree unlocks'). If null, shows 'Skill +1'.
  final String? reason;

  @override
  bool isSatisfied(GlobalState state) {
    return state.skillState(skill).xp >= targetXp;
  }

  @override
  String describe() => '${skill.name} XP >= $targetXp';

  @override
  String get shortDescription => reason ?? 'Skill +1';

  @override
  bool operator ==(Object other) =>
      other is WaitForSkillXp &&
      other.skill == skill &&
      other.targetXp == targetXp;

  @override
  int get hashCode => Object.hash(skill, targetXp);
}

/// Wait until mastery for an action reaches a target XP amount.
@immutable
class WaitForMasteryXp extends WaitFor {
  const WaitForMasteryXp(this.actionId, this.targetMasteryXp);

  final MelvorId actionId;
  final int targetMasteryXp;

  @override
  bool isSatisfied(GlobalState state) {
    return state.actionState(actionId).masteryXp >= targetMasteryXp;
  }

  @override
  String describe() => '${actionId.name} mastery XP >= $targetMasteryXp';

  @override
  String get shortDescription => 'Mastery +1';

  @override
  bool operator ==(Object other) =>
      other is WaitForMasteryXp &&
      other.actionId == actionId &&
      other.targetMasteryXp == targetMasteryXp;

  @override
  int get hashCode => Object.hash(actionId, targetMasteryXp);
}

/// Wait until inventory usage reaches a threshold fraction.
@immutable
class WaitForInventoryThreshold extends WaitFor {
  const WaitForInventoryThreshold(this.threshold);

  /// Fraction of inventory capacity (0.0 to 1.0).
  final double threshold;

  @override
  bool isSatisfied(GlobalState state) {
    if (state.inventoryCapacity <= 0) return false;
    final usedFraction = state.inventoryUsed / state.inventoryCapacity;
    return usedFraction >= threshold;
  }

  @override
  String describe() => 'inventory >= ${(threshold * 100).toInt()}%';

  @override
  String get shortDescription => 'Inventory threshold';

  @override
  bool operator ==(Object other) =>
      other is WaitForInventoryThreshold && other.threshold == threshold;

  @override
  int get hashCode => threshold.hashCode;
}

/// Wait until inventory is completely full.
@immutable
class WaitForInventoryFull extends WaitFor {
  const WaitForInventoryFull();

  @override
  bool isSatisfied(GlobalState state) {
    return state.inventoryRemaining <= 0;
  }

  @override
  String describe() => 'inventory full';

  @override
  String get shortDescription => 'Inventory full';

  @override
  bool operator ==(Object other) => other is WaitForInventoryFull;

  @override
  int get hashCode => 0;
}

/// Wait until goal is reached. This is a terminal wait.
@immutable
class WaitForGoal extends WaitFor {
  const WaitForGoal(this.goal);

  final Goal goal;

  @override
  bool isSatisfied(GlobalState state) => goal.isSatisfied(state);

  @override
  String describe() => goal.describe();

  @override
  String get shortDescription => 'Goal reached';

  @override
  bool operator ==(Object other) => other is WaitForGoal && other.goal == goal;

  @override
  int get hashCode => goal.hashCode;
}

// ---------------------------------------------------------------------------
// Plan Steps
// ---------------------------------------------------------------------------

/// A single step in a plan.
sealed class PlanStep {
  const PlanStep();
}

/// A step that performs an interaction (switch activity, buy upgrade, sell).
@immutable
class InteractionStep extends PlanStep {
  const InteractionStep(this.interaction);

  final Interaction interaction;

  @override
  String toString() => 'InteractionStep($interaction)';

  @override
  bool operator ==(Object other) =>
      other is InteractionStep && other.interaction == interaction;

  @override
  int get hashCode => interaction.hashCode;
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
  String toString() => 'WaitStep($deltaTicks ticks, ${waitFor.describe()})';

  @override
  bool operator ==(Object other) =>
      other is WaitStep &&
      other.deltaTicks == deltaTicks &&
      other.waitFor == waitFor;

  @override
  int get hashCode => Object.hash(deltaTicks, waitFor);
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

  /// Pretty-prints the plan for debugging.
  String prettyPrint({int maxSteps = 30}) {
    final buffer = StringBuffer();
    buffer.writeln('=== Plan ===');
    buffer.writeln(
      'Total ticks: $totalTicks (${_formatDuration(totalDuration)})',
    );
    buffer.writeln('Interactions: $interactionCount');
    buffer.writeln('Expanded nodes: $expandedNodes');
    buffer.writeln('Enqueued nodes: $enqueuedNodes');
    buffer.writeln('Steps (${steps.length} total):');

    final stepsToShow = steps.take(maxSteps).toList();
    for (var i = 0; i < stepsToShow.length; i++) {
      final step = stepsToShow[i];
      buffer.writeln('  ${i + 1}. ${_formatStep(step)}');
    }

    if (steps.length > maxSteps) {
      buffer.writeln('  ... and ${steps.length - maxSteps} more steps');
    }

    return buffer.toString();
  }

  String _formatStep(PlanStep step) {
    return switch (step) {
      InteractionStep(:final interaction) => switch (interaction) {
        SwitchActivity(:final actionName) => 'Switch to $actionName',
        BuyUpgrade(:final type) => 'Buy upgrade: $type',
        SellAll() => 'Sell all items',
      },
      WaitStep(:final deltaTicks, :final waitFor) =>
        'Wait ${_formatDuration(durationFromTicks(deltaTicks))} -> ${waitFor.shortDescription}',
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
      'SolverFailure($reason, expanded=$expandedNodes, enqueued=$enqueuedNodes, bestCredits=$bestCredits)';
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
  final dynamic profile;
}

class SolverFailed extends SolverResult {
  const SolverFailed(this.failure, [this.profile]);

  final SolverFailure failure;
  final dynamic profile;
}

/// Result of executing a plan via [executePlan].
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
