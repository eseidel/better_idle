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
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'interaction.dart';

// ---------------------------------------------------------------------------
// Wait Conditions
// ---------------------------------------------------------------------------

/// A condition that a [WaitStep] waits for during plan execution.
///
/// During planning, the solver uses expected-value modeling which may differ
/// from actual simulation due to randomness. WaitConditions allow plan
/// execution to continue until the condition is actually met, rather than
/// stopping after a fixed number of ticks.
sealed class WaitCondition {
  const WaitCondition();

  /// Returns true if this condition is satisfied in the given state.
  bool isSatisfied(GlobalState state);

  /// Human-readable description of what we're waiting for.
  String describe();
}

/// Wait until effective value (GP + inventory sell value) reaches a target.
@immutable
class WaitForInventoryValue extends WaitCondition {
  const WaitForInventoryValue(this.targetValue);

  final int targetValue;

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
  bool operator ==(Object other) =>
      other is WaitForInventoryValue && other.targetValue == targetValue;

  @override
  int get hashCode => targetValue.hashCode;
}

/// Wait until a skill reaches a target XP amount.
@immutable
class WaitForSkillXp extends WaitCondition {
  const WaitForSkillXp(this.skill, this.targetXp);

  final Skill skill;
  final int targetXp;

  @override
  bool isSatisfied(GlobalState state) {
    return state.skillState(skill).xp >= targetXp;
  }

  @override
  String describe() => '${skill.name} XP >= $targetXp';

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
class WaitForMasteryXp extends WaitCondition {
  const WaitForMasteryXp(this.actionName, this.targetMasteryXp);

  final String actionName;
  final int targetMasteryXp;

  @override
  bool isSatisfied(GlobalState state) {
    return state.actionState(actionName).masteryXp >= targetMasteryXp;
  }

  @override
  String describe() => '$actionName mastery XP >= $targetMasteryXp';

  @override
  bool operator ==(Object other) =>
      other is WaitForMasteryXp &&
      other.actionName == actionName &&
      other.targetMasteryXp == targetMasteryXp;

  @override
  int get hashCode => Object.hash(actionName, targetMasteryXp);
}

/// Wait until inventory usage reaches a threshold fraction.
@immutable
class WaitForInventoryThreshold extends WaitCondition {
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
  bool operator ==(Object other) =>
      other is WaitForInventoryThreshold && other.threshold == threshold;

  @override
  int get hashCode => threshold.hashCode;
}

/// Wait until inventory is completely full.
@immutable
class WaitForInventoryFull extends WaitCondition {
  const WaitForInventoryFull();

  @override
  bool isSatisfied(GlobalState state) {
    return state.inventoryRemaining <= 0;
  }

  @override
  String describe() => 'inventory full';

  @override
  bool operator ==(Object other) => other is WaitForInventoryFull;

  @override
  int get hashCode => 0;
}

/// Wait until player dies (HP reaches 0).
/// After death, the activity stops and HP resets.
@immutable
class WaitForDeath extends WaitCondition {
  const WaitForDeath();

  @override
  bool isSatisfied(GlobalState state) {
    // Death resets HP and stops activity - check if activity stopped
    // or HP is at max (reset after death).
    // In practice, we detect death by the activity being null after thieving.
    return state.activeAction == null;
  }

  @override
  String describe() => 'death';

  @override
  bool operator ==(Object other) => other is WaitForDeath;

  @override
  int get hashCode => 1;
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

/// Reason why a wait step ended.
enum WaitReason {
  /// Goal GP was reached.
  goalReached,

  /// An upgrade became affordable.
  upgradeAffordable,

  /// A locked activity unlocked.
  activityUnlocks,

  /// Inventory reached threshold for selling.
  inventoryThreshold,

  /// Inventory became full.
  inventoryFull,

  /// Player died (thieving).
  death,

  /// Skill level increased.
  skillLevel,

  /// Mastery level increased.
  masteryLevel,

  /// Unknown or unspecified reason.
  unknown,
}

/// A step that waits for a condition to be met.
///
/// During planning, [deltaTicks] is the expected time to wait based on
/// expected-value modeling. During execution, [condition] is used to
/// determine when to stop waiting, which handles variance in actual
/// simulation vs expected values.
@immutable
class WaitStep extends PlanStep {
  const WaitStep(
    this.deltaTicks, {
    this.reason = WaitReason.unknown,
    this.condition,
  });

  /// Expected ticks to wait (from planning).
  final int deltaTicks;

  /// Why this wait ended (what event triggered re-evaluation).
  final WaitReason reason;

  /// The condition to wait for during execution.
  /// If null, falls back to time-based waiting using [deltaTicks].
  final WaitCondition? condition;

  @override
  String toString() {
    final condStr = condition != null ? ', ${condition!.describe()}' : '';
    return 'WaitStep($deltaTicks ticks, $reason$condStr)';
  }

  @override
  bool operator ==(Object other) =>
      other is WaitStep &&
      other.deltaTicks == deltaTicks &&
      other.reason == reason &&
      other.condition == condition;

  @override
  int get hashCode => Object.hash(deltaTicks, reason, condition);
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
  });

  /// An empty plan (goal already satisfied).
  const Plan.empty()
    : steps = const [],
      totalTicks = 0,
      interactionCount = 0,
      expandedNodes = 0,
      enqueuedNodes = 0;

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
      WaitStep(:final deltaTicks, :final reason) =>
        'Wait ${_formatDuration(durationFromTicks(deltaTicks))} -> ${_formatWaitReason(reason)}',
    };
  }

  String _formatWaitReason(WaitReason reason) {
    return switch (reason) {
      WaitReason.goalReached => 'Goal reached',
      WaitReason.upgradeAffordable => 'Upgrade affordable',
      WaitReason.activityUnlocks => 'Activity unlocks',
      WaitReason.inventoryThreshold => 'Inventory threshold',
      WaitReason.inventoryFull => 'Inventory full',
      WaitReason.death => 'Death',
      WaitReason.skillLevel => 'Skill +1',
      WaitReason.masteryLevel => 'Mastery +1',
      WaitReason.unknown => '?',
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
