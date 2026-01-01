/// Interaction types: discrete player inputs that mutate state at 0 ticks.
///
/// ## Taxonomy
///
/// - [SwitchActivity]: Change which action is running (switch/restart)
/// - [BuyShopItem]: Purchase a shop item/upgrade (buy)
/// - [SellItems]: Sell inventory items according to a policy (sell)
///
/// ## Design Notes
///
/// The solver optimizes primarily for simulated time (ticks); interactions
/// are a secondary objective (optionally minimized for "fewer clicks").
///
/// These are all **instantaneous** (0-tick) state changes. Waiting (time
/// passing) is handled separately via [WaitStep] in plans.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart' show Skill;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/plan.dart' show WaitStep;
import 'package:logic/src/state.dart' show GlobalState;
import 'package:meta/meta.dart';

/// Represents a possible interaction that can change game state.
///
/// All interactions are instantaneous (0 ticks). Time advancement is
/// modeled separately.
sealed class Interaction extends Equatable {
  const Interaction();
}

/// Switch to a different activity.
class SwitchActivity extends Interaction {
  const SwitchActivity(this.actionId);

  final ActionId actionId;

  @override
  List<Object?> get props => [actionId];

  @override
  String toString() => 'SwitchActivity($actionId)';
}

/// Buy an item from the shop.
class BuyShopItem extends Interaction {
  const BuyShopItem(this.purchaseId);

  final MelvorId purchaseId;

  @override
  List<Object?> get props => [purchaseId];

  @override
  String toString() => 'BuyShopItem($purchaseId)';
}

/// Sell inventory items according to a policy.
///
/// The [policy] determines which items to sell vs keep.
class SellItems extends Interaction {
  const SellItems(this.policy);

  final SellPolicy policy;

  @override
  List<Object?> get props => [policy];

  @override
  String toString() => 'SellItems($policy)';
}

// ---------------------------------------------------------------------------
// Sell Policies
// ---------------------------------------------------------------------------

/// Policy that determines which items to sell vs keep.
///
/// Used by [SellItems] to filter items before selling.
@immutable
sealed class SellPolicy extends Equatable {
  const SellPolicy();
}

/// Sell all items in inventory.
///
/// This is the default policy for GP-focused goals.
class SellAllPolicy extends SellPolicy {
  const SellAllPolicy();

  @override
  List<Object?> get props => [];

  @override
  String toString() => 'SellAllPolicy()';
}

/// Sell all items except those in the keep list.
///
/// Used for consuming skill goals to preserve inputs (logs, fish, ore).
class SellExceptPolicy extends SellPolicy {
  const SellExceptPolicy(this.keepItems);

  /// Item IDs to keep (not sell).
  final Set<MelvorId> keepItems;

  @override
  List<Object?> get props => [keepItems];

  @override
  String toString() => 'SellExceptPolicy(keep: ${keepItems.length} items)';
}

// ---------------------------------------------------------------------------
// Sell Policy Specs
// ---------------------------------------------------------------------------

/// Specification for which sell policy family to use.
///
/// This is a stable, immutable description chosen once per solve/segment.
/// It does not contain state-dependent data like the `keepItems` set.
///
/// Use [instantiate] to create a concrete [SellPolicy] from a spec + state.
@immutable
sealed class SellPolicySpec extends Equatable {
  const SellPolicySpec();

  /// Creates a concrete [SellPolicy] from this spec and the current state.
  ///
  /// The [state] is used to determine which actions are unlocked and what
  /// inputs they require (for [ReserveConsumingInputsSpec]).
  ///
  /// The [consumingSkills] determines which skills' inputs to preserve.
  SellPolicy instantiate(GlobalState state, Set<Skill> consumingSkills);
}

/// Sell all items - no reservations.
///
/// Used for GP goals where all items contribute to progress.
class SellAllSpec extends SellPolicySpec {
  const SellAllSpec();

  @override
  SellPolicy instantiate(GlobalState state, Set<Skill> consumingSkills) {
    return const SellAllPolicy();
  }

  @override
  List<Object?> get props => [];

  @override
  String toString() => 'SellAllSpec()';
}

/// Reserve inputs for consuming skills before selling.
///
/// This is the default spec for skill goals with consuming skills.
/// Computes the keep set from unlocked actions' inputs.
class ReserveConsumingInputsSpec extends SellPolicySpec {
  const ReserveConsumingInputsSpec();

  @override
  SellPolicy instantiate(GlobalState state, Set<Skill> consumingSkills) {
    if (consumingSkills.isEmpty) {
      return const SellAllPolicy();
    }

    final keepItems = _computeKeepItemsForSkills(state, consumingSkills);
    if (keepItems.isEmpty) {
      return const SellAllPolicy();
    }
    return SellExceptPolicy(keepItems);
  }

  @override
  List<Object?> get props => [];

  @override
  String toString() => 'ReserveConsumingInputsSpec()';
}

/// Computes which items to keep (not sell) for the given consuming skills.
///
/// Finds all unlocked actions for the consuming skills and collects their
/// input items.
Set<MelvorId> _computeKeepItemsForSkills(
  GlobalState state,
  Set<Skill> consumingSkills,
) {
  final keepItems = <MelvorId>{};
  final registries = state.registries;

  for (final skill in consumingSkills) {
    for (final action in registries.actions.forSkill(skill)) {
      // Check if action is unlocked
      final skillLevel = state.skillState(skill).skillLevel;
      if (action.unlockLevel > skillLevel) continue;

      // Get input items for this action
      final actionState = state.actionState(action.id);
      final selection = actionState.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);

      // Add all input item IDs to keep set
      keepItems.addAll(inputs.keys);
    }
  }

  return keepItems;
}

// ---------------------------------------------------------------------------
// Effective GP Calculations
// ---------------------------------------------------------------------------

/// Calculates the value of inventory items that can be sold per [sellPolicy].
///
/// This is the GP that would be gained by applying a [SellItems] interaction
/// with the given policy. Items excluded by the policy are not counted.
int sellableValue(GlobalState state, SellPolicy sellPolicy) {
  var total = 0;
  for (final stack in state.inventory.items) {
    if (sellPolicy is SellExceptPolicy &&
        sellPolicy.keepItems.contains(stack.item.id)) {
      continue;
    }
    total += stack.sellsFor;
  }
  return total;
}

/// Calculates effective GP: actual GP + sellable inventory value.
///
/// This represents the total GP available if the player sold all items
/// permitted by [sellPolicy]. Use this for affordability checks in planning.
///
/// For immediate purchase checks (can buy right now), use [GlobalState.gp].
int effectiveCredits(GlobalState state, SellPolicy sellPolicy) {
  return state.gp + sellableValue(state, sellPolicy);
}
