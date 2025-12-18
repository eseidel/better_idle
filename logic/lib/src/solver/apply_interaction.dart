import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/upgrades.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/types/inventory.dart';

import 'interaction.dart';

/// Applies an interaction to the game state, returning the new state.
///
/// This is a pure function that does not modify the input state.
/// Uses a fixed random seed for deterministic behavior during planning.
GlobalState applyInteraction(GlobalState state, Interaction interaction) {
  // Use a fixed random for deterministic planning
  final random = Random(42);

  return switch (interaction) {
    SwitchActivity(:final actionName) => _applySwitchActivity(
      state,
      actionName,
      random,
    ),
    BuyUpgrade(:final type) => _applyBuyUpgrade(state, type),
    SellAll() => _applySellAll(state),
  };
}

/// Switches to a different activity.
GlobalState _applySwitchActivity(
  GlobalState state,
  String actionName,
  Random random,
) {
  final action = actionRegistry.byName(actionName);

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
  final newGp = state.gp - upgrade.cost;

  // Update shop state with new upgrade level
  final newShop = switch (type) {
    UpgradeType.axe => state.shop.copyWith(axeLevel: currentLevel + 1),
    UpgradeType.fishingRod => state.shop.copyWith(
      fishingRodLevel: currentLevel + 1,
    ),
    UpgradeType.pickaxe => state.shop.copyWith(pickaxeLevel: currentLevel + 1),
  };

  return state.copyWith(gp: newGp, shop: newShop);
}

/// Sells all items in inventory.
GlobalState _applySellAll(GlobalState state) {
  var totalValue = 0;
  for (final stack in state.inventory.items) {
    totalValue += stack.sellsFor;
  }

  return state.copyWith(
    inventory: const Inventory.empty(),
    gp: state.gp + totalValue,
  );
}
