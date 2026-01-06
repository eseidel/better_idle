/// Replan boundaries: explicit events that can interrupt plan execution.
///
/// ## Design
///
/// In an online solver, execution may diverge from the plan due to:
/// - Stochastic simulation vs expected-value planning
/// - Resource constraints (inputs depleted, inventory full)
/// - Unexpected unlocks or affordability changes
///
/// Rather than treating these as errors, we model them as **replan
/// boundaries**: explicit events that signal execution should pause and
/// potentially re-solve.
///
/// ## Boundary Types
///
/// Boundaries fall into three categories:
///
/// 1. **Expected boundaries** - Normal flow in online planning:
///    - [GoalReached] - Plan succeeded
///    - [InputsDepleted] - Consuming action needs more inputs
///    - [InventoryFull] - Need to sell before continuing
///    - [Death] - Player died, activity will restart
///
/// 2. **Optimization opportunities** - Could improve the plan:
///    - [UpgradeAffordableEarly] - Can buy upgrade sooner than planned
///    - [UnexpectedUnlock] - New action unlocked ahead of schedule
///
/// 3. **Errors** - Indicate bugs or invalid plans:
///    - [CannotAfford] - Tried to buy something unaffordable
///    - [ActionUnavailable] - Tried to start locked/impossible action
///
/// ## Usage
///
/// ```dart
/// final result = consumeUntil(state, waitFor, random: random);
/// switch (result.boundary) {
///   case GoalReached():
///     // Success!
///   case InputsDepleted():
///     // Switch to producer, then continue
///   case null:
///     // Wait condition satisfied normally
/// }
/// ```
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// An event that can interrupt plan execution.
///
/// Boundaries are first-class: they are expected in online planning,
/// not errors. The solver should handle each boundary type appropriately.
@immutable
sealed class ReplanBoundary {
  const ReplanBoundary();

  /// Human-readable description of what happened.
  String describe();

  /// Whether this boundary is expected in normal operation.
  ///
  /// Expected boundaries are handled gracefully (e.g., by switching actions).
  /// Unexpected boundaries may indicate bugs or invalid plans.
  bool get isExpected;

  /// Whether hitting this boundary should trigger replanning.
  ///
  /// Some boundaries require the solver to create a new plan from the current
  /// state (e.g., inputs depleted, new actions unlocked). Others don't require
  /// replanning (e.g., goal reached, wait condition satisfied).
  ///
  /// Note: This is distinct from [isExpected]. An expected boundary like
  /// [InputsDepleted] still requires replanning, while [GoalReached] is
  /// expected but doesn't require a new plan.
  bool get causesReplan;
}

// ---------------------------------------------------------------------------
// Expected boundaries (normal online flow)
// ---------------------------------------------------------------------------

/// The goal was reached - plan succeeded.
@immutable
class GoalReached extends ReplanBoundary {
  const GoalReached();

  @override
  String describe() => 'Goal reached';

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => false;
}

/// A consuming action ran out of inputs.
///
/// Expected behavior: switch to a producer action to gather more inputs,
/// then resume the consuming action.
@immutable
class InputsDepleted extends ReplanBoundary {
  const InputsDepleted({required this.actionId, required this.missingItemId});

  /// The consuming action that ran out of inputs.
  final ActionId actionId;

  /// The input item that was depleted.
  final MelvorId missingItemId;

  @override
  String describe() =>
      'Inputs depleted for ${actionId.localId} '
      '(need ${missingItemId.name})';

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => true;
}

/// Inventory is full and cannot add new item types.
///
/// Expected behavior: sell items or wait for existing stacks to be consumed.
@immutable
class InventoryFull extends ReplanBoundary {
  const InventoryFull();

  @override
  String describe() => 'Inventory full';

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => true;
}

/// Player died during thieving or combat.
///
/// The boundary resolver handles recovery by attempting to re-equip lost items
/// or food, then restarting the activity. Deaths may trigger replanning if
/// recovery fails repeatedly.
@immutable
class Death extends ReplanBoundary {
  const Death({this.actionId, this.lostItem, this.slotRolled});

  /// The action that was running when death occurred.
  final ActionId? actionId;

  /// The item that was lost due to the death penalty (null if lucky).
  final ItemStack? lostItem;

  /// The equipment slot that was rolled for the death penalty.
  final EquipmentSlot? slotRolled;

  /// True if the player was lucky and lost nothing.
  bool get wasLucky => lostItem == null && slotRolled != null;

