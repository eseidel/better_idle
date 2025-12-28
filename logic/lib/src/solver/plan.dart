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
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/estimate_rates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/solver/next_decision_delta.dart' show infTicks;
import 'package:logic/src/solver/solver.dart';
import 'package:logic/src/solver/value_model.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Calculates the total value of a state (GP + sellable inventory value).
int _effectiveCredits(GlobalState state) {
  var total = state.gp;
  for (final stack in state.inventory.items) {
    total += stack.sellsFor;
  }
  return total;
}

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
sealed class WaitFor extends Equatable {
  const WaitFor();

  /// Returns true if this wait condition is satisfied in the given state.
  bool isSatisfied(GlobalState state);

  /// Estimates ticks to satisfy this condition given current rates.
  ///
  /// Returns [infTicks] if the condition cannot be reached with current rates.
  /// Returns 0 if the condition is already satisfied.
  int estimateTicks(GlobalState state, Rates rates);

  /// Human-readable description of what we're waiting for (with values).
  String describe();

  /// Short description for plan (e.g., "Skill +1", "Upgrade affordable").
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
    return _effectiveCredits(state) >= targetValue;
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentValue = _effectiveCredits(state);
    final needed = targetValue - currentValue;
    if (needed <= 0) return 0;

    final valueRate = defaultValueModel.valuePerTick(state, rates);
    if (valueRate <= 0) return infTicks;

    return (needed / valueRate).ceil();
  }

  @override
  String describe() => 'value >= $targetValue';

  @override
  String get shortDescription => '$reason affordable';

  @override
  List<Object?> get props => [targetValue];
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
  int estimateTicks(GlobalState state, Rates rates) {
    final currentXp = state.skillState(skill).xp;
    final needed = targetXp - currentXp;
    if (needed <= 0) return 0;

    final xpRate = rates.xpPerTickBySkill[skill] ?? 0.0;
    if (xpRate <= 0) return infTicks;

    return (needed / xpRate).ceil();
  }

  @override
  String describe() => '${skill.name} XP >= $targetXp';

  @override
  String get shortDescription => reason ?? 'Skill +1';

  @override
  List<Object?> get props => [skill, targetXp];
}

/// Wait until mastery for an action reaches a target XP amount.
@immutable
class WaitForMasteryXp extends WaitFor {
  const WaitForMasteryXp(this.actionId, this.targetMasteryXp);

  final ActionId actionId;
  final int targetMasteryXp;

  @override
  bool isSatisfied(GlobalState state) {
    return state.actionState(actionId).masteryXp >= targetMasteryXp;
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentXp = state.actionState(actionId).masteryXp;
    final needed = targetMasteryXp - currentXp;
    if (needed <= 0) return 0;

    final masteryRate = rates.masteryXpPerTick;
    if (masteryRate <= 0) return infTicks;

    return (needed / masteryRate).ceil();
  }

  @override
  String describe() {
    // This isn't the real name, but it's close enough for debugging.
    final actionName = actionId.localId.name;
    return '$actionName mastery XP >= $targetMasteryXp';
  }

  @override
  String get shortDescription => 'Mastery +1';

  @override
  List<Object?> get props => [actionId, targetMasteryXp];
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
  int estimateTicks(GlobalState state, Rates rates) {
    if (state.inventoryCapacity <= 0) return infTicks;
    final targetSlots = (threshold * state.inventoryCapacity).ceil();
    final neededSlots = targetSlots - state.inventoryUsed;
    if (neededSlots <= 0) return 0;

    final slotsPerTick = rates.itemTypesPerTick;
    if (slotsPerTick <= 0) return infTicks;

    return (neededSlots / slotsPerTick).ceil();
  }

  @override
  String describe() => 'inventory >= ${(threshold * 100).toInt()}%';

  @override
  String get shortDescription => 'Inventory threshold';

