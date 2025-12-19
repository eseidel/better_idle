import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'interaction.dart';

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

/// A step that waits for a specified number of ticks.
@immutable
class WaitStep extends PlanStep {
  const WaitStep(this.deltaTicks);

  final int deltaTicks;

  @override
  String toString() => 'WaitStep($deltaTicks ticks)';

  @override
  bool operator ==(Object other) =>
      other is WaitStep && other.deltaTicks == deltaTicks;

  @override
  int get hashCode => deltaTicks.hashCode;
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
      WaitStep(:final deltaTicks) =>
        'Wait $deltaTicks ticks (${_formatDuration(durationFromTicks(deltaTicks))})',
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