  @override
  String describe() {
    final parts = <String>['Player died'];
    if (lostItem != null) {
      parts.add('lost ${lostItem!.item.name}');
    } else if (slotRolled != null) {
      parts.add('lucky (empty ${slotRolled!.name})');
    }
    if (actionId != null) {
      parts.add('during ${actionId!.localId.name}');
    }
    return parts.join(' ');
  }

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => false; // Boundary resolver handles recovery
}

/// Wait condition was satisfied (not a replan trigger, just completion).
///
/// This is used when the wait condition is met without hitting any
/// other boundary. It's the "happy path" - execution completed as planned.
///
/// When the wait condition was a [WaitForAnyOf], the [satisfiedWaitFor]
/// field indicates which specific condition was satisfied first. This
/// allows callers to determine which branch of a composite wait triggered
/// without re-probing the state.
@immutable
class WaitConditionSatisfied extends ReplanBoundary {
  const WaitConditionSatisfied({this.satisfiedWaitFor});

  /// The specific [WaitFor] condition that was satisfied.
  ///
  /// For simple waits, this is the wait condition itself.
  /// For [WaitForAnyOf], this is the first condition that was satisfied.
  /// May be null for legacy code or when satisfaction was detected via
  /// ActionStopReason rather than WaitFor.
  final Object? satisfiedWaitFor;

  @override
  String describe() {
    if (satisfiedWaitFor != null) {
      return 'Wait satisfied: $satisfiedWaitFor';
    }
    return 'Wait condition satisfied';
  }

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => false;
}

// ---------------------------------------------------------------------------
// Optimization opportunities
// ---------------------------------------------------------------------------

/// An upgrade became affordable earlier than expected.
///
/// Optional behavior: could buy the upgrade now and re-plan.
/// This is an optimization opportunity, not a requirement.
@immutable
class UpgradeAffordableEarly extends ReplanBoundary {
  const UpgradeAffordableEarly({required this.purchaseId});

  /// The upgrade that became affordable.
  final MelvorId purchaseId;

  @override
  String describe() => 'Upgrade ${purchaseId.name} affordable early';

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => false; // Recovery action buys it, no replan needed
}

/// A new action unlocked earlier than expected.
///
/// Optional behavior: could switch to the new action if it's better.
@immutable
class UnexpectedUnlock extends ReplanBoundary {
  const UnexpectedUnlock({required this.actionId});

  /// The action that was unlocked.
  final ActionId actionId;

  @override
  String describe() => 'Action ${actionId.localId.name} unlocked early';

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => true; // Should replan to potentially use new action
}

// ---------------------------------------------------------------------------
// Error boundaries (indicate bugs or invalid plans)
// ---------------------------------------------------------------------------

/// Tried to buy something that isn't affordable.
///
/// This indicates a bug in the planner or executor - affordability
/// should be checked before attempting a purchase.
@immutable
class CannotAfford extends ReplanBoundary {
  const CannotAfford({
    required this.purchaseId,
    required this.cost,
    required this.available,
  });

  /// The purchase that was attempted.
  final MelvorId purchaseId;

  /// The cost of the purchase.
  final int cost;

  /// The GP available.
  final int available;

  @override
  String describe() =>
      'Cannot afford ${purchaseId.name} '
      '(cost: $cost, have: $available)';

  @override
  bool get isExpected => false;

  @override
  bool get causesReplan => true; // Error state, need to recover
}

/// Tried to start an action that isn't available.
///
/// This indicates a bug - action availability should be checked
/// before attempting to switch.
@immutable
class ActionUnavailable extends ReplanBoundary {
  const ActionUnavailable({required this.actionId, this.reason});

  /// The action that was attempted.
  final ActionId actionId;

  /// Why the action is unavailable (if known).
  final String? reason;

  @override
  String describe() =>
      'Action ${actionId.localId.name} unavailable'
      '${reason != null ? ': $reason' : ''}';

  @override
  bool get isExpected => false;

  @override
  bool get causesReplan => true; // Error state, need to recover
}

/// Execution stalled with no progress possible.
///
/// This indicates a bug or edge case not handled by the planner.
@immutable
class NoProgressPossible extends ReplanBoundary {
  const NoProgressPossible({this.reason});

  /// Why no progress is possible.
  final String? reason;

  @override
  String describe() =>
      'No progress possible${reason != null ? ': $reason' : ''}';

  @override
  bool get isExpected => false;

  @override
  bool get causesReplan => true; // Error state, need to recover
}

