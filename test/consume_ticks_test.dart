import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final normalTree = actionRegistry.byName('Normal Tree');
  final oakTree = actionRegistry.byName('Oak Tree');
  group('consumeTicks', () {
    test('consuming ticks for 1 completion adds 1 item and 1x XP', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(normalTree);

      // Advance time by exactly 1 completion (30 ticks = 3 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30);
      state = builder.build();

      // Verify activity progress reset to 0 (ready for next completion)
      expect(state.activeAction?.progressTicks, 0);
      expect(state.activeAction?.name, normalTree.name);

      // Verify 1 item in inventory
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Normal Logs');
      expect(state.inventory.items.first.count, 1);

      // Verify 1x XP
      expect(state.skillState(normalTree.skill).xp, normalTree.xp);

      // Also validate that builder.changes contains the expected inventory and xp changes.
      expect(builder.changes.inventoryChanges.counts, {'Normal Logs': 1});
      expect(builder.changes.skillXpChanges.counts, {
        normalTree.skill: normalTree.xp,
      });
    });

    test('consuming ticks for 5 completions adds 5 items and 5x XP', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(normalTree);

      // Advance time by exactly 5 completions (150 ticks = 15 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 150);
      state = builder.build();

      // Verify activity progress reset to 0 (ready for next completion)
      expect(state.activeAction?.progressTicks, 0);
      expect(state.activeAction?.name, normalTree.name);

      // Verify 5 items in inventory
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Normal Logs');
      expect(state.inventory.items.first.count, 5);

      // Verify 5x XP
      expect(state.skillState(normalTree.skill).xp, normalTree.xp * 5);

      // Also validate that builder.changes contains the expected inventory and xp changes.
      expect(builder.changes.inventoryChanges.counts, {'Normal Logs': 5});
      expect(builder.changes.skillXpChanges.counts, {
        normalTree.skill: normalTree.xp * 5,
      });
    });

    test('consuming ticks for partial completion does not add rewards', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(normalTree);

      // Advance time by only 15 ticks (1.5 seconds, half completion)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 15);
      state = builder.build();

      // Verify activity progress is at 15 (halfway)
      expect(state.activeAction?.progressTicks, 15);
      expect(state.activeAction?.name, normalTree.name);

      // Verify no items in inventory
      expect(state.inventory.items.length, 0);

      // Verify no XP
      expect(state.skillState(normalTree.skill).xp, 0);
    });

    test('consuming ticks for 1.5 completions adds 1 item and 1x XP', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(normalTree);

      // Advance time by 1.5 completions (45 ticks = 4.5 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 45);
      state = builder.build();

      // Verify activity progress is at 15 (halfway through second completion)
      expect(state.activeAction?.progressTicks, 15);
      expect(state.activeAction?.name, normalTree.name);

      // Verify 1 item in inventory (only first completion counted)
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Normal Logs');
      expect(state.inventory.items.first.count, 1);

      // Verify 1x XP (only first completion counted)
      expect(state.skillState(normalTree.skill).xp, normalTree.xp);
    });

    test('consuming ticks works with different activity (Oak Tree)', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(oakTree);

      // Advance time by exactly 2 completions (80 ticks = 8 seconds, since Oak Tree takes 4 seconds per completion)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 80);
      state = builder.build();

      // Verify activity progress reset to 0
      expect(state.activeAction?.progressTicks, 0);
      expect(state.activeAction?.name, oakTree.name);

      // Verify 2 items in inventory
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.name, 'Oak Logs');
      expect(state.inventory.items.first.count, 2);

      // Verify 2x XP (15 * 2 = 30)
      expect(state.skillState(oakTree.skill).xp, oakTree.xp * 2);
    });

    test('consuming ticks with no active activity does nothing', () {
      var state = GlobalState.empty();

      // No activity started, try to consume ticks
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100);
      state = builder.build();

      // Verify state unchanged
      expect(state.activeAction, null);
      expect(state.inventory.items.length, 0);
      expect(state.skillState(Skill.woodcutting).xp, 0);
    });

    test('consuming ticks for exactly 0 ticks does nothing', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(normalTree);

      // Consume 0 ticks
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 0);
      state = builder.build();

      // Verify no progress, no rewards, no XP
      expect(state.activeAction?.progressTicks, 0);
      expect(state.inventory.items.length, 0);
      expect(state.skillState(normalTree.skill).xp, 0);
    });

    test('consuming ticks handles activity with multiple rewards', () {
      // This test assumes we might have activities with multiple rewards in the future
      // For now, we'll test that the rewards list is properly processed
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(normalTree);

      // Advance by 3 completions
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 90);
      state = builder.build();

      // Verify all rewards are accumulated correctly
      // Normal Tree has 1 reward, so we should have 3 of that item
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.count, 3);
    });

    test('consuming ticks for 1 completion adds mastery XP', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(normalTree);

      // Verify initial mastery XP is 0
      expect(state.skillState(normalTree.skill).masteryXp, 0);

      // Advance time by exactly 1 completion (30 ticks = 3 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30);
      state = builder.build();

      // Verify mastery XP increased
      final masteryXpAfterFirst = state.skillState(normalTree.skill).masteryXp;
      expect(masteryXpAfterFirst, greaterThan(0));

      // Advance time by exactly 1 more completion
      final builder2 = StateUpdateBuilder(state);
      consumeTicks(builder2, 30);
      state = builder2.build();

      // Verify mastery XP increased again
      final masteryXpAfterSecond = state.skillState(normalTree.skill).masteryXp;
      expect(masteryXpAfterSecond, greaterThan(masteryXpAfterFirst));
    });
  });
}
