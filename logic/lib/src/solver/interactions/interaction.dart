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

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Represents a possible interaction that can change game state.
///
/// All interactions are instantaneous (0 ticks). Time advancement is
/// modeled separately.
sealed class Interaction {
  const Interaction();

  /// Serializes this [Interaction] to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes an [Interaction] from a JSON-compatible map.
  static Interaction fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'SwitchActivity' => SwitchActivity(
        ActionId.fromJson(json['actionId'] as String),
      ),
      'BuyShopItem' => BuyShopItem(
        MelvorId.fromJson(json['purchaseId'] as String),
      ),
      'SellItems' => SellItems(
        SellPolicy.fromJson(json['policy'] as Map<String, dynamic>),
      ),
      _ => throw ArgumentError('Unknown Interaction type: $type'),
    };
  }
}

/// Switch to a different activity.
class SwitchActivity extends Interaction {
  const SwitchActivity(this.actionId);

  final ActionId actionId;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'SwitchActivity',
    'actionId': actionId.toJson(),
  };

  @override
  String toString() => 'SwitchActivity($actionId)';
}

/// Buy an item from the shop.
class BuyShopItem extends Interaction {
  const BuyShopItem(this.purchaseId);

  final MelvorId purchaseId;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'BuyShopItem',
    'purchaseId': purchaseId.toJson(),
  };

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
  Map<String, dynamic> toJson() => {
    'type': 'SellItems',
    'policy': policy.toJson(),
  };

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
sealed class SellPolicy {
  const SellPolicy();

  /// Serializes this [SellPolicy] to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes a [SellPolicy] from a JSON-compatible map.
  static SellPolicy fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'SellAllPolicy' => const SellAllPolicy(),
      'SellExceptPolicy' => SellExceptPolicy(
        (json['keepItems'] as List<dynamic>)
            .map((id) => MelvorId.fromJson(id as String))
            .toSet(),
      ),
      _ => throw ArgumentError('Unknown SellPolicy type: $type'),
    };
  }

  /// Deserializes a [SellPolicy] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static SellPolicy? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return SellPolicy.fromJson(json as Map<String, dynamic>);
  }
}

/// Sell all items in inventory.
///
/// This is the default policy for GP-focused goals.
class SellAllPolicy extends SellPolicy {
  const SellAllPolicy();

  @override
  Map<String, dynamic> toJson() => {'type': 'SellAllPolicy'};

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
  Map<String, dynamic> toJson() => {
    'type': 'SellExceptPolicy',
    'keepItems': keepItems.map((id) => id.toJson()).toList(),
  };

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
sealed class SellPolicySpec {
  const SellPolicySpec();

  /// Creates a concrete [SellPolicy] from this spec and the current state.
  ///
  /// The [state] is used to determine which actions are unlocked and what
  /// inputs they require (for [ReserveConsumingInputsSpec]).
  ///
  /// The [consumingSkills] determines which skills' inputs to preserve.
  SellPolicy instantiate(GlobalState state, Set<Skill> consumingSkills);

  /// Serializes this [SellPolicySpec] to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes a [SellPolicySpec] from a JSON-compatible map.
  static SellPolicySpec fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'SellAllSpec' => const SellAllSpec(),
      'ReserveConsumingInputsSpec' => const ReserveConsumingInputsSpec(),
      _ => throw ArgumentError('Unknown SellPolicySpec type: $type'),
    };
  }

  /// Deserializes a [SellPolicySpec] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static SellPolicySpec? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return SellPolicySpec.fromJson(json as Map<String, dynamic>);
  }
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
  Map<String, dynamic> toJson() => {'type': 'SellAllSpec'};

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
  Map<String, dynamic> toJson() => {'type': 'ReserveConsumingInputsSpec'};

  @override
  String toString() => 'ReserveConsumingInputsSpec()';
}

// ---------------------------------------------------------------------------
// Private Helpers
// ---------------------------------------------------------------------------

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