// ---------------------------------------------------------------------------
// Controlled replanning boundaries
// ---------------------------------------------------------------------------

/// Boundary indicating replan limit was exceeded.
///
/// This is a guardrail to prevent infinite replan loops. When the executor
/// hits this limit, execution stops and the caller must decide how to proceed.
@immutable
class ReplanLimitExceeded extends ReplanBoundary {
  const ReplanLimitExceeded(this.limit);

  final int limit;

  @override
  String describe() => 'Replan limit exceeded ($limit)';

  @override
  bool get isExpected => false;

  @override
  bool get causesReplan => false; // Terminal - execution stops
}

/// Boundary indicating time budget was exceeded.
///
/// This is a guardrail to prevent runaway execution. When total ticks across
/// all segments exceeds the budget, execution stops.
@immutable
class TimeBudgetExceeded extends ReplanBoundary {
  const TimeBudgetExceeded(this.budget, this.actual);

  final int budget;
  final int actual;

  @override
  String describe() => 'Time budget exceeded ($actual > $budget ticks)';

  @override
  bool get isExpected => false;

  @override
  bool get causesReplan => false; // Terminal - execution stops
}

// ---------------------------------------------------------------------------
// Planned segment stops (normal segmentation, not errors or goal completion)
// ---------------------------------------------------------------------------

/// A planned segment stop that wraps the original segment boundary.
///
/// This represents a **planned stop** in online planning - not an error,
/// not goal completion, just a point where the planner decided to stop
/// the segment and continue with the next one.
///
/// Examples:
/// - HorizonCapBoundary: Segment reached maximum tick horizon
/// - InventoryPressureBoundary: Inventory usage exceeded threshold
/// - UnlockBoundary: Skill level crossed an unlock boundary
///
/// The executor should continue to the next segment, not stop execution.
@immutable
class PlannedSegmentStop extends ReplanBoundary {
  const PlannedSegmentStop(this.boundary);

  /// The original segment boundary that triggered this stop.
  final Object boundary;

  @override
  String describe() => 'Planned stop: $boundary';

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => true; // Continue to next segment = replan
}

/// A skill unlock was observed during execution.
///
/// This is used when a skill level crosses an unlock boundary and new
/// actions become available. Unlike [UnexpectedUnlock], this does NOT
/// require an actionId - the unlock is identified by skill and level.
///
/// The outer loop should replan to potentially use newly unlocked actions.
@immutable
class UnlockObserved extends ReplanBoundary {
  const UnlockObserved({this.skill, this.level, this.unlocks});

  /// The skill that leveled up (if known).
  final Skill? skill;

  /// The level that was reached (if known).
  final int? level;

  /// Human-readable description of what gets unlocked (if known).
  final String? unlocks;

  @override
  String describe() {
    final parts = <String>[];
    if (skill != null) parts.add(skill!.name);
    if (level != null) parts.add('L$level');
    if (unlocks != null) parts.add('unlocks $unlocks');
    return parts.isEmpty ? 'Unlock observed' : 'Unlock: ${parts.join(' ')}';
  }

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => true; // New actions available - replan to use them
}

/// Inventory pressure was detected (nearing full capacity).
///
/// This is distinct from [InventoryFull] which means completely full.
/// Inventory pressure is a planned stopping point to allow selling before
/// becoming completely stuck.
///
/// The solver handles this boundary by:
/// 1. Computing sell policy via `goal.computeSellPolicy(state)`
/// 2. If sellable items exist, applying sell and retrying planning
/// 3. If nothing to sell, returning NoProgressPossible
///
/// This keeps selling decisions at the solver level, not in individual macros.
@immutable
class InventoryPressure extends ReplanBoundary {
  const InventoryPressure({
    required this.usedSlots,
    required this.totalSlots,
    this.blockedItemId,
  });

  /// Number of inventory slots in use.
  final int usedSlots;

  /// Total inventory capacity.
  final int totalSlots;

  /// The item that was being stocked when pressure was detected (if known).
  /// Useful for debugging and error messages.
  final MelvorId? blockedItemId;

  /// Pressure ratio (0.0 to 1.0).
  double get pressure => usedSlots / totalSlots;

  @override
  String describe() {
    final itemInfo = blockedItemId != null
        ? ' while stocking ${blockedItemId!.localId}'
        : '';
    return 'Inventory pressure ($usedSlots/$totalSlots slots)$itemInfo';
  }

  @override
  bool get isExpected => true;

  @override
  bool get causesReplan => true; // Needs recovery (sell) then continue
}
