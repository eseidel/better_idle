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

import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/solver/replan_boundary.dart';
import 'package:logic/src/solver/solver_profile.dart';
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
///
/// [expectedAction] is the action that should be running during the wait.
/// If provided, execution will switch to this action before waiting. This
/// ensures the wait makes progress on the right skill/action.
@immutable
class WaitStep extends PlanStep {
  const WaitStep(this.deltaTicks, this.waitFor, {this.expectedAction});

  /// Expected ticks to wait (from planning).
  final int deltaTicks;

  /// What we're waiting for.
  final WaitFor waitFor;

  /// The action that should be running during this wait.
  ///
  /// If null, the current action continues (or no action if idle).
  /// If non-null, execution will switch to this action before waiting.
  final ActionId? expectedAction;

  @override
  List<Object?> get props => [deltaTicks, waitFor, expectedAction];

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
      return 'MacroStep(${m.skill.name} for $deltaTicks ticks, '
          '${waitFor.describe()})';
    }
    return 'MacroStep($macro, $deltaTicks ticks, ${waitFor.describe()})';
  }
}

// ---------------------------------------------------------------------------
// Segment Boundaries
// ---------------------------------------------------------------------------

/// What boundary type triggered a segment to end.
///
/// This is planning-time info (what we expect), not execution-time
/// (what happened). Used to categorize segment stopping points.
sealed class SegmentBoundary {
  const SegmentBoundary();

  /// Human-readable description of this boundary.
  String describe();
}

/// Goal was reached - plan succeeded.
@immutable
class GoalReachedBoundary extends SegmentBoundary {
  const GoalReachedBoundary();

  @override
  String describe() => 'Goal reached';
}

/// An upgrade became affordable.
@immutable
class UpgradeAffordableBoundary extends SegmentBoundary {
  const UpgradeAffordableBoundary(this.purchaseId, this.upgradeName);

  /// The upgrade that became affordable.
  final MelvorId purchaseId;

  /// Human-readable name of the upgrade.
  final String upgradeName;

  @override
  String describe() => 'Upgrade $upgradeName affordable';
}

/// A skill level crossed an unlock boundary.
@immutable
class UnlockBoundary extends SegmentBoundary {
  const UnlockBoundary(this.skill, this.level, this.unlocks);

  /// The skill that leveled up.
  final Skill skill;

  /// The level that was reached.
  final int level;

  /// What gets unlocked at this level (human-readable).
  final String unlocks;

  @override
  String describe() => '${skill.name} L$level unlocks $unlocks';
}

/// Inputs were depleted for a consuming action.
@immutable
class InputsDepletedBoundary extends SegmentBoundary {
  const InputsDepletedBoundary(this.actionId);

  /// The action that ran out of inputs.
  final ActionId actionId;

  @override
  String describe() => 'Inputs depleted for ${actionId.localId.name}';
}

/// Segment reached the maximum tick horizon.
@immutable
class HorizonCapBoundary extends SegmentBoundary {
  const HorizonCapBoundary(this.ticksElapsed);

  /// How many ticks elapsed before hitting the cap.
  final int ticksElapsed;

  @override
  String describe() => 'Horizon cap reached ($ticksElapsed ticks)';
}

/// Inventory usage exceeded the pressure threshold.
@immutable
class InventoryPressureBoundary extends SegmentBoundary {
  const InventoryPressureBoundary(this.usedSlots, this.totalSlots);

  /// Number of inventory slots in use.
  final int usedSlots;

  /// Total inventory capacity.
  final int totalSlots;

  @override
  String describe() => 'Inventory pressure ($usedSlots/$totalSlots slots)';
}

// ---------------------------------------------------------------------------
// Segments
// ---------------------------------------------------------------------------

/// A portion of a plan between material boundaries.
///
/// Segments represent the natural stopping points where replanning should
/// occur. Each segment ends at a material boundary (upgrade affordable,
/// unlock reached, inputs depleted, or goal reached).
@immutable
class Segment {
  const Segment({
    required this.steps,
    required this.totalTicks,
    required this.interactionCount,
    required this.stopBoundary,
    this.description,
  });

  /// The sequence of steps in this segment.
  final List<PlanStep> steps;

  /// Total ticks for this segment.
  final int totalTicks;

  /// Number of interactions in this segment.
  final int interactionCount;

  /// What boundary this segment stops at.
  final SegmentBoundary stopBoundary;

  /// Human-readable description for rendering.
  /// E.g., "WC→FM loop until Teak unlocked"
  final String? description;
}

/// Marks where a segment starts within a Plan.
@immutable
class SegmentMarker {
  const SegmentMarker({
    required this.stepIndex,
    required this.boundary,
    this.description,
  });

  /// Index in Plan.steps where this segment starts.
  final int stepIndex;

