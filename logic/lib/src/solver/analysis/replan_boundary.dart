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
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/time_away.dart';
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
}

/// Player died during thieving or combat.
///
/// Expected behavior: restart the activity automatically.
/// Death is modeled in the planner, so this is anticipated.
@immutable
class Death extends ReplanBoundary {
  const Death();

  @override
  String describe() => 'Player died';

  @override
  bool get isExpected => true;
}

/// Wait condition was satisfied (not a replan trigger, just completion).
///
/// This is used when the wait condition is met without hitting any
/// other boundary. It's the "happy path" - execution completed as planned.
@immutable
class WaitConditionSatisfied extends ReplanBoundary {
  const WaitConditionSatisfied();

  @override
  String describe() => 'Wait condition satisfied';

  @override
  bool get isExpected => true;
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
  const UpgradeAffordableEarly({required this.purchaseId, required this.cost});

  /// The upgrade that became affordable.
  final MelvorId purchaseId;

  /// The cost of the upgrade.
  final int cost;

  @override
  String describe() =>
      'Upgrade ${purchaseId.name} affordable early (cost: $cost)';

  @override
  bool get isExpected => true;
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
}

// ---------------------------------------------------------------------------
// Conversion from ActionStopReason
// ---------------------------------------------------------------------------

/// Converts an [ActionStopReason] to a [ReplanBoundary].
///
/// This bridges the simulator's stop reasons to the solver's boundary model.
ReplanBoundary? boundaryFromStopReason(
  ActionStopReason reason, {
  ActionId? actionId,
  MelvorId? missingItemId,
}) {
  return switch (reason) {
    ActionStopReason.stillRunning => null,
    ActionStopReason.outOfInputs => InputsDepleted(
      actionId: actionId!,
      missingItemId: missingItemId ?? const MelvorId('unknown:unknown'),
    ),
    ActionStopReason.inventoryFull => const InventoryFull(),
    ActionStopReason.playerDied => const Death(),
  };
}
