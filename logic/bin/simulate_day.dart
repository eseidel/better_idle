// Simulates running the game for 1 day and prints TimeAway information.
//
// Usage: dart run bin/simulate_day.dart [action_name]
//
// If no action is specified, defaults to 'Normal Tree' (woodcutting).
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:logic/logic.dart';

/// Prints TimeAway information to the console in a readable format.
void printTimeAway(TimeAway timeAway) {
  final activeSkill = timeAway.activeSkill;
  final duration = timeAway.duration;
  final changes = timeAway.changes;

  print('');
  print('=' * 60);
  if (activeSkill != null) {
    print('  ${activeSkill.name.toUpperCase()} - Welcome Back!');
  } else {
    print('  Welcome Back!');
  }
  print('=' * 60);
  print('');
  print('You were away for ${approximateDuration(duration)}.');
  print('');

  // Print skill level changes
  if (changes.skillLevelChanges.isNotEmpty) {
    print('LEVEL UPS:');
    for (final entry in changes.skillLevelChanges.entries) {
      final skill = entry.key;
      final levelChange = entry.value;
      final levelsGained = levelChange.levelsGained;
      final range = '${levelChange.startLevel} -> ${levelChange.endLevel}';
      final levelText = levelsGained > 1
          ? 'gained $levelsGained levels'
          : 'level up';
      print('  ✓ ${skill.name} $levelText ($range)');
    }
    print('');
  }

  // Print skill XP changes
  if (changes.skillXpChanges.isNotEmpty) {
    print('XP GAINED:');
    for (final entry in changes.skillXpChanges.entries) {
      final skill = entry.key;
      final xpGained = entry.value;
      final xpPerHour = timeAway.predictedXpPerHour[skill];
      final xpText = signedCountString(xpGained);
      final prediction = xpPerHour != null
          ? ' (${approximateCountString(xpPerHour)} xp/hr)'
          : '';
      print('  $xpText ${skill.name} XP$prediction');
    }
    print('');
  }

  // Print inventory changes
  if (changes.inventoryChanges.isNotEmpty) {
    print('INVENTORY CHANGES:');
    final itemsGained = timeAway.itemsGainedPerHour;
    final itemsConsumed = timeAway.itemsConsumedPerHour;
    for (final entry in changes.inventoryChanges.entries) {
      final itemName = entry.key;
      final itemCount = entry.value;
      final gainedPerHour = itemsGained[itemName];
      final consumedPerHour = itemsConsumed[itemName];
      final countText = signedCountString(itemCount);

      String prediction;
      if (itemCount > 0 && gainedPerHour != null) {
        prediction = ' (${approximateCountString(gainedPerHour.round())}/hr)';
      } else if (itemCount < 0 && consumedPerHour != null) {
        prediction = ' (${approximateCountString(consumedPerHour.round())}/hr)';
      } else {
        prediction = '';
      }

      print('  $countText $itemName$prediction');
    }
    print('');
  }

  // Print currencies gained
  if (changes.currenciesGained.isNotEmpty) {
    print('CURRENCIES GAINED:');
    for (final entry in changes.currenciesGained.entries) {
      final currency = entry.key;
      final amount = entry.value;
      print('  +${approximateCountString(amount)} ${currency.abbreviation}');
    }
    print('');
  }

  // Print dropped items
  if (changes.droppedItems.isNotEmpty) {
    print('DROPPED ITEMS (inventory full):');
    for (final entry in changes.droppedItems.entries) {
      print('  ⚠ ${entry.value} ${entry.key}');
    }
    print('');
  }

  // Print stop reason if action stopped
  if (timeAway.stopReason != ActionStopReason.stillRunning) {
    print('ACTION STOPPED:');
    final reason = switch (timeAway.stopReason) {
      ActionStopReason.stillRunning => 'Still running',
      ActionStopReason.outOfInputs => 'Ran out of input items',
      ActionStopReason.inventoryFull => 'Inventory full',
      ActionStopReason.playerDied => 'Player died',
    };
    final stoppedAfter = timeAway.stoppedAfter;
    final whenText = stoppedAfter != null
        ? ' after ${approximateDuration(stoppedAfter)}'
        : '';
    print('  ⛔ $reason$whenText');
    print('');
  }

  if (changes.isEmpty) {
    print('Nothing happened while you were away.');
    print('');
  }

  print('=' * 60);
}

/// Prints a summary of the final game state.
void printFinalState(GlobalState state) {
  print('');
  print('FINAL STATE:');
  print('-' * 40);

  // Print skill levels
  print('Skills:');
  for (final skill in Skill.values) {
    final skillState = state.skillState(skill);
    if (skillState.xp > 0) {
      final level = skillState.skillLevel;
      print(
        '  ${skill.name}: Level $level (${approximateCountString(skillState.xp)} XP)',
      );
    }
  }

  // Print inventory
  if (state.inventory.items.isNotEmpty) {
    print('');
    print(
      'Inventory (${state.inventoryUsed}/${state.inventoryCapacity} slots):',
    );
    for (final stack in state.inventory.items) {
      print('  ${stack.count} ${stack.item.name}');
    }
  }

  // Print GP
  if (state.gp > 0) {
    print('');
    print('GP: ${approximateCountString(state.gp)}');
  }

  print('-' * 40);
}

// It's not valid to look up an action by name, since there are duplicates
// e.g. Golbin thieving and combat.  But this is good enough for this script.
Action actionByName(ActionRegistry actions, String name) {
  return actions.all.firstWhere((a) => a.name == name);
}

void main(List<String> args) async {
  // Parse action name from args, default to 'Normal Tree'
  final actionName = args.isNotEmpty ? args.join(' ') : 'Normal Tree';

  final registries = await loadRegistries();

  // Look up the action
  final Action action;
  try {
    action = actionByName(registries.actions, actionName);
  } catch (e) {
    print('Error: Unknown action "$actionName"');
    print('');
    print('Available actions by skill:');
    for (final skill in Skill.values) {
      final actions = registries.actions.forSkill(skill).toList();
      if (actions.isNotEmpty) {
        print('  ${skill.name}:');
        for (final a in actions) {
          print('    - ${a.name}');
        }
      }
    }
    return;
  }

  print('Simulating 1 day of "${action.name}" (${action.skill.name})...');

  // Create initial state
  var state = GlobalState.empty(registries);

  // If the action requires inputs, add them to the inventory
  if (action is SkillAction && action.inputs.isNotEmpty) {
    print('');
    print('Action requires inputs, adding to inventory:');
    var inventory = state.inventory;
    for (final entry in action.inputs.entries) {
      final item = registries.items.byId(entry.key);
      // Add enough for many completions (enough for 1 day at ~1200/hr)
      const itemsNeeded = 50000;
      inventory = inventory.adding(ItemStack(item, count: itemsNeeded));
      print('  Added ${approximateCountString(itemsNeeded)}x ${item.name}');
    }
    state = state.copyWith(inventory: inventory);
  }

  // Start the action
  final random = Random();
  state = state.startAction(action, random: random);

  // Simulate 1 day (24 hours)
  const oneDay = Duration(hours: 24);
  final ticks = ticksFromDuration(oneDay);

  print(
    'Running simulation for ${approximateDuration(oneDay)} ($ticks ticks)...',
  );
  print('');

  // Consume all ticks and get the TimeAway result
  final (timeAway, finalState) = consumeManyTicks(
    state,
    ticks,
    endTime: state.updatedAt.add(oneDay),
    random: random,
  );

  // Print the TimeAway information
  printTimeAway(timeAway);

  // Print final state summary
  printFinalState(finalState);
}
