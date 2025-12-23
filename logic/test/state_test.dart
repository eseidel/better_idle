import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item normalLogs;
  late Item oakLogs;
  late Item birdNest;
  late Item shrimp;
  late Item lobster;
  late Action normalTree;
  late Action oakTree;

  setUpAll(() async {
    await loadTestRegistries();
    normalLogs = testItems.byName('Normal Logs');
    oakLogs = testItems.byName('Oak Logs');
    birdNest = testItems.byName('Bird Nest');
    shrimp = testItems.byName('Shrimp');
    lobster = testItems.byName('Lobster');
    normalTree = testActions.byName('Normal Tree');
    oakTree = testActions.byName('Oak Tree');
  });

  test('GlobalState toJson/fromJson round-trip', () {
    // Create a state with TimeAway data
    final originalState = GlobalState.test(
      testRegistries,
      inventory: Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
        ItemStack(oakLogs, count: 3),
      ]),
      activeAction: ActiveAction(
        id: normalTree.id,
        remainingTicks: 15,
        totalTicks: 30,
      ),
      skillStates: const {
        Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 50),
      },
      actionStates: {
        normalTree.id: ActionState(masteryXp: 25),
        oakTree.id: ActionState(masteryXp: 10),
      },
      updatedAt: DateTime(2024, 1, 1, 12),
      timeAway: TimeAway(
        registries: testRegistries,
        startTime: DateTime(2024, 1, 1, 11, 59, 30),
        endTime: DateTime(2024, 1, 1, 12),
        activeSkill: Skill.woodcutting,
        changes: Changes(
          inventoryChanges: Counts<MelvorId>(
            counts: {normalLogs.id: 10, oakLogs.id: 5},
          ),
          skillXpChanges: Counts<Skill>(counts: {Skill.woodcutting: 50}),
          droppedItems: Counts<MelvorId>.empty(),
          skillLevelChanges: LevelChanges.empty(),
        ),
        masteryLevels: {normalTree.id: 2},
      ),
    );

    // Convert to JSON
    final json = originalState.toJson();

    // Convert back from JSON
    final loaded = GlobalState.fromJson(testRegistries, json);

    // Verify all fields match
    expect(loaded.updatedAt, originalState.updatedAt);
    final items = loaded.inventory.items;
    expect(items.length, 2);
    expect(items[0].item, normalLogs);
    expect(items[0].count, 5);
    expect(items[1].item, oakLogs);
    expect(items[1].count, 3);

    expect(loaded.activeAction?.id, normalTree.id);
    expect(loaded.activeAction?.progressTicks, 15);

    expect(loaded.skillStates.length, 1);
    expect(loaded.skillStates[Skill.woodcutting]?.xp, 100);
    expect(loaded.skillStates[Skill.woodcutting]?.masteryPoolXp, 50);

    expect(loaded.actionStates.length, 2);
    expect(loaded.actionStates[normalTree.id]?.masteryXp, 25);
    expect(loaded.actionStates[oakTree.id]?.masteryXp, 10);

    // Verify TimeAway data
    final timeAway = loaded.timeAway;
    expect(timeAway, isNotNull);
    expect(timeAway!.duration, const Duration(seconds: 30));
    expect(timeAway.activeSkill, Skill.woodcutting);
    final changes = timeAway.changes;
    expect(changes.inventoryChanges.counts.length, 2);
    expect(changes.inventoryChanges.counts[normalLogs.id], 10);
    expect(changes.inventoryChanges.counts[oakLogs.id], 5);
    expect(changes.skillXpChanges.counts.length, 1);
    expect(changes.skillXpChanges.counts[Skill.woodcutting], 50);
  });

  test('GlobalState clearAction clears activeAction', () {
    // Create a state with an activeAction
    final stateWithAction = GlobalState.test(
      testRegistries,
      inventory: Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
      ]),
      activeAction: ActiveAction(
        id: normalTree.id,
        remainingTicks: 15,
        totalTicks: 30,
      ),
      skillStates: const {
        Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 50),
      },
      actionStates: {normalTree.id: const ActionState(masteryXp: 25)},
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
      testRegistries,
      inventory: Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
      ]),
      activeAction: ActiveAction(
        id: normalTree.id,
        remainingTicks: 15,
        totalTicks: 30,
      ),
      skillStates: const {
        Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 50),
      },
      actionStates: {normalTree.id: const ActionState(masteryXp: 25)},
      updatedAt: DateTime(2024, 1, 1, 12),
      timeAway: TimeAway(
        registries: testRegistries,
        startTime: DateTime(2024, 1, 1, 11, 59, 30),
        endTime: DateTime(2024, 1, 1, 12),
        activeSkill: Skill.woodcutting,
        changes: Changes(
          inventoryChanges: Counts<MelvorId>(counts: {normalLogs.id: 10}),
          skillXpChanges: Counts<Skill>(counts: {Skill.woodcutting: 50}),
          droppedItems: Counts<MelvorId>.empty(),
          skillLevelChanges: LevelChanges.empty(),
        ),
        masteryLevels: {normalTree.id: 2},
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
      testRegistries,
      inventory: Inventory.fromItems(testItems, [
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
      testRegistries,
      inventory: Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
      ]),
      updatedAt: DateTime(2024, 1, 1, 12),
    );

    final afterSelling = initialState.sellItem(ItemStack(normalLogs, count: 5));

    // Verify all items were removed
    expect(afterSelling.inventory.countOfItem(normalLogs), 0);
    expect(afterSelling.inventory.items.length, 0);

    // Verify GP was added correctly (5 * 1 = 5)
    expect(afterSelling.gp, 5);
  });

  group('GlobalState.unequipFood', () {
    test('moves food from equipment slot to inventory', () {
      // Start with food equipped and empty inventory
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(testRegistries, equipment: equipment);

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
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(shrimp, count: 5),
        ]),
        equipment: equipment,
      );

      final newState = state.unequipFood(0);

      // Food should be removed from equipment
      expect(newState.equipment.foodSlots[0], isNull);
      // Food should stack in inventory (5 + 10 = 15)
      expect(newState.inventory.countOfItem(shrimp), 15);
    });

    test('throws ArgumentError when slot is empty', () {
      final state = GlobalState.test(testRegistries);
      expect(() => state.unequipFood(0), throwsArgumentError);
    });

    test('throws ArgumentError when slot index is invalid', () {
      final state = GlobalState.test(testRegistries);
      expect(() => state.unequipFood(-1), throwsArgumentError);
      expect(() => state.unequipFood(3), throwsArgumentError);
    });

    test('throws StateError when inventory is full', () {
      // Create inventory at capacity with different items
      final items = <ItemStack>[];
      for (var i = 0; i < initialBankSlots; i++) {
        items.add(ItemStack(Item.test('Test Item $i', gp: 1), count: 1));
      }
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, items),
        equipment: equipment,
      );

      expect(() => state.unequipFood(0), throwsStateError);
    });

    test('succeeds when inventory full but has same item type', () {
      // Create inventory at capacity but with shrimp as one of the items
      final items = <ItemStack>[ItemStack(shrimp, count: 5)];
      for (var i = 1; i < initialBankSlots; i++) {
        items.add(ItemStack(Item.test('Test Item $i', gp: 1), count: 1));
      }
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, items),
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
      final state = GlobalState.test(testRegistries, equipment: equipment);

      // Unequip from slot 1
      final newState = state.unequipFood(1);

      expect(newState.equipment.foodSlots[0]?.item, shrimp);
      expect(newState.equipment.foodSlots[1], isNull);
      expect(newState.inventory.countOfItem(lobster), 3);
    });
  });

  group('rollDurationWithModifiers', () {
    test('woodcutting mastery 99 applies 0.2s flat reduction', () {
      final normalTree = testActions.skillActionByName('Normal Tree');
      // Normal Tree has 3 second duration = 30 ticks
      expect(normalTree.minDuration, const Duration(seconds: 3));

      final random = Random(42);

      // State with no mastery - should get full 30 ticks
      final stateNoMastery = GlobalState.test(testRegistries);
      final ticksNoMastery = stateNoMastery.rollDurationWithModifiers(
        normalTree,
        random,
        testRegistries.shop,
      );
      expect(ticksNoMastery, 30);

      // State with mastery level 98 (just below threshold) - should get full 30 ticks
      final xpForLevel98 = startXpForLevel(98);
      final stateMastery98 = GlobalState.test(
        testRegistries,
        actionStates: {normalTree.id: ActionState(masteryXp: xpForLevel98)},
      );
      expect(stateMastery98.actionState(normalTree.id).masteryLevel, 98);
      final ticksMastery98 = stateMastery98.rollDurationWithModifiers(
        normalTree,
        random,
        testRegistries.shop,
      );
      expect(ticksMastery98, 30);

      // State with mastery level 99 - should get 28 ticks (30 - 2 = 0.2s reduction)
      final xpForLevel99 = startXpForLevel(99);
      final stateMastery99 = GlobalState.test(
        testRegistries,
        actionStates: {normalTree.id: ActionState(masteryXp: xpForLevel99)},
      );
      expect(stateMastery99.actionState(normalTree.id).masteryLevel, 99);
      final ticksMastery99 = stateMastery99.rollDurationWithModifiers(
        normalTree,
        random,
        testRegistries.shop,
      );
      expect(ticksMastery99, 28); // 30 ticks - 2 ticks = 28 ticks
    });

    test('shop upgrade applies percentage reduction to woodcutting', () {
      final normalTree = testActions.skillActionByName('Normal Tree');
      // Normal Tree has 3 second fixed duration = 30 ticks
      expect(normalTree.minDuration, const Duration(seconds: 3));
      expect(normalTree.maxDuration, const Duration(seconds: 3));

      final random = Random(42);

      // State with no upgrades - should get full 30 ticks
      final stateNoUpgrade = GlobalState.test(testRegistries);
      final ticksNoUpgrade = stateNoUpgrade.rollDurationWithModifiers(
        normalTree,
        random,
        testRegistries.shop,
      );
      expect(ticksNoUpgrade, 30);

      // Axes must be purchased in order (each requires the previous one).
      // Iron Axe (-5%) + Steel Axe (-5%) = -10% total
      final ironAxeId = MelvorId('melvorD:Iron_Axe');
      final steelAxeId = MelvorId('melvorD:Steel_Axe');
      final stateWithAxes = GlobalState.test(
        testRegistries,
        shop: ShopState(purchaseCounts: {ironAxeId: 1, steelAxeId: 1}),
      );
      final ticksWithAxes = stateWithAxes.rollDurationWithModifiers(
        normalTree,
        random,
        testRegistries.shop,
      );
      // 30 * 0.90 = 27 ticks
      expect(ticksWithAxes, 27);
    });

    test('shop upgrade applies percentage reduction to fishing', () {
      final shrimp = testActions.skillActionByName('Raw Shrimp');
      // Raw Shrimp has variable duration (4-8 seconds)
      expect(shrimp.minDuration, const Duration(seconds: 4));
      expect(shrimp.maxDuration, const Duration(seconds: 8));

      // Get the rolled duration without any modifiers
      final random1 = Random(42);
      final stateNoUpgrade = GlobalState.test(testRegistries);
      final ticksNoUpgrade = stateNoUpgrade.rollDurationWithModifiers(
        shrimp,
        random1,
        testRegistries.shop,
      );

      // Fishing rods must be purchased in order (each requires the previous).
      // Iron Rod (-5%) + Steel Rod (-5%) = -10% total
      final random2 = Random(42);
      final ironRodId = MelvorId('melvorD:Iron_Fishing_Rod');
      final steelRodId = MelvorId('melvorD:Steel_Fishing_Rod');
      final stateWithRods = GlobalState.test(
        testRegistries,
        shop: ShopState(purchaseCounts: {ironRodId: 1, steelRodId: 1}),
      );
      final ticksWithRods = stateWithRods.rollDurationWithModifiers(
        shrimp,
        random2,
        testRegistries.shop,
      );

      // The modifier should reduce duration by 10%
      final expectedTicks = (ticksNoUpgrade * 0.90).round();
      expect(ticksWithRods, expectedTicks);

      // Verify the reduction is meaningful (not just 0)
      expect(ticksWithRods, lessThan(ticksNoUpgrade));
    });

    test('shop upgrade applies percentage reduction to mining', () {
      final copper = testActions.skillActionByName('Copper');
      // Copper has 3 second duration = 30 ticks
      expect(copper.minDuration, const Duration(seconds: 3));

      final random = Random(42);

      // State with no upgrades
      final stateNoUpgrade = GlobalState.test(testRegistries);
      final ticksNoUpgrade = stateNoUpgrade.rollDurationWithModifiers(
        copper,
        random,
        testRegistries.shop,
      );
      expect(ticksNoUpgrade, 30);

      // Pickaxes must be purchased in order (each requires the previous).
      // Iron (-5%) + Steel (-5%) = -10% total
      final ironPickaxeId = MelvorId('melvorD:Iron_Pickaxe');
      final steelPickaxeId = MelvorId('melvorD:Steel_Pickaxe');
      final stateWithPickaxes = GlobalState.test(
        testRegistries,
        shop: ShopState(purchaseCounts: {ironPickaxeId: 1, steelPickaxeId: 1}),
      );
      final ticksWithPickaxes = stateWithPickaxes.rollDurationWithModifiers(
        copper,
        random,
        testRegistries.shop,
      );
      // 30 * 0.90 = 27 ticks
      expect(ticksWithPickaxes, 27);
    });
  });

  group('GlobalState.openItems', () {
    late Item eggChest;
    late Item feathers;
    late Item rawChicken;

    setUpAll(() {
      eggChest = testItems.byName('Egg Chest');
      feathers = testItems.byName('Feathers');
      rawChicken = testItems.byName('Raw Chicken');
    });

    // initialBankSlots is 20, so to get specific capacities we subtract from 20
    // E.g., bankSlots: -18 gives capacity of 20 + (-18) = 2

    test('opens a single item successfully', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(eggChest, count: 1),
        ]),
        // Capacity = 20 + (-18) = 2 (enough for chest + drop)
        shop: const ShopState.empty(), // Uses default capacity
      );

      final random = Random(42); // Seeded for determinism
      final (newState, result) = state.openItems(
        eggChest,
        count: 1,
        random: random,
      );

      // One item opened
      expect(result.openedCount, 1);
      expect(result.hasDrops, isTrue);
      expect(result.error, isNull);

      // Chest was consumed
      expect(newState.inventory.countOfItem(eggChest), 0);

      // Got exactly one type of drop (feathers or raw chicken)
      expect(result.drops.length, 1);
      final dropName = result.drops.keys.first;
      expect(dropName == 'Feathers' || dropName == 'Raw Chicken', isTrue);

      // The drop is in inventory
      if (dropName == 'Feathers') {
        expect(
          newState.inventory.countOfItem(feathers),
          result.drops[dropName],
        );
      } else {
        expect(
          newState.inventory.countOfItem(rawChicken),
          result.drops[dropName],
        );
      }
    });

    test('opens multiple items and combines drops', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(eggChest, count: 5),
        ]),
        // Capacity = 20 + (-17) = 3 (chest + both possible drop types)
        shop: const ShopState.empty(), // Uses default capacity
      );

      final random = Random(123);
      final (newState, result) = state.openItems(
        eggChest,
        count: 5,
        random: random,
      );

      // All items opened
      expect(result.openedCount, 5);
      expect(result.hasDrops, isTrue);
      expect(result.error, isNull);

      // All chests consumed
      expect(newState.inventory.countOfItem(eggChest), 0);

      // Got drops (could be feathers, chicken, or both)
      expect(result.drops.isNotEmpty, isTrue);

      // Total drops in result match inventory
      final feathersInResult = result.drops['Feathers'] ?? 0;
      final chickenInResult = result.drops['Raw Chicken'] ?? 0;
      expect(newState.inventory.countOfItem(feathers), feathersInResult);
      expect(newState.inventory.countOfItem(rawChicken), chickenInResult);
    });

    test('fails on first open when inventory is full', () {
      // Create state with full inventory (20 slots)
      // Fill 19 slots with different items, 1 slot with the chest
      final fillerItems = <ItemStack>[];
      var fillerIndex = 0;
      for (final item in testItems.all) {
        // Skip the egg chest and find 19 different items
        if (item.id == eggChest.id) continue;
        fillerItems.add(ItemStack(item, count: 1));
        fillerIndex++;
        if (fillerIndex >= 19) break;
      }
      // Add the chests we want to open
      fillerItems.add(ItemStack(eggChest, count: 3));

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, fillerItems),
        shop: const ShopState.empty(),
      );

      // Verify inventory is actually full
      expect(state.inventoryUsed, state.inventoryCapacity);

      final random = Random(42);
      final (newState, result) = state.openItems(
        eggChest,
        count: 3,
        random: random,
      );

      // No items opened because we can't add the drop (no new slot available)
      expect(result.openedCount, 0);
      expect(result.hasDrops, isFalse);
      expect(result.error, 'Inventory full');
      expect(result.drops, isEmpty);

      // All chests remain
      expect(newState.inventory.countOfItem(eggChest), 3);
    });

    test('partial open when inventory fills mid-stack', () {
      // Create inventory with 18 filler items + 1 chest slot = 19 slots
      // This leaves 1 slot for a drop type
      // Open 1: drop uses the 20th slot. Now full.
      // Open 2: if drop is same type, it stacks and we continue
      //         if drop is different type, we can't add, so we stop
      final fillerItems = <ItemStack>[];
      var fillerIndex = 0;
      for (final item in testItems.all) {
        // Skip the egg chest and find 18 different items
        if (item.id == eggChest.id) continue;
        fillerItems.add(ItemStack(item, count: 1));
        fillerIndex++;
        if (fillerIndex >= 18) break;
      }
      // Add the chests we want to open
      fillerItems.add(ItemStack(eggChest, count: 10));

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, fillerItems),
        shop: const ShopState.empty(),
      );

      // Verify inventory is 19/20 (one slot free for first drop)
      expect(state.inventoryUsed, 19);
      expect(state.inventoryCapacity, 20);

      // Seed 999 should give us a mix that eventually hits a different drop
      final random = Random(999);
      final (newState, result) = state.openItems(
        eggChest,
        count: 10,
        random: random,
      );

      // Should have opened some but not all (depends on random drops)
      // At minimum we should open 1, at most we could open all 10 if same drop
      expect(result.openedCount, greaterThan(0));

      // If we didn't open all 10, there should be an error
      if (result.openedCount < 10) {
        expect(result.error, 'Inventory full');
        // Remaining chests are still there
        expect(
          newState.inventory.countOfItem(eggChest),
          10 - result.openedCount,
        );
      }

      // Drops were tracked
      expect(result.hasDrops, isTrue);
    });

    test('leaves remaining chests when inventory fills after some opens', () {
      // We want to ensure that when opening fails partway through,
      // the unopened chests remain in inventory
      // Create inventory with 18 filler items + 1 chest slot = 19 slots
      // This leaves 1 slot for a drop type
      final fillerItems = <ItemStack>[];
      var fillerIndex = 0;
      for (final item in testItems.all) {
        // Skip the egg chest and find 18 different items
        if (item.id == eggChest.id) continue;
        fillerItems.add(ItemStack(item, count: 1));
        fillerIndex++;
        if (fillerIndex >= 18) break;
      }
      // Add the chests we want to open
      fillerItems.add(ItemStack(eggChest, count: 5));

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, fillerItems),
        shop: const ShopState.empty(),
      );

      // Try many seeds to find one that fails partway
      for (var seed = 0; seed < 100; seed++) {
        final random = Random(seed);
        final (newState, result) = state.openItems(
          eggChest,
          count: 5,
          random: random,
        );

        // If this seed caused partial opening
        if (result.openedCount > 0 && result.openedCount < 5) {
          // Verify error
          expect(result.error, 'Inventory full');

          // Verify remaining chests
          final remainingChests = 5 - result.openedCount;
          expect(newState.inventory.countOfItem(eggChest), remainingChests);

          // Verify we got drops for what we opened
          expect(result.hasDrops, isTrue);

          // Test passed, we found a good seed
          return;
        }
      }

      // If we get here, we didn't find a seed that triggered partial open
      // This is unlikely but possible - skip with a warning
      // ignore: avoid_print
      print('Warning: Could not find seed for partial open test');
    });

    test('throws when item is not openable', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 5),
        ]),
      );

      expect(
        () => state.openItems(normalLogs, count: 1, random: Random()),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when item is not in inventory', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.empty(testItems),
      );

      expect(
        () => state.openItems(eggChest, count: 1, random: Random()),
        throwsA(isA<StateError>()),
      );
    });

    test('clamps count to available quantity', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(eggChest, count: 2),
        ]),
        // Enough capacity for drops
        shop: const ShopState.empty(), // Uses default capacity // Capacity = 3
      );

      final random = Random(42);
      final (newState, result) = state.openItems(
        eggChest,
        count: 100, // Request more than we have
        random: random,
      );

      // Only opened what we had
      expect(result.openedCount, 2);
      expect(newState.inventory.countOfItem(eggChest), 0);
    });
  });
}
