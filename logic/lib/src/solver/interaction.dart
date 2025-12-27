/// Interaction types: discrete player inputs that mutate state at 0 ticks.
///
/// ## Taxonomy
///
/// - [SwitchActivity]: Change which action is running (switch/restart)
/// - [BuyShopItem]: Purchase a shop item/upgrade (buy)
/// - [SellAll]: Sell all inventory items (sell)
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

/// Sell all sellable items in inventory.
class SellAll extends Interaction {
  const SellAll();

  @override
  List<Object?> get props => [];

  @override
  String toString() => 'SellAll()';
}
