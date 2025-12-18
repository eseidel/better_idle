// Entry point for the solver - enumerates available interactions from a state.
//
// Usage: dart run bin/solver.dart
//
// This is a first step toward building a time-optimal planner.

import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/available_interactions.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/estimate_rates.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/next_decision_delta.dart';

void main() {
  // Demo state with some progress and an active action
  var state = GlobalState.empty().copyWith(
    gp: 40, // Not enough for Iron Axe (50 GP)
    skillStates: {
      Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
      // Level 20 = 4470 XP
      Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.fishing: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.mining: const SkillState(xp: 4470, masteryPoolXp: 0),
    },
  );

  // Start an action so we have gold rate
  final action = actionRegistry.byName('Willow Tree');
  state = state.startAction(action, random: Random(0));

  print('=== Solver Demo ===');
  print('');
  print('State: Level 20 woodcutting/fishing/mining, 40 GP');
  print('Active: ${state.activeAction?.name}');
  print('');

  // Print available interactions
  print('--- Available Interactions ---');
  _printInteractions(state);

  // Print enumerated candidates
  print('');
  print('--- Enumerated Candidates ---');
  _printCandidates(state);

  // Print next decision delta
  print('');
  print('--- Next Decision Delta ---');
  _printNextDecisionDelta(state);
}

void _printInteractions(GlobalState state) {
  final interactions = availableInteractions(state);

  final switches = interactions.whereType<SwitchActivity>().toList();
  final upgrades = interactions.whereType<BuyUpgrade>().toList();
  final sells = interactions.whereType<SellAll>().toList();

  print('Activities (${switches.length}):');
  for (final s in switches) {
    final action = actionRegistry.byName(s.actionName);
    print('  - ${s.actionName} (${action.skill.name})');
  }

  if (upgrades.isNotEmpty) {
    print('Upgrades (${upgrades.length}):');
    for (final u in upgrades) {
      final currentLevel = state.shop.upgradeLevel(u.type);
      final next = nextUpgrade(u.type, currentLevel);
      print('  - ${next!.name} (${next.cost} GP)');
    }
  }

  if (sells.isNotEmpty) {
    print('Other: SellAll');
  }
}

void _printCandidates(GlobalState state) {
  final candidates = enumerateCandidates(state);
  final summaries = buildActionSummaries(state);

  print('Activity candidates (${candidates.switchToActivities.length}):');
  for (final name in candidates.switchToActivities) {
    final action = actionRegistry.skillActionByName(name);
    final summary = summaries.firstWhere((s) => s.actionName == name);
    print(
      '  - $name (${action.skill.name}) '
      '[${summary.goldRatePerTick.toStringAsFixed(4)} gp/tick]',
    );
  }

  if (candidates.buyUpgrades.isNotEmpty) {
    print('Upgrade candidates (${candidates.buyUpgrades.length}):');
    for (final type in candidates.buyUpgrades) {
      final currentLevel = state.shop.upgradeLevel(type);
      final next = nextUpgrade(type, currentLevel);
      final affordable = state.gp >= next!.cost;
      final affordStr = affordable ? 'affordable' : 'unaffordable';
      print('  - ${next.name} (${next.cost} GP) [$affordStr]');
    }
  }

  if (candidates.includeSellAll) {
    print('SellAll: included');
  }

  print('Watch list:');
  if (candidates.watch.lockedActivityNames.isNotEmpty) {
    print('  Locked activities:');
    for (final name in candidates.watch.lockedActivityNames) {
      final action = actionRegistry.skillActionByName(name);
      print(
        '    - $name (unlocks at ${action.skill.name} ${action.unlockLevel})',
      );
    }
  }
  if (candidates.watch.upgradeTypes.isNotEmpty) {
    print('  Upgrades:');
    for (final type in candidates.watch.upgradeTypes) {
      final currentLevel = state.shop.upgradeLevel(type);
      final next = nextUpgrade(type, currentLevel);
      print('    - ${next!.name} (${next.cost} GP)');
    }
  }
  if (candidates.watch.inventory) {
    print('  Inventory: watching for full');
  }
}

void _printNextDecisionDelta(GlobalState state) {
  final goal = Goal(targetCredits: 10000);
  final candidates = enumerateCandidates(state);
  final rates = estimateRates(state);
  final result = nextDecisionDelta(state, goal, candidates);

  print('Goal: ${goal.targetCredits} GP');
  print('Current GP: ${state.gp}');
  print('Gold rate: ${rates.goldPerTick.toStringAsFixed(4)} gp/tick');
  print('');
  print('Next decision in: ${result.deltaTicks} ticks');
  print('Reason: ${result.reason}');
  if (result.details != null) {
    print('Details: ${result.details}');
  }

  if (result.deltaTicks > 0 && result.deltaTicks < infTicks) {
    final seconds = result.deltaTicks * 0.1;
    print('(~${seconds.toStringAsFixed(1)} seconds)');
  }
}
