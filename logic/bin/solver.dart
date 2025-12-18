// Entry point for the solver - enumerates available interactions from a state.
//
// Usage: dart run bin/solver.dart
//
// This is a first step toward building a time-optimal planner.

import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/available_interactions.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/interaction.dart';

void main() {
  print('=== Solver: Available Interactions ===');
  print('');

  // Test 1: Empty state (no GP)
  print('Test 1: Empty state (no GP)');
  print('-' * 40);
  var state = GlobalState.empty();
  _printInteractions(state);

  // Test 2: State with 1000 GP (can afford Iron Axe at 50 GP)
  print('');
  print('Test 2: State with 1000 GP');
  print('-' * 40);
  state = GlobalState.empty().copyWith(gp: 1000);
  _printInteractions(state);

  // Test 3: State with active action (Normal Tree)
  print('');
  print('Test 3: State with active action (Normal Tree, 500 GP)');
  print('-' * 40);
  state = GlobalState.empty().copyWith(gp: 500);
  final action = actionRegistry.byName('Normal Tree');
  final random = Random(0);
  state = state.startAction(action, random: random);
  _printInteractions(state);

  // Test 4: State with high GP and high skill levels
  print('');
  print(
    'Test 4: State with 100k GP and level 20 in woodcutting/fishing/mining',
  );
  print('-' * 40);
  state = GlobalState.empty().copyWith(
    gp: 100000,
    skillStates: {
      Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
      // Level 20 = 4470 XP
      Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.fishing: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.mining: const SkillState(xp: 4470, masteryPoolXp: 0),
    },
  );
  _printInteractions(state);

  // Test 5: State with sellable items in inventory
  print('');
  print('Test 5: State with sellable items in inventory');
  print('-' * 40);
  final logs = itemRegistry.byName('Normal Logs');
  final ore = itemRegistry.byName('Copper Ore');
  state = GlobalState.empty().copyWith(
    inventory: Inventory.fromItems([
      ItemStack(logs, count: 100),
      ItemStack(ore, count: 50),
    ]),
  );
  _printInteractions(state);

  // === Enumerate Candidates Section ===
  print('');
  print('');
  print('=== Solver: Enumerate Candidates ===');
  print('');

  // Test 1: Empty state
  print('Test 1: Empty state');
  print('-' * 40);
  state = GlobalState.empty();
  _printCandidates(state);

  // Test 2: State with 1000 GP
  print('');
  print('Test 2: State with 1000 GP');
  print('-' * 40);
  state = GlobalState.empty().copyWith(gp: 1000);
  _printCandidates(state);

  // Test 3: State with level 20 in woodcutting/fishing/mining
  print('');
  print('Test 3: State with level 20 in woodcutting/fishing/mining');
  print('-' * 40);
  state = GlobalState.empty().copyWith(
    gp: 5000,
    skillStates: {
      Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
      // Level 20 = 4470 XP
      Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.fishing: const SkillState(xp: 4470, masteryPoolXp: 0),
      Skill.mining: const SkillState(xp: 4470, masteryPoolXp: 0),
    },
  );
  _printCandidates(state);

  // Test 4: State with high inventory usage
  print('');
  print('Test 4: State with high inventory usage (>80%)');
  print('-' * 40);
  // Create inventory with 17+ unique items (>80% of 20 slots)
  state = GlobalState.empty().copyWith(
    inventory: Inventory.fromItems([
      ItemStack(itemRegistry.byName('Normal Logs'), count: 10),
      ItemStack(itemRegistry.byName('Oak Logs'), count: 10),
      ItemStack(itemRegistry.byName('Willow Logs'), count: 10),
      ItemStack(itemRegistry.byName('Teak Logs'), count: 10),
      ItemStack(itemRegistry.byName('Raw Shrimp'), count: 10),
      ItemStack(itemRegistry.byName('Raw Lobster'), count: 10),
      ItemStack(itemRegistry.byName('Raw Sardine'), count: 10),
      ItemStack(itemRegistry.byName('Raw Herring'), count: 10),
      ItemStack(itemRegistry.byName('Copper Ore'), count: 10),
      ItemStack(itemRegistry.byName('Tin Ore'), count: 10),
      ItemStack(itemRegistry.byName('Iron Ore'), count: 10),
      ItemStack(itemRegistry.byName('Bronze Bar'), count: 10),
      ItemStack(itemRegistry.byName('Iron Bar'), count: 10),
      ItemStack(itemRegistry.byName('Shrimp'), count: 10),
      ItemStack(itemRegistry.byName('Sardine'), count: 10),
      ItemStack(itemRegistry.byName('Herring'), count: 10),
      ItemStack(itemRegistry.byName('Coal Ore'), count: 10),
    ]),
  );
  _printCandidates(state);
}