  @override
  List<Object?> get props => [threshold];
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
  int estimateTicks(GlobalState state, Rates rates) {
    final neededSlots = state.inventoryRemaining;
    if (neededSlots <= 0) return 0;

    final slotsPerTick = rates.itemTypesPerTick;
    if (slotsPerTick <= 0) return infTicks;

    return (neededSlots / slotsPerTick).ceil();
  }

  @override
  String describe() => 'inventory full';

  @override
  String get shortDescription => 'Inventory full';

  @override
  List<Object?> get props => [];
}

/// Wait until goal is reached. This is a terminal wait.
@immutable
class WaitForGoal extends WaitFor {
  const WaitForGoal(this.goal);

  final Goal goal;

  @override
  bool isSatisfied(GlobalState state) => goal.isSatisfied(state);

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final remaining = goal.remaining(state);
    if (remaining <= 0) return 0;

    final progressRate = goal.progressPerTick(state, rates);
    if (progressRate <= 0) return infTicks;

    return (remaining / progressRate).ceil();
  }

  @override
  String describe() => goal.describe();

  @override
  String get shortDescription => 'Goal reached';

  @override
  List<Object?> get props => [goal];
}

/// Wait until inputs for the current action are depleted.
/// Used for consuming actions (firemaking, cooking, etc.) to signal when
/// the solver should switch to a producer action.
@immutable
class WaitForInputsDepleted extends WaitFor {
  const WaitForInputsDepleted(this.actionId);

  final ActionId actionId;

  @override
  bool isSatisfied(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    // Inputs are depleted when we can no longer start the action
    return !state.canStartAction(action);
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final action = state.registries.actions.byId(actionId);
    if (action is! SkillAction) return infTicks;

    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    if (inputs.isEmpty) return infTicks; // Non-consuming action

    // Find minimum ticks based on available inputs
    var minInputTicks = infTicks;
    final actionDurationTicks = action.minDuration.inMilliseconds ~/ msPerTick;

    for (final entry in inputs.entries) {
      final item = state.registries.items.byId(entry.key);
      final available = state.inventory.countOfItem(item);
      final consumedPerAction = entry.value;
      final consumedPerTick =
          consumedPerAction / actionDurationTicks.toDouble();

      if (consumedPerTick > 0) {
        final ticksUntilDepleted = (available / consumedPerTick).floor();
        if (ticksUntilDepleted < minInputTicks) {
          minInputTicks = ticksUntilDepleted;
        }
      }
    }

    return minInputTicks;
  }

  @override
  String describe() => 'inputs depleted for ${actionId.localId.name}';

  @override
  String get shortDescription => 'Inputs depleted';

  @override
  List<Object?> get props => [actionId];
}

/// Wait until inputs for a consuming action become available.
/// Used when a producer action is gathering inputs for a consuming action.
@immutable
class WaitForInputsAvailable extends WaitFor {
  const WaitForInputsAvailable(this.actionId);

  final ActionId actionId;

  @override
  bool isSatisfied(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    // Inputs are available when we can start the action
    return state.canStartAction(action);
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    // If inputs are already available, no waiting needed
    if (isSatisfied(state)) return 0;

    // This is typically used when gathering inputs with a producer action.
    // The estimate depends on the production rate of the current action.
    // For now, return infTicks as a conservative fallback - the actual
    // estimation is usually done at a higher level when planning the
    // producer/consumer cycle.
    return infTicks;
  }

  @override
  String describe() => 'inputs available for ${actionId.localId.name}';

  @override
  String get shortDescription => 'Inputs available';

  @override
  List<Object?> get props => [actionId];
}

/// Wait until inventory has at least a certain count of an item.
/// Used during adaptive produce/consume cycles to gather enough inputs
/// before switching back to the consuming action.
@immutable
class WaitForInventoryAtLeast extends WaitFor {
  const WaitForInventoryAtLeast(this.itemId, this.minCount);

  final MelvorId itemId;
  final int minCount;