  /// What boundary this segment stops at.
  final SegmentBoundary boundary;

  /// Optional human-readable description.
  final String? description;
}

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

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
    this.segmentMarkers = const <SegmentMarker>[],
  });

  /// An empty plan (goal already satisfied).
  const Plan.empty()
    : steps = const [],
      totalTicks = 0,
      interactionCount = 0,
      expandedNodes = 0,
      enqueuedNodes = 0,
      expectedDeaths = 0,
      segmentMarkers = const <SegmentMarker>[];

  /// Constructs a Plan from multiple segments.
  ///
  /// Stitches segments together into a single plan with segment markers
  /// for rendering purposes.
  factory Plan.fromSegments(
    List<Segment> segments, {
    int expandedNodes = 0,
    int enqueuedNodes = 0,
  }) {
    final allSteps = <PlanStep>[];
    final markers = <SegmentMarker>[];
    var totalTicks = 0;
    var interactionCount = 0;

    for (final segment in segments) {
      markers.add(
        SegmentMarker(
          stepIndex: allSteps.length,
          boundary: segment.stopBoundary,
          description: segment.description,
        ),
      );
      allSteps.addAll(segment.steps);
      totalTicks += segment.totalTicks;
      interactionCount += segment.interactionCount;
    }

    return Plan(
      steps: allSteps,
      totalTicks: totalTicks,
      interactionCount: interactionCount,
      segmentMarkers: markers,
      expandedNodes: expandedNodes,
      enqueuedNodes: enqueuedNodes,
    );
  }

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

  /// Segment boundaries within this plan.
  /// Used for rendering cycles like "Cycle 3: WC→FM loop until Teak unlocked".
  final List<SegmentMarker> segmentMarkers;

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

        case WaitStep(:final deltaTicks, :final waitFor, :final expectedAction):
          // Check if we can merge with the previous step
          if (compressed.isNotEmpty && compressed.last is WaitStep) {
            // Check if there's no meaningful interaction between these waits
            // A meaningful interaction is anything except the wait itself
            // Since we're iterating in order, if the last compressed step
            // is a WaitStep, we can try to merge.
            final lastWait = compressed.last as WaitStep;

            // Merge consecutive waits - keep the final waitFor since that's
            // what we're ultimately waiting for, but preserve expectedAction
            // from the first wait (that's the action that should be running)
            compressed[compressed.length - 1] = WaitStep(
              lastWait.deltaTicks + deltaTicks,
              waitFor, // Use the later wait's condition
              expectedAction: lastWait.expectedAction ?? expectedAction,
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
    ActionId? currentAction;
    for (var i = 0; i < stepsToShow.length; i++) {
      final step = stepsToShow[i];
      final formatted = _formatStep(step, actions, currentAction);
      buffer.writeln('  ${i + 1}. $formatted');
      // Track current action for context in wait steps
      if (step case InteractionStep(:final interaction)) {
        if (interaction case SwitchActivity(:final actionId)) {
          currentAction = actionId;
        }
      } else if (step case MacroStep(:final macro)) {
        // Macros may set an action
        if (macro case TrainSkillUntil(:final actionId)) {
          currentAction = actionId;
        }
      }
    }

    if (steps.length > maxSteps) {
      buffer.writeln('  ... and ${steps.length - maxSteps} more steps');
    }

    return buffer.toString();
  }

  String _formatStep(
    PlanStep step,
    ActionRegistry? actions,
    ActionId? currentAction,
  ) {
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
        BuyShopItem(:final purchaseId) => 'Buy ${purchaseId.name}',
        SellItems(:final policy) => _formatSellPolicy(policy),
      },
      WaitStep(:final deltaTicks, :final waitFor, :final expectedAction) => () {
        final duration = _formatDuration(durationFromTicks(deltaTicks));
        // Use expectedAction if available, otherwise fall back to currentAction
        final actionToUse = expectedAction ?? currentAction;
        final actionName = actionToUse != null
            ? actions?.byId(actionToUse).name ?? actionToUse.toString()
            : null;
        final prefix = actionName != null ? '$actionName ' : 'Wait ';
        return '$prefix$duration -> ${waitFor.shortDescription}';
      }(),
      MacroStep(:final macro, :final deltaTicks, :final waitFor) =>
        'Macro: ${_formatMacro(macro)} '
            '(${_formatDuration(durationFromTicks(deltaTicks))}) '
            '-> ${waitFor.shortDescription}',
    };
  }

  String _formatMacro(MacroCandidate macro) {
    return switch (macro) {
      TrainSkillUntil(:final skill) => skill.name,
      TrainConsumingSkillUntil(:final consumingSkill) => consumingSkill.name,
      AcquireItem(:final itemId, :final quantity) =>
        'Acquire ${quantity}x ${itemId.name}',
      EnsureStock(:final itemId, :final minTotal) =>
        'EnsureStock ${itemId.name}: $minTotal',
    };
  }

  String _formatSellPolicy(SellPolicy policy) {
    return switch (policy) {
      SellAllPolicy() => 'Sell all',
      SellExceptPolicy(:final keepItems) => () {
        final names = keepItems.map((id) => id.name).toList()..sort();
        if (names.length <= 3) {
          return 'Sell all except ${names.join(', ')}';
        }
        return 'Sell all except ${names.length} items '
            '(${names.take(3).join(', ')}, ...)';
      }(),
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

// ---------------------------------------------------------------------------
// Repro Bundle for debugging failures
// ---------------------------------------------------------------------------

/// A bundle of state and goal for reproducing solver failures.
///
/// When the solver fails or hits an unexpected boundary, this bundle captures
/// enough information to reproduce the issue for debugging.
@immutable
class ReproBundle {
  const ReproBundle({
    required this.state,
    required this.goal,
    this.reason,
    this.boundary,
    this.plan,
    this.stepIndex,
  });

  /// Creates a ReproBundle from a JSON map.
  ///
  /// Requires [registries] to deserialize the GlobalState.
  /// Note: [boundary] and [plan] are not deserialized (they are stored
  /// as human-readable strings for debugging, not for reconstruction).
  factory ReproBundle.fromJson(
    Map<String, dynamic> json,
    Registries registries,
  ) {
    return ReproBundle(
      state: GlobalState.fromJson(
        registries,
        json['state'] as Map<String, dynamic>,
      ),
      goal: _goalFromJson(json['goal'] as Map<String, dynamic>),
      reason: json['reason'] as String?,
      // boundary and plan are not deserialized - they're debug info only
    );
  }

  /// Creates a ReproBundle from a JSON string.
  factory ReproBundle.fromJsonString(String jsonString, Registries registries) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return ReproBundle.fromJson(json, registries);
  }

  /// The game state at the point of failure/boundary.
  final GlobalState state;

  /// The goal the solver was trying to achieve.
  final Goal goal;

  /// Human-readable reason for the failure (if from solver failure).
  final String? reason;

  /// The boundary that was hit (if from unexpected boundary).
  final ReplanBoundary? boundary;

  /// The plan being executed (if from execution failure).
  final Plan? plan;

  /// The step index where the boundary was hit (if from execution failure).
  final int? stepIndex;

  /// Converts the bundle to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'state': state.toJson(),
    'goal': _goalToJson(goal),
    if (reason != null) 'reason': reason,
    if (boundary != null) 'boundary': boundary!.describe(),
    if (plan != null) 'plan': _planToJson(plan!),
    if (stepIndex != null) 'stepIndex': stepIndex,
  };

  /// Converts the bundle to a JSON string.
  String toJsonString({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  static Goal _goalFromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'ReachGpGoal' => ReachGpGoal(json['targetGp'] as int),
      'ReachSkillLevelGoal' => ReachSkillLevelGoal(
        Skill.fromName(json['skill'] as String),
        json['targetLevel'] as int,
      ),
      'MultiSkillGoal' => MultiSkillGoal(
        (json['subgoals'] as List<dynamic>)
            .map((e) => _goalFromJson(e as Map<String, dynamic>))
            .cast<ReachSkillLevelGoal>()
            .toList(),
      ),
      'SegmentGoal' => throw ArgumentError(
        'SegmentGoal cannot be deserialized directly',
      ),
      _ => throw ArgumentError('Unknown goal type: $type'),
    };
  }

  static Map<String, dynamic> _goalToJson(Goal goal) {
    return switch (goal) {
      ReachGpGoal(:final targetGp) => {
        'type': 'ReachGpGoal',
        'targetGp': targetGp,
      },
      ReachSkillLevelGoal(:final skill, :final targetLevel) => {
        'type': 'ReachSkillLevelGoal',
        'skill': skill.name,
        'targetLevel': targetLevel,
      },
      MultiSkillGoal(:final subgoals) => {
        'type': 'MultiSkillGoal',
        'subgoals': subgoals.map(_goalToJson).toList(),
      },
      SegmentGoal(:final innerGoal) => {
        'type': 'SegmentGoal',
        'innerGoal': _goalToJson(innerGoal),
      },
    };
  }

  static Map<String, dynamic> _planToJson(Plan plan) {
    return {
      'totalTicks': plan.totalTicks,
      'stepCount': plan.steps.length,
      'steps': plan.steps.map(_stepToJson).toList(),
    };
  }

  static Map<String, dynamic> _stepToJson(PlanStep step) {
    return switch (step) {
      InteractionStep(:final interaction) => {
        'type': 'InteractionStep',
        'interaction': interaction.toString(),
      },
      WaitStep(:final deltaTicks, :final waitFor, :final expectedAction) => {
        'type': 'WaitStep',
        'deltaTicks': deltaTicks,
        'waitFor': waitFor.describe(),
        if (expectedAction != null) 'expectedAction': expectedAction.toString(),
      },
      MacroStep(:final macro, :final deltaTicks, :final waitFor) => {
        'type': 'MacroStep',
        'macro': _macroToJson(macro),
        'deltaTicks': deltaTicks,
        'waitFor': waitFor.describe(),
      },
    };
  }

  static Map<String, dynamic> _macroToJson(MacroCandidate macro) {
    return switch (macro) {
      TrainSkillUntil(:final skill, :final primaryStop, :final actionId) => {
        'type': 'TrainSkillUntil',
        'skill': skill.name,
        'primaryStop': primaryStop.toString(),
        if (actionId != null) 'actionId': actionId.toString(),
      },
      TrainConsumingSkillUntil(:final consumingSkill, :final primaryStop) => {
        'type': 'TrainConsumingSkillUntil',
        'consumingSkill': consumingSkill.name,
        'primaryStop': primaryStop.toString(),
      },
      AcquireItem(:final itemId, :final quantity) => {
        'type': 'AcquireItem',
        'itemId': itemId.toString(),
        'quantity': quantity,
      },
      EnsureStock(:final itemId, :final minTotal) => {
        'type': 'EnsureStock',
        'itemId': itemId.toString(),
        'minTotal': minTotal,
      },
    };
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
    this.reproBundle,
  });

  /// Human-readable reason for failure.
  final String reason;

  /// Number of nodes expanded before failure.
  final int expandedNodes;

  /// Number of nodes enqueued before failure.
  final int enqueuedNodes;

  /// Best credits achieved during search (if any).
  final int? bestCredits;

  /// Optional repro bundle for debugging.
  final ReproBundle? reproBundle;

  @override
  String toString() =>
      'SolverFailure($reason, expanded=$expandedNodes, '
      'enqueued=$enqueuedNodes, bestCredits=$bestCredits)';
}

