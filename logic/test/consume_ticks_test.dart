import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late SkillAction normalTree;
  late SkillAction oakTree;
  late SkillAction burnNormalLogs;
  late MiningAction runeEssence;
  late MiningAction copper;

  late Item normalLogs;
  late Item oakLogs;
  late Item willowLogs;
  late Item teakLogs;
  late Item birdNest;
  late Item coalOre;
  late Item ash;
  late Item rawShrimp;
  late Item runeEssenceItem;
  late Item copperOre;

  setUpAll(() async {
    await loadTestRegistries();
    final actions = testActions;
    SkillAction skillAction(String name) => actions.skillActionByName(name);

    normalTree = skillAction('Normal Tree');
    oakTree = skillAction('Oak Tree');
    burnNormalLogs = skillAction('Burn Normal Logs');
    runeEssence = skillAction('Rune Essence') as MiningAction;
    copper = skillAction('Copper') as MiningAction;

    final items = testItems;
    normalLogs = items.byName('Normal Logs');
    oakLogs = items.byName('Oak Logs');
    willowLogs = items.byName('Willow Logs');
    teakLogs = items.byName('Teak Logs');
    birdNest = items.byName('Bird Nest');
    coalOre = items.byName('Coal Ore');
    ash = items.byName('Ash');
    rawShrimp = items.byName('Raw Shrimp');
    runeEssenceItem = items.byName('Rune Essence');
    copperOre = items.byName('Copper Ore');
  });

  group('consumeTicks', () {
    test('consuming ticks for 1 completion adds 1 item and 1x XP', () {
      var state = GlobalState.empty(testRegistries);

      final random = Random(0);
      // Start action
      state = state.startAction(normalTree, random: random);

      // Advance time by exactly 1 completion (30 ticks = 3 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random);
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);

      // Start action
      state = state.startAction(normalTree, random: random);

      // Advance time by exactly 5 completions (150 ticks = 15 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 150, random: random);
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // Start action
      state = state.startAction(normalTree, random: random);

      // Advance time by only 15 ticks (1.5 seconds, half completion)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 15, random: random);
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // Start action
      state = state.startAction(normalTree, random: random);

      // Advance time by 1.5 completions (45 ticks = 4.5 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 45, random: random);
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // Start action
      state = state.startAction(oakTree, random: random);

      // Advance time by exactly 2 completions (80 ticks = 8 seconds,
      // since Oak Tree takes 4 seconds per completion)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 80, random: random);
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // No activity started, try to consume ticks
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: random);
      state = builder.build();

      // Verify state unchanged
      expect(state.activeAction, null);
      expect(state.inventory.items.length, 0);
      expect(state.skillState(Skill.woodcutting).xp, 0);
    });

    test('consuming ticks for exactly 0 ticks does nothing', () {
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // Start action
      state = state.startAction(normalTree, random: random);

      // Consume 0 ticks
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 0, random: random);
      state = builder.build();

      // Verify no progress, no rewards, no XP
      expect(state.activeAction?.progressTicks, 0);
      expect(state.inventory.items.length, 0);
      expect(state.skillState(normalTree.skill).xp, 0);
    });

    test('consuming ticks handles activity with multiple rewards', () {
      // This test assumes we might have activities with multiple rewards
      // For now, we'll test that the rewards list is properly processed
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // Start action
      state = state.startAction(normalTree, random: random);

      // Advance by 3 completions
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 90, random: random);
      state = builder.build();

      // Verify all rewards are accumulated correctly
      expect(state.inventory.items.length, 1);
      expect(state.inventory.items.first.count, 3);
    });

    test('consuming ticks for 1 completion adds mastery XP', () {
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // Start action
      state = state.startAction(normalTree, random: random);

      // Verify initial mastery XP is 0
      expect(state.skillState(normalTree.skill).masteryPoolXp, 0);

      // Advance time by exactly 1 completion (30 ticks = 3 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random);
      state = builder.build();

      // Verify mastery XP increased
      final masteryXpAfterFirst = state
          .skillState(normalTree.skill)
          .masteryPoolXp;
      expect(masteryXpAfterFirst, 1);

      // Advance time by exactly 1 more completion
      final builder2 = StateUpdateBuilder(state);
      consumeTicks(builder2, 30, random: random);
      state = builder2.build();

      // Verify mastery XP increased again
      final masteryXpAfterSecond = state
          .skillState(normalTree.skill)
          .masteryPoolXp;
      expect(masteryXpAfterSecond, 2);
    });

    test('skill-level drops are processed on action completion', () {
      // Use seeded random to test drop rates deterministically
      final random = Random(12345);
      var state = GlobalState.empty(testRegistries);
      state = state.startAction(normalTree, random: random);

      // Consume enough ticks to drop at least one Bird Nest
      // With rate 0.005, we expect ~0.5 drops per 100 actions
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 3000, random: random); // 100 completions
      state = builder.build();

      // Verify action-level drop (Normal Logs) is present
      final items = state.inventory.items;
      expect(items.any((i) => i.item == normalLogs), true);
      final normalLogsCount = items
          .firstWhere((i) => i.item == normalLogs)
          .count;
      // We should have 100 logs because the mastery level is 0.
      expect(normalLogsCount, 100);

      // Verify skill-level drop (Bird Nest) dropped
      final birdNestCount = state.inventory.items
          .where((i) => i.item == birdNest)
          .fold(0, (sum, item) => sum + item.count);
      expect(birdNestCount, 1);
    });

    test(
      'action with output count > 1 correctly creates drops with that count',
      () {
        // Create an action with output count > 1
        const testAction = SkillAction(
          skill: Skill.woodcutting,
          name: 'Test Action',
          unlockLevel: 1,
          duration: Duration(seconds: 1),
          xp: 10,
          outputs: {'Normal Logs': 3}, // Count > 1
        );
        final random = Random(0);

        // Verify the rewards getter returns drops with the correct count
        final rewards = testAction.rewardsForMasteryLevel(1);
        expect(rewards.length, 1);
        expect(rewards.first.expectedItems['Normal Logs'], 3);

        // Test end-to-end: complete the action and verify correct items added
        var state = GlobalState.empty(testRegistries);
        state = state.startAction(testAction, random: random);

        final builder = StateUpdateBuilder(state);
        // Complete the action directly (bypassing consumeTicks which
        // requires registry lookup)
        completeAction(builder, testAction, random: random);
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
        // Start with Normal Logs in inventory
        var state = GlobalState.empty(testRegistries);
        final random = Random(0);
        state = state.copyWith(
          inventory: Inventory.fromItems(testItems, [
            ItemStack(normalLogs, count: 5),
          ]),
        );

        // Verify we have 5 Normal Logs
        expect(state.inventory.countOfItem(normalLogs), 5);

        // Start the firemaking action
        state = state.startAction(burnNormalLogs, random: random);

        // Advance time by exactly 1 completion (20 ticks = 2 seconds)
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, 20, random: random);
        state = builder.build();

        // Verify activity progress reset to 0 (ready for next completion)
        expect(state.activeAction?.progressTicks, 0);
        expect(state.activeAction?.name, burnNormalLogs.name);

        // Verify 1 Normal Log was consumed (5 - 1 = 4 remaining)
        expect(state.inventory.countOfItem(normalLogs), 4);

        // Verify 1x XP was gained
        expect(state.skillState(burnNormalLogs.skill).xp, burnNormalLogs.xp);

        // Verify skill-level drops (with seeded Random(0), neither dropped)
        final coalOreCount = state.inventory.countOfItem(coalOre);
        final ashCount = state.inventory.countOfItem(ash);
        expect(coalOreCount, 0);
        expect(ashCount, 0);

        // Verify changes object tracks the consumed item
        expect(builder.changes.inventoryChanges.counts['Normal Logs'], -1);
        expect(
          builder.changes.skillXpChanges.counts[burnNormalLogs.skill],
          burnNormalLogs.xp,
        );
      },
    );

    test('consuming ticks for multiple completions of action with inputs', () {
      // Start with 10 Normal Logs in inventory
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 10),
        ]),
      );

      // Start the firemaking action
      state = state.startAction(burnNormalLogs, random: random);

      // Advance time by exactly 3 completions (60 ticks = 6 seconds)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 60, random: random);
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
      const n = 5; // Try to run 5 times
      const nMinusOne = 4; // But only have inputs for 4 times

      // Start with N-1 Normal Logs in inventory (enough for 4 completions)
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: nMinusOne),
        ]),
      );

      // Verify we have N-1 logs
      expect(state.inventory.countOfItem(normalLogs), nMinusOne);

      // Start the firemaking action
      state = state.startAction(burnNormalLogs, random: random);

      // Advance time by enough ticks for N completions
      // (N * 20 ticks = 100 ticks for 5 completions)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, n * 20, random: random);
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
      final fillerItems = <ItemStack>[];
      for (var i = 0; i < 20; i++) {
        // Create unique test items to completely fill inventory
        fillerItems.add(ItemStack(Item.test('Test Item $i', gp: 1), count: 1));
      }

      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, fillerItems),
      );

      // Verify inventory is completely full
      expect(state.inventoryUsed, 20);
      expect(state.inventoryRemaining, 0);
      expect(state.isInventoryFull, true);

      // Start woodcutting Normal Tree (outputs Normal Logs - new item)
      // Action CAN start even with full inventory
      state = state.startAction(normalTree, random: random);
      expect(state.activeAction, isNotNull);

      // Complete one action - the output should be dropped
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random); // 1 completion
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      final items = <ItemStack>[
        ItemStack(normalLogs, count: 5), // Include Normal Logs
        ItemStack(oakLogs, count: 1),
        ItemStack(willowLogs, count: 1),
        ItemStack(teakLogs, count: 1),
        ItemStack(birdNest, count: 1),
        ItemStack(coalOre, count: 1),
        ItemStack(ash, count: 1),
        ItemStack(rawShrimp, count: 1),
      ];
      state = state.copyWith(inventory: Inventory.fromItems(testItems, items));

      // Verify inventory has all 8 items
      expect(state.inventoryUsed, 8);

      // Start woodcutting Normal Tree (outputs Normal Logs - can stack!)
      state = state.startAction(normalTree, random: random);

      // Multiple completions should work because Normal Logs can stack
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 90, random: random); // 3 completions
      state = builder.build();

      // Verify we got 3 more Normal Logs (5 + 3 = 8 total)
      expect(state.inventory.countOfItem(normalLogs), 8);
      expect(state.activeAction, isNotNull); // Action should still be active

      // Verify changes tracked the 3 Normal Logs added
      expect(builder.changes.inventoryChanges.counts['Normal Logs'], 3);
    });

    test('TimeAway tracks dropped items when inventory is full', () {
      // Create test items to fill inventory to capacity
      final fillerItems = <ItemStack>[];
      for (var i = 0; i < 20; i++) {
        fillerItems.add(ItemStack(Item.test('Test Item $i', gp: 1), count: 1));
      }

      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, fillerItems),
      );
      final random = Random(0);
      state = state.startAction(normalTree, random: random);

      // Use consumeManyTicks to simulate time away
      final (timeAway, newState) = consumeManyTicks(
        state,
        90, // 3 completions worth of ticks
        random: random,
      );

      // Verify action stopped after first completion (items were dropped)
      expect(newState.activeAction, isNull);

      // Verify TimeAway has the dropped items
      expect(timeAway.changes.droppedItems.counts['Normal Logs'], 1);

      // No Normal Logs in inventory
      expect(newState.inventory.countOfItem(normalLogs), 0);

      // Verify TimeAway has correct duration and skill
      expect(timeAway.activeSkill, Skill.woodcutting);
      expect(timeAway.duration.inMilliseconds, 9000);
    });

    test('Changes tracks skill level gains', () {
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      // Start with level 1 (0 XP)
      expect(levelForXp(state.skillState(Skill.woodcutting).xp), 1);

      state = state.startAction(normalTree, random: random);

      // Complete enough actions to level up
      // Level 2 requires 83 XP, normalTree gives 10 XP per completion
      // So we need 9 completions (9 * 10 = 90 XP)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30 * 9, random: random); // 9 completions
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      state = state.startAction(normalTree, random: random);

      // Complete enough actions to gain multiple levels
      // Level 3 requires 174 XP, normalTree gives 10 XP per completion
      // So we need 18 completions (18 * 10 = 180 XP)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30 * 18, random: random); // 18 completions
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      state = state.startAction(normalTree, random: random);

      // Complete enough ticks to level up
      final (timeAway, newState) = consumeManyTicks(
        state,
        30 * 9, // 9 completions = 90 XP = level 2
        random: random,
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
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);
      state = state.startAction(runeEssence, random: random);

      // Rune Essence: 3 second action (30 ticks), 1 second respawn (10 ticks)
      // HP at mastery level 1: 5 + 1 = 6 HP
      // HP regen: 1 HP per 100 ticks (10 seconds)
      //
      // With the new architecture, background healing happens in parallel with
      // the foreground mining action. This means the node heals while mining,
      // allowing for more swings before depletion than the old implementation.

      final ticks = ticksFromDuration(const Duration(seconds: 30));
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, ticks, random: random);
      state = builder.build();

      // In 30s, we should swing 10 times.
      // However the node runs out of hp after 6 swings (18s) without healing
      // but if we account for healing it's healed twice during 7 swings (21s)
      // so we actually get 8 swings, before healing (1s) and then swinging
      // again.
      // So 18 seems low?  But the right ballpark.  This needs more debugging.
      final runeEssenceCount = state.inventory.countOfItem(runeEssenceItem);
      expect(runeEssenceCount, 18, reason: 'Should mine 18 over 10s');

      // Verify action is still running
      expect(state.activeAction, isNotNull);
      expect(state.activeAction!.name, runeEssence.name);
    });

    test('mining action resumes after respawn across multiple tick cycles', () {
      // This tests the specific bug where the action would stop when a node
      // depleted and the respawn timer hadn't completed in the same tick cycle.
      //
      // With the new parallel healing architecture, the node heals while being
      // mined. Copper has 6 HP and heals 1 HP every 100 ticks. At 180 ticks,
      // the node has healed once (at tick 130), so it's at 5 HP lost, not
      // depleted.
      //
      // To test depletion/respawn behavior, we need to mine longer to actually
      // deplete the node, or start with a pre-damaged node.

      // Start with a node that's already at 5 HP lost (1 HP remaining)
      // so that the next completion will deplete it
      var state = GlobalState.test(
        testRegistries,
        actionStates: const {
          'Copper': ActionState(
            masteryXp: 0,
            mining: MiningState(
              totalHpLost: 5,
              hpRegenTicksRemaining: 100, // Full countdown until next heal
            ),
          ),
        },
      );
      final random = Random(0);
      state = state.startAction(copper, random: random);

      // Copper: 3 second action (30 ticks), 5 second respawn (50 ticks)
      // HP at mastery level 1: 5 + 1 = 6 HP
      // Node starts with 5 HP lost, so 1 HP remaining

      // Mine once to deplete the node (30 ticks)
      var builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random);
      state = builder.build();

      // Verify we got 1 copper and node is depleted
      expect(state.inventory.countOfItem(copperOre), 1);
      final miningState =
          state.actionState(copper.name).mining ?? const MiningState.empty();
      expect(miningState.isDepleted, true);

      // Critical: Action should still be active even though node is depleted
      expect(state.activeAction, isNotNull);
      expect(state.activeAction!.name, copper.name);

      // Now simulate a few more tick cycles while node is respawning
      // Respawn takes 50 ticks, let's do 20 ticks at a time
      builder = StateUpdateBuilder(state);
      consumeTicks(builder, 20, random: random);
      state = builder.build();

      // Still depleted, still active
      expect(
        (state.actionState(copper.name).mining ?? const MiningState.empty())
            .isDepleted,
        true,
      );
      expect(state.activeAction, isNotNull);
      expect(state.inventory.countOfItem(copperOre), 1); // No new copper yet

      // Another 20 ticks (40 total, still 10 ticks to go)
      builder = StateUpdateBuilder(state);
      consumeTicks(builder, 20, random: random);
      state = builder.build();

      expect(
        (state.actionState(copper.name).mining ?? const MiningState.empty())
            .isDepleted,
        true,
      );
      expect(state.activeAction, isNotNull);

      // Final 20 ticks - respawn completes (10 ticks) + 10 ticks toward next
      builder = StateUpdateBuilder(state);
      consumeTicks(builder, 20, random: random);
      state = builder.build();

      // Node should no longer be depleted
      expect(
        (state.actionState(copper.name).mining ?? const MiningState.empty())
            .isDepleted,
        false,
      );
      // Action should still be running
      expect(state.activeAction, isNotNull);
      expect(state.activeAction!.name, copper.name);

      // Complete another mining action (need 30 more ticks since action
      // restarted when respawn completed, but we only have 10 ticks of
      // progress from the 20 tick batch above)
      builder = StateUpdateBuilder(state);
      consumeTicks(
        builder,
        20,
        random: random,
      ); // 10 + 20 = 30 ticks for completion
      state = builder.build();

      // Should have 2 copper now (1 before + 1 after respawn)
      expect(state.inventory.countOfItem(copperOre), 2);
      expect(state.activeAction, isNotNull);
    });

    test('concurrent systems: woodcutting while mining nodes heal/respawn', () {
      // This test verifies that multiple systems run concurrently:
      // 1. Active woodcutting action produces logs
      // 2. Non-active mining node mid-respawn continues respawn countdown
      // 3. Non-active mining node with damage continues healing
      //
      // This simulates what UpdateActivityProgressAction does in the game.

      // Create initial state with:
      // - Woodcutting as active action
      // - Copper node mid-respawn (30 ticks remaining out of 50)
      // - Rune Essence node damaged (3 HP lost) and healing
      var state = GlobalState.test(
        testRegistries,
        actionStates: const {
          // Copper: depleted, mid-respawn with 30 ticks remaining
          'Copper': ActionState(
            masteryXp: 0,
            mining: MiningState(
              totalHpLost: 6, // Fully depleted (6 HP lost = 0 HP remaining)
              respawnTicksRemaining: 30, // 30 ticks until respawn (3 seconds)
            ),
          ),
          // Rune Essence: damaged but not depleted, healing
          'Rune Essence': ActionState(
            masteryXp: 0,
            mining: MiningState(
              totalHpLost: 3, // 3 HP lost, 3 HP remaining (out of 6)
              hpRegenTicksRemaining: 50, // 50 ticks until next heal
            ),
          ),
        },
      );
      final random = Random(0);

      // Start woodcutting
      state = state.startAction(normalTree, random: random);

      // Helper that uses the same logic as UpdateActivityProgressAction
      GlobalState applyTicks(GlobalState state, Tick ticks) {
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, ticks, random: random);
        return builder.build();
      }

      // --- Phase 1: 20 ticks ---
      // - Woodcutting: 20/30 ticks toward completion (not done yet)
      // - Copper: respawn 30 -> 10 ticks remaining (still depleted)
      // - Rune Essence: heal countdown 50 -> 30 ticks (no heal yet)
      state = applyTicks(state, 20);

      expect(
        state.activeAction?.name,
        normalTree.name,
        reason: 'Active action should still be woodcutting',
      );
      expect(
        state.activeAction?.progressTicks,
        20,
        reason: 'Should have 20 ticks progress toward woodcutting',
      );
      expect(
        state.inventory.countOfItem(normalLogs),
        0,
        reason: 'No logs yet - woodcutting not complete',
      );

      final copperMiningPhase1 =
          state.actionState(copper.name).mining ?? const MiningState.empty();
      expect(
        copperMiningPhase1.isDepleted,
        true,
        reason: 'Copper should still be depleted',
      );
      expect(
        copperMiningPhase1.respawnTicksRemaining,
        10,
        reason: 'Copper should have 10 ticks remaining until respawn',
      );

      final runeMiningPhase1 =
          state.actionState(runeEssence.name).mining ??
          const MiningState.empty();
      expect(
        runeMiningPhase1.totalHpLost,
        3,
        reason: 'Rune Essence should still have 3 HP lost (no heal yet)',
      );
      expect(
        runeMiningPhase1.hpRegenTicksRemaining,
        30,
        reason: 'Rune Essence should have 30 ticks until next heal',
      );

      // --- Phase 2: 30 more ticks (50 total) ---
      // - Woodcutting: completes at tick 30, restarts, at 20/30 again
      // - Copper: respawn completes at tick 10, node available
      // - Rune Essence: heal triggers at exactly tick 30, HP 3->2 lost,
      //   reset to 100 ticks until next heal (no leftover ticks)
      state = applyTicks(state, 30);

      expect(
        state.activeAction?.name,
        normalTree.name,
        reason: 'Active action should still be woodcutting',
      );
      expect(
        state.inventory.countOfItem(normalLogs),
        1,
        reason: 'Should have 1 log from first woodcutting completion',
      );

      final copperMiningPhase2 =
          state.actionState(copper.name).mining ?? const MiningState.empty();
      expect(
        copperMiningPhase2.isDepleted,
        false,
        reason: 'Copper should have respawned and no longer be depleted',
      );
      expect(
        copperMiningPhase2.totalHpLost,
        0,
        reason: 'Copper should be at full HP after respawn',
      );

      final runeMiningPhase2 =
          state.actionState(runeEssence.name).mining ??
          const MiningState.empty();
      expect(
        runeMiningPhase2.totalHpLost,
        2,
        reason: 'Rune Essence should have healed 1 HP (3->2 lost)',
      );
      expect(
        runeMiningPhase2.hpRegenTicksRemaining,
        100,
        reason:
            'Rune Essence: heal consumed exactly 30 ticks, '
            'reset to 100 ticks until next heal',
      );

      // --- Phase 3: 100 more ticks (150 total) ---
      // - Woodcutting: had 20 progress, needs 10 to complete -> log 2
      //   then 90 ticks remaining = 3 more completions -> logs 3, 4, 5
      //   Total: 5 logs
      // - Copper: stays at full HP (not being mined)
      // - Rune Essence: heals 1 more HP at tick 100, HP 2->1 lost
      state = applyTicks(state, 100);

      expect(state.activeAction?.name, normalTree.name);
      expect(
        state.inventory.countOfItem(normalLogs),
        5,
        reason: 'Should have 5 logs total (1 + 1 partial + 3 full)',
      );

      final copperMiningPhase3 =
          state.actionState(copper.name).mining ?? const MiningState.empty();
      expect(
        copperMiningPhase3.isDepleted,
        false,
        reason: 'Copper should still be available',
      );
      expect(copperMiningPhase3.totalHpLost, 0);

      final runeMiningPhase3 =
          state.actionState(runeEssence.name).mining ??
          const MiningState.empty();
      expect(
        runeMiningPhase3.totalHpLost,
        1,
        reason: 'Rune Essence should have healed another HP (2->1 lost)',
      );

      // --- Phase 4: 100 more ticks (250 total) ---
      // - Woodcutting: had 10 progress, needs 20 to complete -> log 6
      //   then 80 ticks remaining = 2 more completions -> logs 7, 8
      //   plus 20 progress toward next
      //   Total: 8 logs
      // - Rune Essence: heals final HP at tick 100 (1->0 lost)
      state = applyTicks(state, 100);

      expect(
        state.inventory.countOfItem(normalLogs),
        8,
        reason: 'Should have 8 logs total',
      );

      final runeMiningPhase4 =
          state.actionState(runeEssence.name).mining ??
          const MiningState.empty();
      expect(
        runeMiningPhase4.totalHpLost,
        0,
        reason: 'Rune Essence should be fully healed',
      );
      expect(
        runeMiningPhase4.hpRegenTicksRemaining,
        0,
        reason: 'No regen needed when at full HP',
      );

      // Verify the active action stayed woodcutting throughout
      expect(
        state.activeAction?.name,
        normalTree.name,
        reason: 'Woodcutting should still be the active action',
      );
    });

    test('background actions run without foreground action', () {
      // Start with a damaged mining node but no active action
      var state = GlobalState.test(
        testRegistries,
        actionStates: const {
          'Copper': ActionState(
            masteryXp: 0,
            mining: MiningState(
              totalHpLost: 3, // 3 HP lost
              hpRegenTicksRemaining: 50, // 50 ticks until next heal
            ),
          ),
        },
      );
      final random = Random(0);
      // Verify no active action
      expect(state.activeAction, isNull);

      // Process 60 ticks (enough for 1 heal at tick 50, partial progress)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 60, random: random);
      state = builder.build();

      // Verify node healed (should have healed once at tick 50)
      final miningState =
          state.actionState('Copper').mining ?? const MiningState.empty();
      expect(
        miningState.totalHpLost,
        2,
        reason: 'Node should have healed 1 HP (3 -> 2)',
      );
      // 10 ticks of partial progress toward next heal (100 - 10 = 90 remaining)
      expect(
        miningState.hpRegenTicksRemaining,
        90,
        reason: 'Should have 90 ticks until next heal',
      );
    });

    test('background respawn runs without foreground action', () {
      // Start with a depleted mining node but no active action
      var state = GlobalState.test(
        testRegistries,
        actionStates: const {
          'Copper': ActionState(
            masteryXp: 0,
            mining: MiningState(
              totalHpLost: 6,
              respawnTicksRemaining: 30, // 30 ticks until respawn
            ),
          ),
        },
      );
      final random = Random(0);
      // Verify no active action and node is depleted
      expect(state.activeAction, isNull);
      expect(state.actionState('Copper').mining?.isDepleted, true);

      // Process enough ticks to respawn
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 50, random: random);
      state = builder.build();

      // Verify node respawned
      final miningState =
          state.actionState('Copper').mining ?? const MiningState.empty();
      expect(
        miningState.isDepleted,
        false,
        reason: 'Node should have respawned',
      );
      expect(
        miningState.totalHpLost,
        0,
        reason: 'Node should be at full HP after respawn',
      );
    });

    test('multiple mining nodes heal in parallel', () {
      // Start with two damaged mining nodes
      var state = GlobalState.test(
        testRegistries,
        actionStates: const {
          'Copper': ActionState(
            masteryXp: 0,
            mining: MiningState(totalHpLost: 2, hpRegenTicksRemaining: 50),
          ),
          'Rune Essence': ActionState(
            masteryXp: 0,
            mining: MiningState(totalHpLost: 3, hpRegenTicksRemaining: 80),
          ),
        },
      );
      final random = Random(0);
      // Do woodcutting while both heal
      state = state.startAction(normalTree, random: random);

      // Process 200 ticks - enough for woodcutting completions and heals
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 200, random: random);
      state = builder.build();

      // Verify woodcutting produced logs
      expect(state.inventory.countOfItem(normalLogs), 6);

      // Verify both nodes healed
      final copperMining =
          state.actionState('Copper').mining ?? const MiningState.empty();
      final runeMining =
          state.actionState('Rune Essence').mining ?? const MiningState.empty();

      expect(copperMining.totalHpLost, 0);
      expect(runeMining.totalHpLost, 1);
    });

    test('combat action processes ticks with monster name as action name', () {
      // Get the Plant combat action
      final plantAction = combatActionByName('Plant');
      final random = Random(0);
      // Start combat
      var state = GlobalState.empty(testRegistries);
      state = state.startAction(plantAction, random: random);

      // Verify the active action name is "Plant", not "Combat"
      expect(state.activeAction?.name, 'Plant');

      // Verify combat state is stored under "Plant"
      final actionState = state.actionState('Plant');
      expect(actionState.combat, isNotNull);
      expect(actionState.combat!.monsterName, 'Plant');

      // Process some ticks - should not throw
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: random);
      state = builder.build();

      // Combat should still be active (player shouldn't have died in 100 ticks)
      expect(state.activeAction?.name, 'Plant');
    });

    test('combat action with mining background heals node', () {
      final plantAction = combatActionByName('Plant');
      final random = Random(0);
      // Start with damaged mining node
      var state = GlobalState.test(
        testRegistries,
        actionStates: const {
          'Copper': ActionState(
            masteryXp: 0,
            mining: MiningState(totalHpLost: 2, hpRegenTicksRemaining: 50),
          ),
        },
      );

      // Start combat
      state = state.startAction(plantAction, random: random);

      // Process 200 ticks - enough for healing
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 200, random: random);
      state = builder.build();

      // Verify mining node healed during combat
      final copperMining =
          state.actionState('Copper').mining ?? const MiningState.empty();
      expect(copperMining.totalHpLost, 0);
    });

    test('mining hit and heal happen in predictable order', () {
      // Set up a scenario where heal completes in same tick batch as mining
      // hit. Copper: 3 second action (30 ticks). HP regen: 10 seconds (100
      // ticks) per HP.
      //
      // Start with node at 1 HP lost, and 30 ticks until heal.
      // After 30 ticks: mining completes (hit), heal also completes.
      // With parallel architecture: background heal runs first (each
      // iteration), then foreground hit runs.
      // Expected result: heal first (1 HP -> 0 HP lost), then hit (0 HP -> 1 HP
      // lost).
      // Net result: still 1 HP lost after 30 ticks.

      var state = GlobalState.test(
        testRegistries,
        actionStates: const {
          'Copper': ActionState(
            masteryXp: 0,
            mining: MiningState(
              totalHpLost: 1,
              hpRegenTicksRemaining: 30, // Heal completes at tick 30
            ),
          ),
        },
      );
      final random = Random(0);

      // Start mining copper
      state = state.startAction(copper, random: random);
      // Process exactly 30 ticks (mining completes + heal completes)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random);
      state = builder.build();

      // Verify we got copper ore (mining completed)
      expect(state.inventory.countOfItem(copperOre), 1);

      // Verify HP state. With parallel architecture:
      // - Background healing runs each foreground iteration
      // - Heal completes at tick 30, reducing 1 HP lost to 0
      // - Mining hit then adds 1 HP lost
      // Net effect: still 1 HP lost
      final miningState =
          state.actionState(copper.name).mining ?? const MiningState.empty();
      expect(
        miningState.totalHpLost,
        1,
        reason: 'Should have 1 HP lost: heal reduced to 0, then hit added 1',
      );

      // Verify action is still running
      expect(state.activeAction, isNotNull);
      expect(state.activeAction!.name, copper.name);
    });

    test('completes activity and adds toast', () {
      final normalTree = testActions.byName('Normal Tree') as SkillAction;
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);

      // Start activity
      state = state.startAction(normalTree, random: random);

      // Advance time by 3 seconds (30 ticks)
      // consumeTicks takes state and ticks
      // 3s = 3000ms. tickDuration = 100ms. So 30 ticks.
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random);
      state = builder.build();

      // Verify activity completed (progress resets on completion)
      expect(state.activeAction?.progressTicks, 0);

      // Verify rewards
      final items = state.inventory.items;
      expect(items.length, 1);
      expect(items.first.item.name, 'Normal Logs');
      expect(items.first.count, 1);

      // Verify XP
      expect(state.skillState(normalTree.skill).xp, normalTree.xp);
    });
  });

  group('consumeTicks vs consumeTicksUntil', () {
    test('consumeTicks always consumes all requested ticks', () {
      var state = GlobalState.empty(testRegistries);
      final random = Random(42);

      // Start woodcutting Normal Tree (30 ticks per action, 10 XP each)
      state = state.startAction(
        testActions.skillActionByName('Normal Tree'),
        random: random,
      );

      // Request 100 ticks - should consume all 100 even though
      // we'd hit 10 XP after just 30 ticks
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: random);

      // Should consume exactly 100 ticks
      expect(builder.ticksElapsed, 100);
    });

    test('consumeTicksUntil stops when condition is met', () {
      var state = GlobalState.empty(testRegistries);
      final random = Random(42);

      // Start woodcutting Normal Tree (30 ticks per action, 10 XP each)
      state = state.startAction(
        testActions.skillActionByName('Normal Tree'),
        random: random,
      );

      // Request up to 10000 ticks, but stop when we have 10 XP
      final builder = StateUpdateBuilder(state);
      consumeTicksUntil(
        builder,
        random: random,
        stopCondition: (s) => s.skillState(Skill.woodcutting).xp >= 10,
        maxTicks: 10000,
      );

      // Should stop after ~30 ticks (1 action), not consume all 10000
      expect(builder.ticksElapsed, lessThan(100));
      expect(builder.ticksElapsed, greaterThanOrEqualTo(30));

      // Verify we actually have the XP
      expect(
        builder.state.skillState(Skill.woodcutting).xp,
        greaterThanOrEqualTo(10),
      );
    });
  });
}
