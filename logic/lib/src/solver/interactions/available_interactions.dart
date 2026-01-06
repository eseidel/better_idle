/// Available interactions: enumerates actions that can be applied **now**.
///
/// ## Immediate Actions Only
///
/// @docImport 'package:logic/src/solver/analysis/next_decision_delta.dart';
/// This module returns only 0-tick interactions (switch, buy, sell).
/// It must NOT include "wait" - that is handled by [nextDecisionDelta].
/// It must NOT include actions just because they are "watched".
///
/// ## Upgrade Filtering
///
/// The solver filters [BuyShopItem] interactions through
/// [Candidates.buyUpgrades] to ensure only competitive upgrades are
/// considered. Watched-but-not-buyable upgrades must not show up in the
/// final action set passed to the planner.
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/solver/candidates/enumerate_candidates.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';

/// Returns all available interactions from the current state.
///
/// This includes:
/// - SwitchActivity for each unlocked action that is not the current action
/// - BuyShopItem for each affordable shop purchase that meets requirements
/// - SellItems with [sellPolicy] if there are sellable items in inventory
///
/// Note: the solver further filters these through [Candidates] to only
/// consider competitive options.
List<Interaction> availableInteractions(
  GlobalState state, {
  SellPolicy? sellPolicy,
}) {
  return <Interaction>[
    ..._availableActivitySwitches(state),
    ..._availableShopPurchases(state),
    if (sellPolicy != null && _canSell(state)) SellItems(sellPolicy),
  ];
}

/// Returns true if there are any sellable items in inventory.
bool _canSell(GlobalState state) {
  return state.inventory.items.isNotEmpty;
}

/// Returns SwitchActivity interactions for all unlocked actions
/// that are not the current action.
List<SwitchActivity> _availableActivitySwitches(GlobalState state) {
  final currentActionId = state.activeAction?.id;
  final switches = <SwitchActivity>[];
  final registries = state.registries;

  // Check all skills for available actions
  for (final skill in Skill.values) {
    final skillLevel = state.skillState(skill).skillLevel;

    for (final action in registries.actions.forSkill(skill)) {
      // Skip if this is the current action
      if (action.id == currentActionId) continue;

      // Skip if action is locked (player doesn't meet level requirement)
      if (action.unlockLevel > skillLevel) continue;

      // Skip if action can't be started (missing inputs, depleted node, etc.)
      if (!state.canStartAction(action)) continue;

      switches.add(SwitchActivity(action.id));
    }
  }

  return switches;
}

/// Returns BuyShopItem interactions for all affordable shop purchases
/// that meet requirements.
List<BuyShopItem> _availableShopPurchases(GlobalState state) {
  final purchases = <BuyShopItem>[];
  final registry = state.registries.shop;

  for (final purchase in registry.all) {
    // Check if already at buy limit
    final currentCount = state.shop.purchaseCount(purchase.id);
    if (!purchase.isUnlimited && currentCount >= purchase.buyLimit) continue;

    // Check unlock requirements (must own prerequisites)
    if (!_meetsUnlockRequirements(state, purchase)) continue;

    // Check purchase requirements (skill levels etc.)
    if (!_meetsPurchaseRequirements(state, purchase)) continue;

    // Check affordability - skip purchases without GP cost (item costs, etc.)
    final currencyCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: state.shop.bankSlotsPurchased,
    );
    // Solver only considers pure GP purchases
    if (currencyCosts.length != 1) continue;
    final (currency, cost) = currencyCosts.first;
    if (currency != Currency.gp) continue;
    if (state.gp < cost) continue;

    purchases.add(BuyShopItem(purchase.id));
  }

  return purchases;
}

/// Checks if unlock requirements are met (e.g., owning prerequisite purchases).
bool _meetsUnlockRequirements(GlobalState state, ShopPurchase purchase) {
  for (final req in purchase.unlockRequirements) {
    switch (req) {
      case ShopPurchaseRequirement(:final purchaseId, :final count):
        if (state.shop.purchaseCount(purchaseId) < count) return false;
      case SkillLevelRequirement():
        // Skill requirements are typically in purchaseRequirements, not unlock
        break;
    }
  }
  return true;
}

/// Checks if purchase requirements are met (e.g., skill levels).
bool _meetsPurchaseRequirements(GlobalState state, ShopPurchase purchase) {
  for (final req in purchase.purchaseRequirements) {
    switch (req) {
      case SkillLevelRequirement(:final skill, :final level):
        if (state.skillState(skill).skillLevel < level) return false;
      case ShopPurchaseRequirement(:final purchaseId, :final count):
        if (state.shop.purchaseCount(purchaseId) < count) return false;
    }
  }
  return true;
}
