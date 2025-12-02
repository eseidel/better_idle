import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/inventory.dart';
import 'package:better_idle/src/types/time_away.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GlobalState toJson/fromJson round-trip', () {
    // Create a state with TimeAway data
    final originalState = GlobalState(
      inventory: Inventory.fromItems([
        ItemStack(name: 'Normal Logs', count: 5),
        ItemStack(name: 'Oak Logs', count: 3),
      ]),
      activeAction: ActiveAction(name: 'Normal Tree', progressTicks: 15),
      skillStates: {Skill.woodcutting: SkillState(xp: 100, masteryXp: 50)},
      actionStates: {
        'Normal Tree': ActionState(masteryXp: 25),
        'Oak Tree': ActionState(masteryXp: 10),
      },
      updatedAt: DateTime(2024, 1, 1, 12, 0, 0),
      gp: 0,
      timeAway: TimeAway(
        duration: Duration(seconds: 30),
        activeSkill: Skill.woodcutting,
        changes: Changes(
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
    final roundTrippedState = GlobalState.fromJson(json);

    // Verify all fields match
    expect(roundTrippedState.updatedAt, originalState.updatedAt);
    expect(roundTrippedState.inventory.items.length, 2);
    expect(roundTrippedState.inventory.items[0].name, 'Normal Logs');
    expect(roundTrippedState.inventory.items[0].count, 5);
    expect(roundTrippedState.inventory.items[1].name, 'Oak Logs');
    expect(roundTrippedState.inventory.items[1].count, 3);

    expect(roundTrippedState.activeAction?.name, 'Normal Tree');
    expect(roundTrippedState.activeAction?.progressTicks, 15);

    expect(roundTrippedState.skillStates.length, 1);
    expect(roundTrippedState.skillStates[Skill.woodcutting]?.xp, 100);
    expect(roundTrippedState.skillStates[Skill.woodcutting]?.masteryXp, 50);

    expect(roundTrippedState.actionStates.length, 2);
    expect(roundTrippedState.actionStates['Normal Tree']?.masteryXp, 25);
    expect(roundTrippedState.actionStates['Oak Tree']?.masteryXp, 10);

    // Verify TimeAway data
    expect(roundTrippedState.timeAway, isNotNull);
    expect(roundTrippedState.timeAway!.duration, Duration(seconds: 30));
    expect(roundTrippedState.timeAway!.activeSkill, Skill.woodcutting);
    expect(
      roundTrippedState.timeAway!.changes.inventoryChanges.counts.length,
      2,
    );
    expect(
      roundTrippedState
          .timeAway!
          .changes
          .inventoryChanges
          .counts['Normal Logs'],
      10,
    );
    expect(
      roundTrippedState.timeAway!.changes.inventoryChanges.counts['Oak Logs'],
      5,
    );
    expect(roundTrippedState.timeAway!.changes.skillXpChanges.counts.length, 1);
    expect(
      roundTrippedState.timeAway!.changes.skillXpChanges.counts[Skill
          .woodcutting],
      50,
    );
  });

  test('GlobalState clearAction clears activeAction', () {
    // Create a state with an activeAction
    final stateWithAction = GlobalState(
      inventory: Inventory.fromItems([
        ItemStack(name: 'Normal Logs', count: 5),
      ]),
      activeAction: ActiveAction(name: 'Normal Tree', progressTicks: 15),
      skillStates: {Skill.woodcutting: SkillState(xp: 100, masteryXp: 50)},
      actionStates: {'Normal Tree': ActionState(masteryXp: 25)},
      updatedAt: DateTime(2024, 1, 1, 12, 0, 0),
      gp: 0,
      timeAway: null,
    );

    // Clear the action
    final clearedState = stateWithAction.clearAction();

    // Verify activeAction is null
    expect(clearedState.activeAction, isNull);
  });

  test('GlobalState clearTimeAway clears timeAway', () {
    // Create a state with timeAway
    final stateWithTimeAway = GlobalState(
      inventory: Inventory.fromItems([
        ItemStack(name: 'Normal Logs', count: 5),
      ]),
      activeAction: ActiveAction(name: 'Normal Tree', progressTicks: 15),
      skillStates: {Skill.woodcutting: SkillState(xp: 100, masteryXp: 50)},
      actionStates: {'Normal Tree': ActionState(masteryXp: 25)},
      updatedAt: DateTime(2024, 1, 1, 12, 0, 0),
      gp: 0,
      timeAway: TimeAway(
        duration: Duration(seconds: 30),
        activeSkill: Skill.woodcutting,
        changes: Changes(
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
