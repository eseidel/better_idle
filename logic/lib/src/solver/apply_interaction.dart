/// Interaction application: pure state mutation at 0 ticks.
///
/// ## Design
///
/// Interactions mutate state at **0 ticks**:
/// - [BuyUpgrade]: subtracts GP, updates upgrade level
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

import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/upgrades.dart';
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
    BuyUpgrade(:final type) => _applyBuyUpgrade(state, type),
    SellAll() => _applySellAll(state),
  };
}

/// Switches to a different activity.
GlobalState _applySwitchActivity(
  GlobalState state,
  MelvorId actionId,
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

/// Buys an upgrade from the shop.
GlobalState _applyBuyUpgrade(GlobalState state, UpgradeType type) {
  final currentLevel = state.shop.upgradeLevel(type);
  final upgrade = nextUpgrade(type, currentLevel);

  if (upgrade == null) {
    throw StateError('No more upgrades available for $type');
  }

  if (state.gp < upgrade.cost) {
    throw StateError(
      'Cannot afford ${upgrade.name}: costs ${upgrade.cost}, have ${state.gp}',
    );
  }

  // Deduct cost
  final stateAfterPayment = state.addCurrency(Currency.gp, -upgrade.cost);

  // Update shop state with new upgrade level
  final newShop = switch (type) {
    UpgradeType.axe => state.shop.copyWith(axeLevel: currentLevel + 1),
    UpgradeType.fishingRod => state.shop.copyWith(
      fishingRodLevel: currentLevel + 1,
    ),
    UpgradeType.pickaxe => state.shop.copyWith(pickaxeLevel: currentLevel + 1),
  };

  return stateAfterPayment.copyWith(shop: newShop);
}

/// Sells all items in inventory.
GlobalState _applySellAll(GlobalState state) {
  for (final stack in state.inventory.items) {
    state = state.sellItem(stack);
  }
  return state;
}
