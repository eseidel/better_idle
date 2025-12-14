import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  final normalLogs = itemRegistry.byName('Normal Logs');
  final oakLogs = itemRegistry.byName('Oak Logs');
  final birdNest = itemRegistry.byName('Bird Nest');

  test('GlobalState toJson/fromJson round-trip', () {
    // Create a state with TimeAway data
    final originalState = GlobalState.test(
      inventory: Inventory.fromItems([
        ItemStack(normalLogs, count: 5),
        ItemStack(oakLogs, count: 3),
      ]),
      activeAction: const ActiveAction(
        name: 'Normal Tree',
        remainingTicks: 15,
        totalTicks: 30,
      ),
      skillStates: const {
        Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 50),
      },
      actionStates: const {
        'Normal Tree': ActionState(masteryXp: 25),
        'Oak Tree': ActionState(masteryXp: 10),
      },
      updatedAt: DateTime(2024, 1, 1, 12),
      timeAway: TimeAway(
        startTime: DateTime(2024, 1, 1, 11, 59, 30),
        endTime: DateTime(2024, 1, 1, 12),
        activeSkill: Skill.woodcutting,
        changes: const Changes(
          inventoryChanges: Counts<String>(
            counts: {'Normal Logs': 10, 'Oak Logs': 5},
          ),
          skillXpChanges: Counts<Skill>(counts: {Skill.woodcutting: 50}),
          droppedItems: Counts<String>.empty(),
          skillLevelChanges: LevelChanges.empty(),
        ),
        masteryLevels: const {'Normal Tree': 2},
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
    expect(loaded.skillStates[Skill.woodcutting]?.masteryPoolXp, 50);

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
    final stateWithAction = GlobalState.test(
      inventory: Inventory.fromItems([ItemStack(normalLogs, count: 5)]),
      activeAction: const ActiveAction(
        name: 'Normal Tree',
        remainingTicks: 15,
        totalTicks: 30,
      ),
      skillStates: const {
        Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 50),
      },
      actionStates: const {'Normal Tree': ActionState(masteryXp: 25)},
      updatedAt: DateTime(2024, 1, 1, 12),
    );

    // Clear the action
    final clearedState = stateWithAction.clearAction();

    // Verify activeAction is null
    expect(clearedState.activeAction, isNull);
  });

  test('GlobalState clearTimeAway clears timeAway', () {
    // Create a state with timeAway
    final stateWithTimeAway = GlobalState.test(
      inventory: Inventory.fromItems([ItemStack(normalLogs, count: 5)]),
      activeAction: const ActiveAction(
        name: 'Normal Tree',
        remainingTicks: 15,
        totalTicks: 30,
      ),
      skillStates: const {
        Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 50),
      },
      actionStates: const {'Normal Tree': ActionState(masteryXp: 25)},
      updatedAt: DateTime(2024, 1, 1, 12),
      timeAway: TimeAway(
        startTime: DateTime(2024, 1, 1, 11, 59, 30),
        endTime: DateTime(2024, 1, 1, 12),
        activeSkill: Skill.woodcutting,
        changes: const Changes(
          inventoryChanges: Counts<String>(counts: {'Normal Logs': 10}),
          skillXpChanges: Counts<Skill>(counts: {Skill.woodcutting: 50}),
          droppedItems: Counts<String>.empty(),
          skillLevelChanges: LevelChanges.empty(),
        ),
        masteryLevels: const {'Normal Tree': 2},
      ),
    );

    // Clear the timeAway
    final clearedState = stateWithTimeAway.clearTimeAway();

    // Verify timeAway is null
    expect(clearedState.timeAway, isNull);
  });

  test('GlobalState sellItem removes items and adds GP', () {
    // Create a state with items and some existing GP
    final initialState = GlobalState.test(
      inventory: Inventory.fromItems([
        ItemStack(normalLogs, count: 10),
        ItemStack(oakLogs, count: 5),
        ItemStack(birdNest, count: 2),
      ]),
      updatedAt: DateTime(2024, 1, 1, 12),
      gp: 100,
    );

    // Sell some normal logs (partial quantity)
    final afterSellingLogs = initialState.sellItem(
      ItemStack(normalLogs, count: 3),
    );

    // Verify items were removed
    expect(afterSellingLogs.inventory.countOfItem(normalLogs), 7);
    expect(afterSellingLogs.inventory.countOfItem(oakLogs), 5);
    expect(afterSellingLogs.inventory.countOfItem(birdNest), 2);

    // Verify GP was added correctly (3 * 1 = 3, plus existing 100 = 103)
    expect(afterSellingLogs.gp, 103);

    // Sell all oak logs
    final afterSellingOak = afterSellingLogs.sellItem(
      ItemStack(oakLogs, count: 5),
    );

    // Verify oak logs are completely removed
    expect(afterSellingOak.inventory.countOfItem(oakLogs), 0);
    expect(
      afterSellingOak.inventory.items.length,
      2,
    ); // Only normal logs and bird nest remain

    // Verify GP was added correctly (5 * 5 = 25, plus existing 103 = 128)
    expect(afterSellingOak.gp, 128);

    // Sell a bird nest (high value item)
    final afterSellingNest = afterSellingOak.sellItem(
      ItemStack(birdNest, count: 1),
    );

    // Verify bird nest count decreased
    expect(afterSellingNest.inventory.countOfItem(birdNest), 1);

    // Verify GP was added correctly (1 * 350 = 350, plus existing 128 = 478)
    expect(afterSellingNest.gp, 478);
  });

  test('GlobalState sellItem with zero GP', () {
    // Test selling when starting with zero GP
    final initialState = GlobalState.test(
      inventory: Inventory.fromItems([ItemStack(normalLogs, count: 5)]),
      updatedAt: DateTime(2024, 1, 1, 12),
    );

    final afterSelling = initialState.sellItem(ItemStack(normalLogs, count: 5));

    // Verify all items were removed
    expect(afterSelling.inventory.countOfItem(normalLogs), 0);
    expect(afterSelling.inventory.items.length, 0);

    // Verify GP was added correctly (5 * 1 = 5)
    expect(afterSelling.gp, 5);
  });
}