void _printInteractions(GlobalState state) {
  final interactions = availableInteractions(state);

  // Group by type for readability
  final switches = interactions.whereType<SwitchActivity>().toList();
  final upgrades = interactions.whereType<BuyUpgrade>().toList();
  final sells = interactions.whereType<SellAll>().toList();

  print('Current action: ${state.activeAction?.name ?? "(none)"}');
  print('GP: ${state.gp}');
  print('');
  print('Available interactions (${interactions.length} total):');

  if (switches.isNotEmpty) {
    print('  Activities (${switches.length}):');
    for (final s in switches) {
      final action = actionRegistry.byName(s.actionName);
      print('    - ${s.actionName} (${action.skill.name})');
    }
  }

  if (upgrades.isNotEmpty) {
    print('  Upgrades (${upgrades.length}):');
    for (final u in upgrades) {
      final currentLevel = state.shop.upgradeLevel(u.type);
      final next = nextUpgrade(u.type, currentLevel);
      print('    - ${next!.name} (${next.cost} GP)');
    }
  }

  if (sells.isNotEmpty) {
    print('  Other:');
    for (final s in sells) {
      print('    - $s');
    }
  }

  if (interactions.isEmpty) {
    print('  (none)');
  }
}

void _printCandidates(GlobalState state) {
  final candidates = enumerateCandidates(state);

  print('Current action: ${state.activeAction?.name ?? "(none)"}');
  print('GP: ${state.gp}');
  print('');

  // Print activity candidates
  print('Activity candidates (${candidates.switchToActivities.length}):');
  for (final name in candidates.switchToActivities) {
    final action = actionRegistry.skillActionByName(name);
    final summaries = buildActionSummaries(state);
    final summary = summaries.firstWhere((s) => s.actionName == name);
    print(
      '  - $name (${action.skill.name}) '
      '[${summary.goldRatePerTick.toStringAsFixed(4)} gp/tick]',
    );
  }

  // Print upgrade candidates
  if (candidates.buyUpgrades.isNotEmpty) {
    print('');
    print('Upgrade candidates (${candidates.buyUpgrades.length}):');
    for (final type in candidates.buyUpgrades) {
      final currentLevel = state.shop.upgradeLevel(type);
      final next = nextUpgrade(type, currentLevel);
      final affordable = state.gp >= next!.cost;
      final affordStr = affordable ? '✓' : '✗';
      print('  - ${next.name} (${next.cost} GP) [$affordStr affordable]');
    }
  }

  // Print SellAll
  if (candidates.includeSellAll) {
    print('');
    print('SellAll: included (inventory > 80% full)');
  }

  // Print watch list
  print('');
  print('Watch list:');
  if (candidates.watch.lockedActivityNames.isNotEmpty) {
    print('  Locked activities to watch:');
    for (final name in candidates.watch.lockedActivityNames) {
      final action = actionRegistry.skillActionByName(name);
      print(
        '    - $name (unlocks at ${action.skill.name} ${action.unlockLevel})',
      );
    }
  }
  if (candidates.watch.upgradeTypes.isNotEmpty) {
    print('  Upgrades to watch:');
    for (final type in candidates.watch.upgradeTypes) {
      final currentLevel = state.shop.upgradeLevel(type);
      final next = nextUpgrade(type, currentLevel);
      print('    - ${next!.name} (${next.cost} GP)');
    }
  }
  if (candidates.watch.inventory) {
    print('  Inventory: watching for full');
  }
  if (candidates.watch.lockedActivityNames.isEmpty &&
      candidates.watch.upgradeTypes.isEmpty &&
      !candidates.watch.inventory) {
    print('  (nothing to watch)');
  }
}