/// Result of the solver - either a plan or a failure.
sealed class SolverResult {
  const SolverResult([this.profile]);

  final SolverProfile? profile;
}

class SolverSuccess extends SolverResult {
  const SolverSuccess(this.plan, this.terminalState, [super.profile]);

  final Plan plan;

  /// The terminal node's state from the search.
  ///
  /// This is the state at the end of the plan, derived directly from the
  /// A* search rather than replaying the plan. Used by solveSegment() to
  /// derive segment boundaries without plan replay.
  final GlobalState terminalState;
}

class SolverFailed extends SolverResult {
  const SolverFailed(this.failure, [super.profile]);

  final SolverFailure failure;
}

/// Result of executing a plan via [executePlan()].
@immutable
class PlanExecutionResult {
  const PlanExecutionResult({
    required this.finalState,
    required this.totalDeaths,
    required this.actualTicks,
    required this.plannedTicks,
    this.boundariesHit = const [],
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

  /// All replan boundaries encountered during execution.
  ///
  /// Expected boundaries (like [InputsDepleted], [WaitConditionSatisfied])
  /// are normal in online execution. Unexpected boundaries may indicate bugs.
  ///
  /// This list is useful for:
  /// - Debugging execution flow
  /// - Deciding when to replan
  /// - Detecting potential solver bugs
  final List<ReplanBoundary> boundariesHit;

  /// Difference between actual and planned ticks.
  int get ticksDelta => actualTicks - plannedTicks;

  /// Whether any unexpected boundaries were hit during execution.
  bool get hasUnexpectedBoundaries => boundariesHit.any((b) => !b.isExpected);

  /// Returns only unexpected boundaries (potential bugs).
  List<ReplanBoundary> get unexpectedBoundaries =>
      boundariesHit.where((b) => !b.isExpected).toList();

  /// Returns only expected boundaries (normal flow).
  List<ReplanBoundary> get expectedBoundaries =>
      boundariesHit.where((b) => b.isExpected).toList();

  /// Creates a repro bundle for debugging unexpected boundaries.
  ///
  /// Returns null if there are no unexpected boundaries.
  /// The [goal] and [plan] parameters are needed since they're not stored
  /// in the execution result.
  ReproBundle? createReproBundleForUnexpected({
    required Goal goal,
    required Plan plan,
  }) {
    if (!hasUnexpectedBoundaries) return null;
    final firstUnexpected = unexpectedBoundaries.first;
    return ReproBundle(
      state: finalState,
      goal: goal,
      boundary: firstUnexpected,
      plan: plan,
    );
  }
}
