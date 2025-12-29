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
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/plan.dart' show WaitStep;
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
