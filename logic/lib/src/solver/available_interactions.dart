/// Available interactions: enumerates actions that can be applied **right now**.
///
/// ## Immediate Actions Only
///
/// This module returns only 0-tick interactions (switch, buy, sell).
/// It must NOT include "wait" - that is handled by [nextDecisionDelta].
/// It must NOT include actions just because they are "watched".
///
/// ## Upgrade Filtering
///
/// The solver filters [BuyUpgrade] interactions through
/// [Candidates.buyUpgrades] to ensure only competitive upgrades are
/// considered. Watched-but-not-buyable upgrades must not show up in the
/// final action set passed to the planner.
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/upgrades.dart';
import 'package:logic/src/state.dart';

import 'interaction.dart';

/// Returns all available interactions from the current state.
///
/// This includes:
/// - SwitchActivity for each unlocked action that is not the current action
/// - BuyUpgrade for each affordable upgrade that meets skill requirements
/// - SellAll if there are sellable items in inventory
///
/// Note: the solver further filters these through [Candidates] to only
/// consider competitive options.
List<Interaction> availableInteractions(GlobalState state) {
  final interactions = <Interaction>[];

  // Add available activity switches
  interactions.addAll(_availableActivitySwitches(state));

  // Add available upgrades
  interactions.addAll(_availableUpgrades(state));

  // Add SellAll if there are sellable items
  if (_canSellAll(state)) {
    interactions.add(const SellAll());
  }

  return interactions;
}

/// Returns SwitchActivity interactions for all unlocked actions
/// that are not the current action.
List<SwitchActivity> _availableActivitySwitches(GlobalState state) {
  final currentActionName = state.activeAction?.name;
  final switches = <SwitchActivity>[];
  final registries = state.registries;

  // Check all skills for available actions
  for (final skill in Skill.values) {
    final skillLevel = state.skillState(skill).skillLevel;

    for (final action in registries.actions.forSkill(skill)) {
      // Skip if this is the current action
      if (action.name == currentActionName) continue;

      // Skip if action is locked (player doesn't meet level requirement)
      if (action.unlockLevel > skillLevel) continue;

      // Skip if action can't be started (missing inputs, depleted node, etc.)
      if (!state.canStartAction(action)) continue;

      switches.add(SwitchActivity(action.name));
    }
  }

  return switches;
}

/// Returns BuyUpgrade interactions for all affordable upgrades
/// that meet skill requirements.
List<BuyUpgrade> _availableUpgrades(GlobalState state) {
  final upgrades = <BuyUpgrade>[];

  for (final type in UpgradeType.values) {
    final currentLevel = state.shop.upgradeLevel(type);
    final next = nextUpgrade(type, currentLevel);

    // No more upgrades available for this type
    if (next == null) continue;

    // Can't afford it
    if (state.gp < next.cost) continue;

    // Doesn't meet skill requirement
    final skillLevel = state.skillState(next.skill).skillLevel;
    if (skillLevel < next.requiredLevel) continue;

    upgrades.add(BuyUpgrade(type));
  }

  return upgrades;
}

/// Returns true if there are any items in inventory (all items are sellable).
bool _canSellAll(GlobalState state) {
  return state.inventory.items.isNotEmpty;
}