  @override
  bool isSatisfied(GlobalState state) {
    final count = state.inventory.items
        .where((s) => s.item.id == itemId)
        .map((s) => s.count)
        .fold(0, (a, b) => a + b);
    return count >= minCount;
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentCount = state.inventory.items
        .where((s) => s.item.id == itemId)
        .map((s) => s.count)
        .fold(0, (a, b) => a + b);
    final needed = minCount - currentCount;
    if (needed <= 0) return 0;

    final productionRate = rates.itemFlowsPerTick[itemId] ?? 0.0;
    if (productionRate <= 0) return infTicks;

    return (needed / productionRate).ceil();
  }

  @override
  String describe() => '${itemId.localId} count >= $minCount';

  @override
  String get shortDescription => 'Inventory at least $minCount';

  @override
  List<Object?> get props => [itemId, minCount];
}

/// Wait until we have enough inputs to complete the goal via a consuming
/// action. Used when a producer action needs to gather sufficient inputs before
/// switching to the consuming action to complete the skill goal.
@immutable
class WaitForSufficientInputs extends WaitFor {
  const WaitForSufficientInputs(this.actionId, this.targetCount);

  final ActionId actionId;
  final int targetCount;

  @override
  bool isSatisfied(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    if (action is! SkillAction) return false;

    // Get the inputs needed for this action
    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    // Check if we have enough of all inputs
    for (final entry in inputs.entries) {
      final item = state.registries.items.byId(entry.key);
      final available = state.inventory.countOfItem(item);
      // We need at least targetCount of the primary input
      // (for simplicity, check if we have enough to run targetCount actions)
      final neededPerAction = entry.value;
      if (available <
          targetCount * neededPerAction / inputs.length.toDouble()) {
        return false;
      }
    }
    return true;
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    if (isSatisfied(state)) return 0;

    final action = state.registries.actions.byId(actionId);
    if (action is! SkillAction) return infTicks;

    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    if (inputs.isEmpty) return 0;

    // Find the bottleneck input (longest time to gather)
    var maxTicks = 0;
    for (final entry in inputs.entries) {
      final item = state.registries.items.byId(entry.key);
      final available = state.inventory.countOfItem(item);
      final neededPerAction = entry.value;
      final totalNeeded = (targetCount * neededPerAction / inputs.length)
          .ceil();
      final needed = totalNeeded - available;
      if (needed <= 0) continue;

      final productionRate = rates.itemFlowsPerTick[entry.key] ?? 0.0;
      if (productionRate <= 0) return infTicks;

      final ticks = (needed / productionRate).ceil();
      if (ticks > maxTicks) maxTicks = ticks;
    }

    return maxTicks;
  }

  @override
  String describe() =>
      'sufficient inputs ($targetCount) for ${actionId.localId.name}';

  @override
  String get shortDescription => 'Sufficient inputs';

  @override
  List<Object?> get props => [actionId, targetCount];
}

/// Wait until ANY of the given conditions is satisfied.
///
/// Used for macro-step planning where we want to stop training when the
/// soonest of several conditions triggers (e.g., "next boundary OR upgrade
/// affordable OR inputs depleted").
class WaitForAnyOf extends WaitFor {
  const WaitForAnyOf(this.conditions);

  final List<WaitFor> conditions;

  @override
  bool isSatisfied(GlobalState state) {
    // Satisfied if ANY condition is met
    return conditions.any((condition) => condition.isSatisfied(state));
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    if (conditions.isEmpty) return infTicks;

    // Return minimum ticks among all conditions (first to trigger wins)
    var minTicks = infTicks;
    for (final condition in conditions) {
      final ticks = condition.estimateTicks(state, rates);
      if (ticks < minTicks) {
        minTicks = ticks;
      }
    }
    return minTicks;
  }

  @override
  String describe() {
    final descriptions = conditions.map((c) => c.describe()).join(' OR ');
    return 'any of ($descriptions)';
  }

  @override
  String get shortDescription {
    // Use the first condition's short description for brevity
    return conditions.isNotEmpty
        ? conditions.first.shortDescription
        : 'Any condition';
  }

  @override
  List<Object?> get props => [conditions];
}

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
            case SellAll():
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
        SellAll() => 'Sell all items',
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
