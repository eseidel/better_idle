/// Interaction application: pure state mutation at 0 ticks.
///
/// ## Design
///
/// Interactions mutate state at **0 ticks**:
/// - [BuyShopItem]: subtracts GP, updates purchase count
/// - [SwitchActivity]: sets active action
/// - [SellAll]: clears inventory, adds GP
///
/// No implicit waiting here. `applyInteraction` must not change policy;
/// it just applies the chosen action.
///
/// ## Upgrade Note
///
/// Buying an upgrade does NOT imply it will be used. The solver prevents
/// irrelevant buys via candidate filtering in [enumerateCandidates].
library;

import 'dart:math';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/state.dart';

import 'interaction.dart';

/// Applies an interaction to the game state, returning the new state.
///
/// This is a pure function that does not modify the input state.
/// Uses a fixed random seed for deterministic behavior during planning.
GlobalState applyInteraction(GlobalState state, Interaction interaction) {
  // Use a fixed random for deterministic planning
  final random = Random(42);

  return switch (interaction) {
    SwitchActivity(:final actionId) => _applySwitchActivity(
      state,
      actionId,
      random,
    ),
    BuyShopItem(:final purchaseId) => _applyBuyShopItem(state, purchaseId),
    SellAll() => _applySellAll(state),
  };
}

/// Switches to a different activity.
GlobalState _applySwitchActivity(
  GlobalState state,
  ActionId actionId,
  Random random,
) {
  final action = state.registries.actions.byId(actionId);

  // Clear current action if any (and not stunned)
  var newState = state;
  if (state.activeAction != null && !state.isStunned) {
    newState = state.clearAction();
  }

  // Start the new action
  return newState.startAction(action, random: random);
}

/// Buys a shop item.
GlobalState _applyBuyShopItem(GlobalState state, MelvorId purchaseId) {
  final purchase = state.registries.shop.byId(purchaseId);

  if (purchase == null) {
    throw StateError('Shop purchase not found: $purchaseId');
  }

  // Check buy limit
  final currentCount = state.shop.purchaseCount(purchaseId);
  if (!purchase.isUnlimited && currentCount >= purchase.buyLimit) {
    throw StateError('Already purchased maximum of ${purchase.name}');
  }

  // Calculate cost (solver only handles GP costs)
  final currencyCosts = purchase.cost.currencyCosts(
    bankSlotsPurchased: state.shop.bankSlotsPurchased,
  );
  // Extract GP cost (solver only processes GP-only purchases)
  final gpCost = currencyCosts
      .where((c) => c.$1 == Currency.gp)
      .map((c) => c.$2)
      .fold(0, (a, b) => a + b);

  if (state.gp < gpCost) {
    throw StateError(
      'Cannot afford ${purchase.name}: costs $gpCost, have ${state.gp}',
    );
  }

  // Deduct cost
  final stateAfterPayment = state.addCurrency(Currency.gp, -gpCost);

  // Update shop state with new purchase
  final newShop = state.shop.withPurchase(purchaseId);

  return stateAfterPayment.copyWith(shop: newShop);
}

/// Sells all items in inventory.
GlobalState _applySellAll(GlobalState state) {
  for (final stack in state.inventory.items) {
    state = state.sellItem(stack);
  }
  return state;
}
