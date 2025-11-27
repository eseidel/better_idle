import 'package:better_idle/src/activities.dart';
import 'package:better_idle/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('consumeTicks', () {
    test('consuming ticks for 1 completion adds 1 item and 1x XP', () {
      final activity =
          allActivities.first; // Normal Tree (3s, 10 XP, 1 Normal Logs)
      var state = GlobalState.empty();

      // Start activity
      state = state.startActivity(activity.name);

      // Advance time by exactly 1 completion (30 ticks = 3 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30);
      state = builder.build();

      // Verify activity progress reset to 0 (ready for next completion)
      expect(state.activeActivity?.progress, 0);
      expect(state.activeActivity?.name, activity.name);

      // Verify 1 item in inventory
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Normal Logs');
      expect(state.inventory.items.first.count, 1);

      // Verify 1x XP
      expect(state.skillXp(activity.skill), activity.xp);

      // Also validate that builder.changes contains the expected inventory and xp changes.
      expect(builder.changes.inventoryChanges, {'Normal Logs': 1});
      expect(builder.changes.xpChanges, {activity.skill.name: activity.xp});
    });

    test('consuming ticks for 5 completions adds 5 items and 5x XP', () {
      final activity =
          allActivities.first; // Normal Tree (3s, 10 XP, 1 Normal Logs)
      var state = GlobalState.empty();

      // Start activity
      state = state.startActivity(activity.name);

      // Advance time by exactly 5 completions (150 ticks = 15 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 150);
      state = builder.build();

      // Verify activity progress reset to 0 (ready for next completion)
      expect(state.activeActivity?.progress, 0);
      expect(state.activeActivity?.name, activity.name);

      // Verify 5 items in inventory
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Normal Logs');
      expect(state.inventory.items.first.count, 5);

      // Verify 5x XP
      expect(state.skillXp(activity.skill), activity.xp * 5);

      // Also validate that builder.changes contains the expected inventory and xp changes.
      expect(builder.changes.inventoryChanges, {'Normal Logs': 5});
      expect(builder.changes.xpChanges, {activity.skill.name: activity.xp * 5});
    });

    test('consuming ticks for partial completion does not add rewards', () {
      final activity =
          allActivities.first; // Normal Tree (3s, 10 XP, 1 Normal Logs)
      var state = GlobalState.empty();

      // Start activity
      state = state.startActivity(activity.name);

      // Advance time by only 15 ticks (1.5 seconds, half completion)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 15);
      state = builder.build();

      // Verify activity progress is at 15 (halfway)
      expect(state.activeActivity?.progress, 15);
      expect(state.activeActivity?.name, activity.name);

      // Verify no items in inventory
      expect(state.inventory.items.length, 0);

      // Verify no XP
      expect(state.skillXp(activity.skill), 0);
    });

    test('consuming ticks for 1.5 completions adds 1 item and 1x XP', () {
      final activity =
          allActivities.first; // Normal Tree (3s, 10 XP, 1 Normal Logs)
      var state = GlobalState.empty();

      // Start activity
      state = state.startActivity(activity.name);

      // Advance time by 1.5 completions (45 ticks = 4.5 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 45);
      state = builder.build();

      // Verify activity progress is at 15 (halfway through second completion)
      expect(state.activeActivity?.progress, 15);
      expect(state.activeActivity?.name, activity.name);

      // Verify 1 item in inventory (only first completion counted)
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Normal Logs');
      expect(state.inventory.items.first.count, 1);

      // Verify 1x XP (only first completion counted)
      expect(state.skillXp(activity.skill), activity.xp);
    });

    test('consuming ticks works with different activity (Oak Tree)', () {
      final activity = allActivities[1]; // Oak Tree (3s, 15 XP, 1 Oak Logs)
      var state = GlobalState.empty();

      // Start activity
      state = state.startActivity(activity.name);

      // Advance time by exactly 2 completions (60 ticks = 6 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 60);
      state = builder.build();

      // Verify activity progress reset to 0
      expect(state.activeActivity?.progress, 0);
      expect(state.activeActivity?.name, activity.name);

      // Verify 2 items in inventory
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Oak Logs');
      expect(state.inventory.items.first.count, 2);

      // Verify 2x XP (15 * 2 = 30)
      expect(state.skillXp(activity.skill), activity.xp * 2);
    });

    test('consuming ticks with no active activity does nothing', () {
      var state = GlobalState.empty();

      // No activity started, try to consume ticks
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100);
      state = builder.build();

      // Verify state unchanged
      expect(state.activeActivity, null);
      expect(state.inventory.items.length, 0);
      expect(state.skillXp(Skill.woodcutting), 0);
    });

    test('consuming ticks for exactly 0 ticks does nothing', () {
      final activity = allActivities.first;
      var state = GlobalState.empty();

      // Start activity
      state = state.startActivity(activity.name);

      // Consume 0 ticks
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 0);
      state = builder.build();

      // Verify no progress, no rewards, no XP
      expect(state.activeActivity?.progress, 0);
      expect(state.inventory.items.length, 0);
      expect(state.skillXp(activity.skill), 0);
    });

    test('consuming ticks handles activity with multiple rewards', () {
      // This test assumes we might have activities with multiple rewards in the future
      // For now, we'll test that the rewards list is properly processed
      final activity = allActivities.first;
      var state = GlobalState.empty();

      // Start activity
      state = state.startActivity(activity.name);

      // Advance by 3 completions
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 90);
      state = builder.build();

      // Verify all rewards are accumulated correctly
      // Normal Tree has 1 reward, so we should have 3 of that item
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.count, 3);
    });
  });
}
