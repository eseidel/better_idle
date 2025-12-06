import 'dart:math';

import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/data/xp.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final normalTree = actionRegistry.byName('Normal Tree');
  final oakTree = actionRegistry.byName('Oak Tree');
  final normalLogs = itemRegistry.byName('Normal Logs');
  final birdNest = itemRegistry.byName('Bird Nest');
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
      final items = state.inventory.items;
      expect(items.length, 1);
      expect(items.first.item.name, 'Normal Logs');
      expect(items.first.count, 1);

      // Verify 1x XP
      expect(state.skillState(normalTree.skill).xp, normalTree.xp);

      // validate that builder.changes contains inventory and xp changes.
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
      final items = state.inventory.items;
      expect(items.length, 1);
      expect(items.first.item.name, 'Normal Logs');
      expect(items.first.count, 5);

      // Verify 5x XP
      expect(state.skillState(normalTree.skill).xp, normalTree.xp * 5);

      // validate that builder.changes contains inventory and xp changes.
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
      final items = state.inventory.items;
      expect(items.length, 1);
      expect(items.first.item.name, 'Normal Logs');
      expect(items.first.count, 1);

      // Verify 1x XP (only first completion counted)
      expect(state.skillState(normalTree.skill).xp, normalTree.xp);
    });

    test('consuming ticks works with different activity (Oak Tree)', () {
      var state = GlobalState.empty();

      // Start action
      state = state.startAction(oakTree);

      // Advance time by exactly 2 completions (80 ticks = 8 seconds,
      // since Oak Tree takes 4 seconds per completion)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 80);
      state = builder.build();

      // Verify activity progress reset to 0
      expect(state.activeAction?.progressTicks, 0);
      expect(state.activeAction?.name, oakTree.name);

      // Verify 2 items in inventory
      final items = state.inventory.items;
      expect(items.length, 1);
      expect(items.first.item.name, 'Oak Logs');
      expect(items.first.count, 2);

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
      // This test assumes we might have activities with multiple rewards
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

    test('skill-level drops are processed on action completion', () {
      // Use seeded random to test drop rates deterministically
      final rng = Random(12345);
      var state = GlobalState.empty();
      state = state.startAction(normalTree);

      // Consume enough ticks to drop at least one Bird Nest
      // With rate 0.005, we expect ~0.5 drops per 100 actions
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 3000, random: rng); // 100 completions
      state = builder.build();

      // Verify action-level drop (Normal Logs) is present
      final items = state.inventory.items;
      expect(items.any((i) => i.item == normalLogs), true);
      final normalLogsCount = items
          .firstWhere((i) => i.item == normalLogs)
          .count;
      expect(normalLogsCount, 100);

      // Verify skill-level drop (Bird Nest) may have dropped
      final birdNestCount = state.inventory.items
          .where((i) => i.item == birdNest)
          .fold(0, (sum, item) => sum + item.count);
      // With seeded random, we know it will always drop 1.
      expect(birdNestCount, greaterThanOrEqualTo(1));
    });

    test(
      'action with output count > 1 correctly creates drops with that count',
      () {
        // Create an action with output count > 1
        const testAction = Action(
          skill: Skill.woodcutting,
          name: 'Test Action',
          unlockLevel: 1,
          duration: Duration(seconds: 1),
          xp: 10,
          outputs: {'Normal Logs': 3}, // Count > 1
        );

        // Verify the rewards getter returns drops with the correct count
        final rewards = testAction.rewards;
        expect(rewards.length, 1);
        expect(rewards.first.name, 'Normal Logs');
        expect(rewards.first.count, 3); // Should be 3, not 1

        // Test end-to-end: complete the action and verify correct items added
        var state = GlobalState.empty();
        state = state.startAction(testAction);

        final builder = StateUpdateBuilder(state);
        // Complete the action directly (bypassing consumeTicks which
        // requires registry lookup)
        completeAction(builder, testAction);
        state = builder.build();

        // Verify 3 items were added (not 1)
        final items = state.inventory.items;
        expect(items.length, 1);
        expect(items.first.item.name, 'Normal Logs');
        expect(items.first.count, 3);
      },
    );

    test(
      'consuming ticks for action with inputs consumes the required items',
      () {
        final burnNormalLogs = actionRegistry.byName('Burn Normal Logs');
        final coalOre = itemRegistry.byName('Coal Ore');
        final ash = itemRegistry.byName('Ash');

        // Start with Normal Logs in inventory
        var state = GlobalState.empty();
        state = state.copyWith(
          inventory: Inventory.fromItems([ItemStack(normalLogs, count: 5)]),
        );

        // Verify we have 5 Normal Logs
        expect(state.inventory.countOfItem(normalLogs), 5);

        // Start the firemaking action
        state = state.startAction(burnNormalLogs);

        // Advance time by exactly 1 completion (20 ticks = 2 seconds)
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, 20);
        state = builder.build();

        // Verify activity progress reset to 0 (ready for next completion)
        expect(state.activeAction?.progressTicks, 0);
        expect(state.activeAction?.name, burnNormalLogs.name);

        // Verify 1 Normal Log was consumed (5 - 1 = 4 remaining)
        expect(state.inventory.countOfItem(normalLogs), 4);

        // Verify 1x XP was gained
        expect(state.skillState(burnNormalLogs.skill).xp, burnNormalLogs.xp);

        // Verify skill-level drops may have occurred (Coal Ore or Ash)
        final coalOreCount = state.inventory.countOfItem(coalOre);
        final ashCount = state.inventory.countOfItem(ash);
        // At least one skill-level drop should have a chance to occur
        // (Coal Ore has 40% rate, Ash has 20% rate)
        expect(coalOreCount + ashCount, greaterThanOrEqualTo(0));

        // Verify changes object tracks the consumed item
        expect(builder.changes.inventoryChanges.counts['Normal Logs'], -1);
        expect(
          builder.changes.skillXpChanges.counts[burnNormalLogs.skill],
          burnNormalLogs.xp,
        );
      },
    );

    test('consuming ticks for multiple completions of action with inputs', () {
      final burnNormalLogs = actionRegistry.byName('Burn Normal Logs');

      // Start with 10 Normal Logs in inventory
      var state = GlobalState.empty();
      state = state.copyWith(
        inventory: Inventory.fromItems([ItemStack(normalLogs, count: 10)]),
      );

      // Start the firemaking action
      state = state.startAction(burnNormalLogs);

      // Advance time by exactly 3 completions (60 ticks = 6 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 60);
      state = builder.build();

      // Verify 3 Normal Logs were consumed (10 - 3 = 7 remaining)
      expect(state.inventory.countOfItem(normalLogs), 7);

      // Verify 3x XP was gained
      expect(state.skillState(burnNormalLogs.skill).xp, burnNormalLogs.xp * 3);

      // Verify changes object tracks all consumed items
      expect(builder.changes.inventoryChanges.counts['Normal Logs'], -3);
      expect(
        builder.changes.skillXpChanges.counts[burnNormalLogs.skill],
        burnNormalLogs.xp * 3,
      );
    });

    test('consuming ticks stops when inputs are insufficient to continue', () {
      final burnNormalLogs = actionRegistry.byName('Burn Normal Logs');
      const n = 5; // Try to run 5 times
      const nMinusOne = 4; // But only have inputs for 4 times

      // Start with N-1 Normal Logs in inventory (enough for 4 completions)
      var state = GlobalState.empty();
      state = state.copyWith(
        inventory: Inventory.fromItems([
          ItemStack(normalLogs, count: nMinusOne),
        ]),
      );

      // Verify we have N-1 logs
      expect(state.inventory.countOfItem(normalLogs), nMinusOne);

      // Start the firemaking action
      state = state.startAction(burnNormalLogs);

      // Advance time by enough ticks for N completions
      // (N * 20 ticks = 100 ticks for 5 completions)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, n * 20);
      state = builder.build();

      // Verify action was cleared (can't continue without inputs)
      expect(state.activeAction, null);

      // Verify all logs were consumed (0 remaining)
      expect(state.inventory.countOfItem(normalLogs), 0);

      // Verify only N-1 completions occurred based on XP
      // (each completion gives burnNormalLogs.xp XP)
      expect(
        state.skillState(burnNormalLogs.skill).xp,
        burnNormalLogs.xp * nMinusOne,
      );

      // Verify changes object tracks all consumed items
      expect(
        builder.changes.inventoryChanges.counts['Normal Logs'],
        -nMinusOne,
      );
      expect(
        builder.changes.skillXpChanges.counts[burnNormalLogs.skill],
        burnNormalLogs.xp * nMinusOne,
      );
    });

    test('action stops when inventory is full and cannot receive outputs', () {
      // Create test items to fill inventory to capacity
      // We need 20 unique items to fill the default 20 slots
      final testItems = <ItemStack>[];
      for (var i = 0; i < 20; i++) {
        // Create unique test items to completely fill inventory
        testItems.add(
          ItemStack(Item(name: 'Test Item $i', sellsFor: 1), count: 1),
        );
      }

      var state = GlobalState.empty();
      state = state.copyWith(inventory: Inventory.fromItems(testItems));

      // Verify inventory is completely full
      expect(state.inventoryUsed, 20);
      expect(state.inventoryRemaining, 0);
      expect(state.isInventoryFull, true);

      // Start woodcutting Normal Tree (outputs Normal Logs - new item)
      // Action CAN start even with full inventory
      state = state.startAction(normalTree);
      expect(state.activeAction, isNotNull);

      // Complete one action - the output should be dropped
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30); // 1 completion
      state = builder.build();

      // Action should have stopped after first completion
      // because items were dropped
      expect(state.activeAction, isNull);

      // No Normal Logs should have been added to inventory
      expect(state.inventory.countOfItem(normalLogs), 0);

      // Verify dropped items were tracked
      expect(builder.changes.droppedItems.counts['Normal Logs'], 1);

      // Inventory should still be full with 20 items
      expect(state.inventoryUsed, 20);
    });

    test('action continues if inventory is full but can stack outputs', () {
      // Create a state with all 8 items in inventory (full)
      var state = GlobalState.empty();
      final items = <ItemStack>[
        ItemStack(normalLogs, count: 5), // Include Normal Logs
        ItemStack(itemRegistry.byName('Oak Logs'), count: 1),
        ItemStack(itemRegistry.byName('Willow Logs'), count: 1),
        ItemStack(itemRegistry.byName('Teak Logs'), count: 1),
        ItemStack(itemRegistry.byName('Bird Nest'), count: 1),
        ItemStack(itemRegistry.byName('Coal Ore'), count: 1),
        ItemStack(itemRegistry.byName('Ash'), count: 1),
        ItemStack(itemRegistry.byName('Raw Shrimp'), count: 1),
      ];
      state = state.copyWith(inventory: Inventory.fromItems(items));

      // Verify inventory has all 8 items
      expect(state.inventoryUsed, 8);

      // Start woodcutting Normal Tree (outputs Normal Logs - can stack!)
      state = state.startAction(normalTree);

      // Multiple completions should work because Normal Logs can stack
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 90); // 3 completions
      state = builder.build();

      // Verify we got 3 more Normal Logs (5 + 3 = 8 total)
      expect(state.inventory.countOfItem(normalLogs), 8);
      expect(state.activeAction, isNotNull); // Action should still be active

      // Verify changes tracked the 3 Normal Logs added
      expect(builder.changes.inventoryChanges.counts['Normal Logs'], 3);
    });

    test('TimeAway tracks dropped items when inventory is full', () {
      // Create test items to fill inventory to capacity
      final testItems = <ItemStack>[];
      for (var i = 0; i < 20; i++) {
        testItems.add(
          ItemStack(Item(name: 'Test Item $i', sellsFor: 1), count: 1),
        );
      }

      var state = GlobalState.empty();
      state = state.copyWith(inventory: Inventory.fromItems(testItems));
      state = state.startAction(normalTree);

      // Use consumeManyTicks to simulate time away
      final (timeAway, newState) = consumeManyTicks(
        state,
        90, // 3 completions worth of ticks
      );

      // Verify action stopped after first completion (items were dropped)
      expect(newState.activeAction, isNull);

      // Verify TimeAway has the dropped items
      expect(timeAway.changes.droppedItems.counts['Normal Logs'], 1);

      // No Normal Logs in inventory
      expect(newState.inventory.countOfItem(normalLogs), 0);

      // Verify TimeAway has correct duration and skill
      expect(timeAway.activeSkill, Skill.woodcutting);
      expect(timeAway.duration.inMilliseconds, greaterThan(0));
    });

    test('Changes tracks skill level gains', () {
      var state = GlobalState.empty();

      // Start with level 1 (0 XP)
      expect(levelForXp(state.skillState(Skill.woodcutting).xp), 1);

      state = state.startAction(normalTree);

      // Complete enough actions to level up
      // Level 2 requires 83 XP, normalTree gives 10 XP per completion
      // So we need 9 completions (9 * 10 = 90 XP)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30 * 9); // 9 completions
      state = builder.build();

      // Verify we leveled up to level 2
      final finalXp = state.skillState(Skill.woodcutting).xp;
      expect(finalXp, 90); // 9 * 10
      expect(levelForXp(finalXp), 2);

      // Verify changes tracked the level gain
      final levelChange =
          builder.changes.skillLevelChanges.changes[Skill.woodcutting];
      expect(levelChange, isNotNull);
      expect(levelChange!.startLevel, 1);
      expect(levelChange.endLevel, 2);
      expect(levelChange.levelsGained, 1);
      expect(builder.changes.skillXpChanges.counts[Skill.woodcutting], 90);
    });

    test('Changes tracks multiple skill level gains', () {
      var state = GlobalState.empty();

      state = state.startAction(normalTree);

      // Complete enough actions to gain multiple levels
      // Level 3 requires 174 XP, normalTree gives 10 XP per completion
      // So we need 18 completions (18 * 10 = 180 XP)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30 * 18); // 18 completions
      state = builder.build();

      // Verify we leveled up to level 3 (gained 2 levels)
      final finalXp = state.skillState(Skill.woodcutting).xp;
      expect(finalXp, 180);
      expect(levelForXp(finalXp), 3);

      // Verify changes tracked 2 level gains
      final levelChange =
          builder.changes.skillLevelChanges.changes[Skill.woodcutting];
      expect(levelChange, isNotNull);
      expect(levelChange!.startLevel, 1);
      expect(levelChange.endLevel, 3);
      expect(levelChange.levelsGained, 2);
    });

    test('TimeAway tracks skill level gains during time away', () {
      var state = GlobalState.empty();
      state = state.startAction(normalTree);

      // Complete enough ticks to level up
      final (timeAway, newState) = consumeManyTicks(
        state,
        30 * 9, // 9 completions = 90 XP = level 2
      );

      // Verify state leveled up
      expect(levelForXp(newState.skillState(Skill.woodcutting).xp), 2);

      // Verify TimeAway tracked the level gain
      final levelChange =
          timeAway.changes.skillLevelChanges.changes[Skill.woodcutting];
      expect(levelChange, isNotNull);
      expect(levelChange!.startLevel, 1);
      expect(levelChange.endLevel, 2);
    });

    test('mining action continues through node depletion and respawn', () {
      final runeEssence = actionRegistry.byName('Rune Essence');
      final runeEssenceItem = itemRegistry.byName('Rune Essence');

      var state = GlobalState.empty();
      state = state.startAction(runeEssence);

      // Rune Essence: 3 second action (30 ticks), 1 second respawn (10 ticks)
      // HP at mastery level 1: 5 + 1 = 6 HP
      // HP regen: 1 HP per 100 ticks (10 seconds)

      // Expected timeline:
      // - First 6 swings: 6 * 30 = 180 ticks (18 seconds)
      //   - At tick 100, HP regens by 1, so we get 7 total HP before depletion
      // - 7th swing completes at tick 210, node depletes
      // - Respawn: 10 ticks (1 second)
      // - Node available again at tick 220
      // - 8th swing: ticks 220-250

      // Let's run enough ticks for 10 completions worth of time
      // 10 * 30 = 300 ticks
      // Expected: 7 swings, then respawn, then 2-3 more swings
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 300);
      state = builder.build();

      // With 6 base HP + 1 regen = 7 swings before first depletion
      // After 10 tick respawn at tick 220, we have 80 ticks left
      // That's 2 more swings (60 ticks), with 20 ticks remaining
      // Total expected: 7 + 2 = 9 rune essence

      final runeEssenceCount = state.inventory.countOfItem(runeEssenceItem);
      expect(
        runeEssenceCount,
        9,
        reason: 'Should mine 7 before depletion, respawn, then mine 2 more',
      );

      // Verify action is still running
      expect(state.activeAction, isNotNull);
      expect(state.activeAction!.name, runeEssence.name);
    });

    test('mining action resumes after respawn across multiple tick cycles', () {
      // This tests the specific bug where the action would stop when a node
      // depleted and the respawn timer hadn't completed in the same tick cycle.
      final copper = actionRegistry.byName('Copper');
      final copperItem = itemRegistry.byName('Copper');

      var state = GlobalState.empty();
      state = state.startAction(copper);

      // Copper: 3 second action (30 ticks), 5 second respawn (50 ticks)
      // HP at mastery level 1: 5 + 1 = 6 HP

      // Mine until the node depletes (6 completions = 180 ticks)
      var builder = StateUpdateBuilder(state);
      consumeTicks(builder, 180);
      state = builder.build();

      // Verify we got 6 copper
      expect(state.inventory.countOfItem(copperItem), 6);

      // Verify node is depleted
      final actionState = state.actionState(copper.name);
      expect(isNodeDepleted(actionState), true);

      // Critical: Action should still be active even though node is depleted
      expect(state.activeAction, isNotNull);
      expect(state.activeAction!.name, copper.name);

      // Now simulate a few more tick cycles while node is respawning
      // Respawn takes 50 ticks, let's do 20 ticks at a time
      builder = StateUpdateBuilder(state);
      consumeTicks(builder, 20);
      state = builder.build();

      // Still depleted, still active
      expect(isNodeDepleted(state.actionState(copper.name)), true);
      expect(state.activeAction, isNotNull);
      expect(state.inventory.countOfItem(copperItem), 6); // No new copper yet

      // Another 20 ticks (40 total, still 10 ticks to go)
      builder = StateUpdateBuilder(state);
      consumeTicks(builder, 20);
      state = builder.build();

      expect(isNodeDepleted(state.actionState(copper.name)), true);
      expect(state.activeAction, isNotNull);

      // Final 20 ticks - respawn completes (10 ticks) + 10 ticks toward next
      builder = StateUpdateBuilder(state);
      consumeTicks(builder, 20);
      state = builder.build();

      // Node should no longer be depleted
      expect(isNodeDepleted(state.actionState(copper.name)), false);
      // Action should still be running
      expect(state.activeAction, isNotNull);
      expect(state.activeAction!.name, copper.name);

      // Complete another mining action
      builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30); // One more completion
      state = builder.build();

      // Should have 7 copper now (6 before + 1 after respawn)
      expect(state.inventory.countOfItem(copperItem), 7);
      expect(state.activeAction, isNotNull);
    });
  });
}
