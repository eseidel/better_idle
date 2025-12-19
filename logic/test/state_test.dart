import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  final normalLogs = itemRegistry.byName('Normal Logs');
  final oakLogs = itemRegistry.byName('Oak Logs');
  final birdNest = itemRegistry.byName('Bird Nest');
  final shrimp = itemRegistry.byName('Shrimp');
  final lobster = itemRegistry.byName('Lobster');

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

  group('Inventory.canAdd', () {
    test('returns true when inventory has existing stack of item', () {
      final inventory = Inventory.fromItems([
        ItemStack(normalLogs, count: 5),
        ItemStack(oakLogs, count: 3),
      ]);
      // Can add more normal logs even if at capacity
      expect(inventory.canAdd(normalLogs, capacity: 2), isTrue);
    });

    test('returns true when inventory has room for new item', () {
      final inventory = Inventory.fromItems([ItemStack(normalLogs, count: 5)]);
      // Can add oak logs because we have room (1 slot used, capacity 2)
      expect(inventory.canAdd(oakLogs, capacity: 2), isTrue);
    });

    test('returns false when inventory is full with different items', () {
      final inventory = Inventory.fromItems([
        ItemStack(normalLogs, count: 5),
        ItemStack(oakLogs, count: 3),
      ]);
      // Cannot add bird nest because inventory is full (2 slots, capacity 2)
      expect(inventory.canAdd(birdNest, capacity: 2), isFalse);
    });

    test('returns true for empty inventory', () {
      const inventory = Inventory.empty();
      expect(inventory.canAdd(normalLogs, capacity: 20), isTrue);
    });
  });

  group('GlobalState.unequipFood', () {
    test('moves food from equipment slot to inventory', () {
      // Start with food equipped and empty inventory
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(equipment: equipment);

      final newState = state.unequipFood(0);

      // Food should be removed from equipment
      expect(newState.equipment.foodSlots[0], isNull);
      // Food should be in inventory
      expect(newState.inventory.countOfItem(shrimp), 10);
    });

    test('stacks with existing inventory items', () {
      // Start with some shrimp in inventory and more equipped
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        inventory: Inventory.fromItems([ItemStack(shrimp, count: 5)]),
        equipment: equipment,
      );

      final newState = state.unequipFood(0);

      // Food should be removed from equipment
      expect(newState.equipment.foodSlots[0], isNull);
      // Food should stack in inventory (5 + 10 = 15)
      expect(newState.inventory.countOfItem(shrimp), 15);
    });

    test('throws ArgumentError when slot is empty', () {
      final state = GlobalState.test();
      expect(() => state.unequipFood(0), throwsArgumentError);
    });

    test('throws ArgumentError when slot index is invalid', () {
      final state = GlobalState.test();
      expect(() => state.unequipFood(-1), throwsArgumentError);
      expect(() => state.unequipFood(3), throwsArgumentError);
    });

    test('throws StateError when inventory is full', () {
      // Create inventory at capacity with different items
      final items = <ItemStack>[];
      for (var i = 0; i < initialBankSlots; i++) {
        items.add(ItemStack(Item('Test Item $i', gp: 1), count: 1));
      }
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        inventory: Inventory.fromItems(items),
        equipment: equipment,
      );

      expect(() => state.unequipFood(0), throwsStateError);
    });

    test('succeeds when inventory full but has same item type', () {
      // Create inventory at capacity but with shrimp as one of the items
      final items = <ItemStack>[ItemStack(shrimp, count: 5)];
      for (var i = 1; i < initialBankSlots; i++) {
        items.add(ItemStack(Item('Test Item $i', gp: 1), count: 1));
      }
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        inventory: Inventory.fromItems(items),
        equipment: equipment,
      );

      // Should succeed because shrimp can stack
      final newState = state.unequipFood(0);
      expect(newState.inventory.countOfItem(shrimp), 15);
      expect(newState.equipment.foodSlots[0], isNull);
    });

    test('can unequip from any slot', () {
      final equipment = Equipment(
        foodSlots: [
          ItemStack(shrimp, count: 5),
          ItemStack(lobster, count: 3),
          null,
        ],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(equipment: equipment);

      // Unequip from slot 1
      final newState = state.unequipFood(1);

      expect(newState.equipment.foodSlots[0]?.item, shrimp);
      expect(newState.equipment.foodSlots[1], isNull);
      expect(newState.inventory.countOfItem(lobster), 3);
    });
  });

  group('rollDurationWithModifiers', () {
    test('woodcutting mastery 99 applies 0.2s flat reduction', () {
      final normalTree = actionRegistry.skillActionByName('Normal Tree');
      // Normal Tree has 3 second duration = 30 ticks
      expect(normalTree.minDuration, const Duration(seconds: 3));

      final random = Random(42);

      // State with no mastery - should get full 30 ticks
      final stateNoMastery = GlobalState.test();
      final ticksNoMastery = stateNoMastery.rollDurationWithModifiers(
        normalTree,
        random,
      );
      expect(ticksNoMastery, 30);

      // State with mastery level 98 (just below threshold) - should get full 30 ticks
      final xpForLevel98 = startXpForLevel(98);
      final stateMastery98 = GlobalState.test(
        actionStates: {'Normal Tree': ActionState(masteryXp: xpForLevel98)},
      );
      expect(stateMastery98.actionState('Normal Tree').masteryLevel, 98);
      final ticksMastery98 = stateMastery98.rollDurationWithModifiers(
        normalTree,
        random,
      );
      expect(ticksMastery98, 30);

      // State with mastery level 99 - should get 28 ticks (30 - 2 = 0.2s reduction)
      final xpForLevel99 = startXpForLevel(99);
      final stateMastery99 = GlobalState.test(
        actionStates: {'Normal Tree': ActionState(masteryXp: xpForLevel99)},
      );
      expect(stateMastery99.actionState('Normal Tree').masteryLevel, 99);
      final ticksMastery99 = stateMastery99.rollDurationWithModifiers(
        normalTree,
        random,
      );
      expect(ticksMastery99, 28); // 30 ticks - 2 ticks = 28 ticks
    });

    test('woodcutting mastery 99 combines with shop upgrades', () {
      final normalTree = actionRegistry.skillActionByName('Normal Tree');
      final random = Random(42);

      // State with mastery 99 AND Iron Axe (5% reduction)
      // Base: 30 ticks
      // After 5% reduction: 30 * 0.95 = 28.5 -> 29 ticks (rounded)
      // After flat -2: 29 - 2 = 27 ticks
      final xpForLevel99 = startXpForLevel(99);
      final stateWithBoth = GlobalState.test(
        actionStates: {'Normal Tree': ActionState(masteryXp: xpForLevel99)},
        shop: const ShopState(bankSlots: 0, axeLevel: 1), // Iron Axe
      );
      expect(stateWithBoth.actionState('Normal Tree').masteryLevel, 99);

      final ticksWithBoth = stateWithBoth.rollDurationWithModifiers(
        normalTree,
        random,
      );
      // 30 * 0.95 = 28.5, rounded = 29 (but we apply percent first in combined)
      // Actually: combined modifier has percent=-0.05, flat=-2
      // So: 30 * (1 + -0.05) + -2 = 30 * 0.95 - 2 = 28.5 - 2 = 26.5 -> 27
      expect(ticksWithBoth, 27);
    });
  });
}
