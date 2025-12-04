import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/inventory.dart';
import 'package:better_idle/src/types/time_away.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final normalLogs = itemRegistry.byName('Normal Logs');
  final oakLogs = itemRegistry.byName('Oak Logs');
  test('GlobalState toJson/fromJson round-trip', () {
    // Create a state with TimeAway data
    final originalState = GlobalState(
      inventory: Inventory.fromItems([
        ItemStack(item: normalLogs, count: 5),
        ItemStack(item: oakLogs, count: 3),
      ]),
      activeAction: const ActiveAction(name: 'Normal Tree', progressTicks: 15),
      skillStates: {
        Skill.woodcutting: const SkillState(xp: 100, masteryXp: 50),
      },
      actionStates: {
        'Normal Tree': const ActionState(masteryXp: 25),
        'Oak Tree': const ActionState(masteryXp: 10),
      },
      updatedAt: DateTime(2024, 1, 1, 12),
      gp: 0,
      timeAway: TimeAway(
        startTime: DateTime(2024, 1, 1, 11, 59, 30),
        endTime: DateTime(2024, 1, 1, 12),
        activeSkill: Skill.woodcutting,
        changes: const Changes(
          inventoryChanges: Counts<String>(
            counts: {'Normal Logs': 10, 'Oak Logs': 5},
          ),
          skillXpChanges: Counts<Skill>(counts: {Skill.woodcutting: 50}),
        ),
      ),
    );

    // Convert to JSON
    final json = originalState.toJson();

    // Convert back from JSON
    final loaded = GlobalState.fromJson(json);

    // Verify all fields match
    expect(loaded.updatedAt, originalState.updatedAt);
    final items = loaded.inventory.items;
    expect(items.length, 2);
    expect(items[0].item, normalLogs);
    expect(items[0].count, 5);
    expect(items[1].item, oakLogs);
    expect(items[1].count, 3);

    expect(loaded.activeAction?.name, 'Normal Tree');
    expect(loaded.activeAction?.progressTicks, 15);

    expect(loaded.skillStates.length, 1);
    expect(loaded.skillStates[Skill.woodcutting]?.xp, 100);
    expect(loaded.skillStates[Skill.woodcutting]?.masteryXp, 50);

    expect(loaded.actionStates.length, 2);
    expect(loaded.actionStates['Normal Tree']?.masteryXp, 25);
    expect(loaded.actionStates['Oak Tree']?.masteryXp, 10);

    // Verify TimeAway data
    final timeAway = loaded.timeAway;
    expect(timeAway, isNotNull);
    expect(timeAway!.duration, const Duration(seconds: 30));
    expect(timeAway.activeSkill, Skill.woodcutting);
    final changes = timeAway.changes;
    expect(changes.inventoryChanges.counts.length, 2);
    expect(changes.inventoryChanges.counts['Normal Logs'], 10);
    expect(changes.inventoryChanges.counts['Oak Logs'], 5);
    expect(changes.skillXpChanges.counts.length, 1);
    expect(changes.skillXpChanges.counts[Skill.woodcutting], 50);
  });

  test('GlobalState clearAction clears activeAction', () {
    // Create a state with an activeAction
    final stateWithAction = GlobalState(
      inventory: Inventory.fromItems([ItemStack(item: normalLogs, count: 5)]),
      activeAction: const ActiveAction(name: 'Normal Tree', progressTicks: 15),
      skillStates: {
        Skill.woodcutting: const SkillState(xp: 100, masteryXp: 50),
      },
      actionStates: {'Normal Tree': const ActionState(masteryXp: 25)},
      updatedAt: DateTime(2024, 1, 1, 12),
      gp: 0,
    );

    // Clear the action
    final clearedState = stateWithAction.clearAction();

    // Verify activeAction is null
    expect(clearedState.activeAction, isNull);
  });

  test('GlobalState clearTimeAway clears timeAway', () {
    // Create a state with timeAway
    final stateWithTimeAway = GlobalState(
      inventory: Inventory.fromItems([ItemStack(item: normalLogs, count: 5)]),
      activeAction: const ActiveAction(name: 'Normal Tree', progressTicks: 15),
      skillStates: {
        Skill.woodcutting: const SkillState(xp: 100, masteryXp: 50),
      },
      actionStates: {'Normal Tree': const ActionState(masteryXp: 25)},
      updatedAt: DateTime(2024, 1, 1, 12),
      gp: 0,
      timeAway: TimeAway(
        startTime: DateTime(2024, 1, 1, 11, 59, 30),
        endTime: DateTime(2024, 1, 1, 12),
        activeSkill: Skill.woodcutting,
        changes: const Changes(
          inventoryChanges: Counts<String>(counts: {'Normal Logs': 10}),
          skillXpChanges: Counts<Skill>(counts: {Skill.woodcutting: 50}),
        ),
      ),
    );

    // Clear the timeAway
    final clearedState = stateWithTimeAway.clearTimeAway();

    // Verify timeAway is null
    expect(clearedState.timeAway, isNull);
  });
}
