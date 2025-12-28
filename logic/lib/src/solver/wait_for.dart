import 'package:equatable/equatable.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/estimate_rates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/next_decision_delta.dart' show infTicks;
import 'package:logic/src/solver/plan.dart' show WaitStep;
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
