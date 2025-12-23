/// Interaction types: discrete player inputs that mutate state at 0 ticks.
///
/// ## Taxonomy
///
/// - [SwitchActivity]: Change which action is running (switch/restart)
/// - [BuyUpgrade]: Purchase a shop upgrade (buy)
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

import 'package:logic/src/data/melvor_id.dart';

/// Represents a possible interaction that can change game state.
///
/// All interactions are instantaneous (0 ticks). Time advancement is
/// modeled separately.
sealed class Interaction {
  const Interaction();
}

/// Switch to a different activity.
class SwitchActivity extends Interaction {
  const SwitchActivity(this.actionId);

  final MelvorId actionId;

  @override
  String toString() => 'SwitchActivity($actionId)';

  @override
  bool operator ==(Object other) =>
      other is SwitchActivity && other.actionId == actionId;

  @override
  int get hashCode => actionId.hashCode;
}

/// Buy an item from the shop.
class BuyShopItem extends Interaction {
  const BuyShopItem(this.purchaseId);

  final MelvorId purchaseId;

  @override
  String toString() => 'BuyShopItem($purchaseId)';

  @override
  bool operator ==(Object other) =>
      other is BuyShopItem && other.purchaseId == purchaseId;

  @override
  int get hashCode => purchaseId.hashCode;
}

/// Sell all sellable items in inventory.
class SellAll extends Interaction {
  const SellAll();

  @override
  String toString() => 'SellAll()';

  @override
  bool operator ==(Object other) => other is SellAll;

  @override
  int get hashCode => runtimeType.hashCode;
}
