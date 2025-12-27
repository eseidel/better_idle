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
  late Item bronzeDagger;
  late Item bronzeSword;
  late Item bronzeHelmet;
  late Item bronzeShield;
  late Action normalTree;
  late Action oakTree;

  setUpAll(() async {
    await loadTestRegistries();
    normalLogs = testItems.byName('Normal Logs');
    oakLogs = testItems.byName('Oak Logs');
    birdNest = testItems.byName('Bird Nest');
    shrimp = testItems.byName('Shrimp');
    lobster = testItems.byName('Lobster');
    bronzeDagger = testItems.byName('Bronze Dagger');
    bronzeSword = testItems.byName('Bronze Sword');
    bronzeHelmet = testItems.byName('Bronze Helmet');
    bronzeShield = testItems.byName('Bronze Shield');
    normalTree = testActions.woodcutting('Normal Tree');
    oakTree = testActions.woodcutting('Oak Tree');
  });

  test('GlobalState toJson/fromJson round-trip', () {
    // Get farming data for plot state testing
    final crops = testRegistries.farmingCrops.all;
    final levelOneCrops = crops.where((c) => c.level == 1).toList();
    final crop = levelOneCrops.first;
    final initialPlots = testRegistries.farmingPlots.initialPlots().toList();
    final plotId1 = initialPlots[0];
    // Get a second plot if available, otherwise use the first with different state
    final plotId2 = initialPlots.length > 1
        ? initialPlots[1]
        : MelvorId('melvorD:Test_Plot_2');

    // Create a state with TimeAway data and PlotStates
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
      plotStates: {
        plotId1: PlotState(cropId: crop.id, growthTicksRemaining: 500),
        plotId2: PlotState(
          cropId: crop.id,
          growthTicksRemaining: 0, // Ready to harvest
        ),
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

    // Verify PlotStates data
    expect(loaded.plotStates.length, 2);
    final loadedPlot1 = loaded.plotStates[plotId1]!;
    expect(loadedPlot1.cropId, crop.id);
    expect(loadedPlot1.growthTicksRemaining, 500);
    expect(loadedPlot1.isGrowing, true);
    expect(loadedPlot1.isReadyToHarvest, false);

    final loadedPlot2 = loaded.plotStates[plotId2]!;
    expect(loadedPlot2.cropId, crop.id);
    expect(loadedPlot2.growthTicksRemaining, 0);
    expect(loadedPlot2.isGrowing, false);
    expect(loadedPlot2.isReadyToHarvest, true);

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

  group('GlobalState.equipFood', () {
    test('moves food from inventory to equipment slot', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(shrimp, count: 10),
        ]),
      );

      final newState = state.equipFood(ItemStack(shrimp, count: 10));

      // Food should be removed from inventory
      expect(newState.inventory.countOfItem(shrimp), 0);
      // Food should be in an equipment slot
      expect(newState.equipment.foodSlots[0]?.item, shrimp);
      expect(newState.equipment.foodSlots[0]?.count, 10);
    });

    test('equips partial stack from inventory', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(shrimp, count: 20),
        ]),
      );

      final newState = state.equipFood(ItemStack(shrimp, count: 5));

      // Only 5 should be removed from inventory
      expect(newState.inventory.countOfItem(shrimp), 15);
      // 5 should be in equipment
      expect(newState.equipment.foodSlots[0]?.count, 5);
    });

    test('stacks with existing food in slot', () {
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 5), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(shrimp, count: 10),
        ]),
        equipment: equipment,
      );

      final newState = state.equipFood(ItemStack(shrimp, count: 10));

      // Food should be removed from inventory
      expect(newState.inventory.countOfItem(shrimp), 0);
      // Should stack in the first slot (5 + 10 = 15)
      expect(newState.equipment.foodSlots[0]?.count, 15);
    });

    test('throws when item is not food', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 5),
        ]),
      );

      expect(
        () => state.equipFood(ItemStack(normalLogs, count: 5)),
        throwsStateError,
      );
    });
  });

  group('GlobalState.eatSelectedFood', () {
    test('heals player and consumes food', () {
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 5), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        health: const HealthState(lostHp: 50),
      );

      final newState = state.eatSelectedFood();

      expect(newState, isNotNull);
      // Food count should decrease by 1
      expect(newState!.equipment.foodSlots[0]?.count, 4);
      // Health should be restored by shrimp's heal amount
      expect(newState.health.lostHp, lessThan(50));
    });

    test('returns null when no food is selected', () {
      final state = GlobalState.test(
        testRegistries,
        health: const HealthState(lostHp: 50),
      );

      final newState = state.eatSelectedFood();

      expect(newState, isNull);
    });

    test('returns null when player is at full health', () {
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 5), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        health: const HealthState.full(),
      );

      final newState = state.eatSelectedFood();

      expect(newState, isNull);
    });

    test('clears slot when last food is eaten', () {
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 1), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        health: const HealthState(lostHp: 50),
      );

      final newState = state.eatSelectedFood();

      expect(newState, isNotNull);
      // Slot should now be empty
      expect(newState!.equipment.foodSlots[0], isNull);
    });

    test('eats from correct selected slot', () {
      final equipment = Equipment(
        foodSlots: [
          ItemStack(shrimp, count: 5),
          ItemStack(lobster, count: 3),
          null,
        ],
        selectedFoodSlot: 1, // Select lobster
      );
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        health: const HealthState(lostHp: 50),
      );

      final newState = state.eatSelectedFood();

      expect(newState, isNotNull);
      // Shrimp should be unchanged
      expect(newState!.equipment.foodSlots[0]?.count, 5);
      // Lobster should decrease by 1
      expect(newState.equipment.foodSlots[1]?.count, 2);
    });
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
      final normalTree = testActions.woodcutting('Normal Tree');
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
      final normalTree = testActions.woodcutting('Normal Tree');
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
      final shrimp = testActions.fishing('Raw Shrimp');
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
      final copper = testActions.mining('Copper');
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

  group('GlobalState.equipGear', () {
    test('moves item from inventory to equipment slot', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(bronzeDagger, count: 1),
        ]),
      );

      final newState = state.equipGear(bronzeDagger, EquipmentSlot.weapon);

      // Item should be removed from inventory
      expect(newState.inventory.countOfItem(bronzeDagger), 0);
      // Item should be in the weapon slot
      expect(newState.equipment.gearInSlot(EquipmentSlot.weapon), bronzeDagger);
    });

    test('only removes one item when equipping from stack', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(bronzeDagger, count: 5),
        ]),
      );

      final newState = state.equipGear(bronzeDagger, EquipmentSlot.weapon);

      // Only one item should be removed from inventory
      expect(newState.inventory.countOfItem(bronzeDagger), 4);
      // Item should be in the weapon slot
      expect(newState.equipment.gearInSlot(EquipmentSlot.weapon), bronzeDagger);
    });

    test('swaps items when slot is occupied', () {
      // Start with a sword equipped and dagger in inventory
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeSword},
      );
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(bronzeDagger, count: 1),
        ]),
        equipment: equipment,
      );

      final newState = state.equipGear(bronzeDagger, EquipmentSlot.weapon);

      // Dagger should be equipped
      expect(newState.equipment.gearInSlot(EquipmentSlot.weapon), bronzeDagger);
      // Sword should be back in inventory
      expect(newState.inventory.countOfItem(bronzeSword), 1);
      // Dagger should be removed from inventory
      expect(newState.inventory.countOfItem(bronzeDagger), 0);
    });

    test('throws StateError when item is not in inventory', () {
      final state = GlobalState.test(testRegistries);

      expect(
        () => state.equipGear(bronzeDagger, EquipmentSlot.weapon),
        throwsStateError,
      );
    });

    test('throws StateError when item is not equippable', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 1),
        ]),
      );

      expect(
        () => state.equipGear(normalLogs, EquipmentSlot.weapon),
        throwsStateError,
      );
    });

    test('throws StateError when item cannot go in the specified slot', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(bronzeDagger, count: 1),
        ]),
      );

      // Bronze dagger can only go in Weapon slot, not Helmet
      expect(
        () => state.equipGear(bronzeDagger, EquipmentSlot.helmet),
        throwsStateError,
      );
    });

    test('throws StateError when inventory full and swapping', () {
      // Fill inventory with different items
      final items = <ItemStack>[];
      for (var i = 0; i < initialBankSlots; i++) {
        items.add(ItemStack(Item.test('Test Item $i', gp: 1), count: 1));
      }
      // Replace one slot with the dagger we want to equip
      items[0] = ItemStack(bronzeDagger, count: 1);

      // Have a sword equipped that needs to go back to inventory
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeSword},
      );

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, items),
        equipment: equipment,
      );

      // Inventory is full, can't swap
      expect(
        () => state.equipGear(bronzeDagger, EquipmentSlot.weapon),
        throwsStateError,
      );
    });

    test('can equip different items to different slots', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(bronzeDagger, count: 1),
          ItemStack(bronzeHelmet, count: 1),
          ItemStack(bronzeShield, count: 1),
        ]),
      );

      var newState = state.equipGear(bronzeDagger, EquipmentSlot.weapon);
      newState = newState.equipGear(bronzeHelmet, EquipmentSlot.helmet);
      newState = newState.equipGear(bronzeShield, EquipmentSlot.shield);

      expect(newState.equipment.gearInSlot(EquipmentSlot.weapon), bronzeDagger);
      expect(newState.equipment.gearInSlot(EquipmentSlot.helmet), bronzeHelmet);
      expect(newState.equipment.gearInSlot(EquipmentSlot.shield), bronzeShield);
      expect(newState.inventory.countOfItem(bronzeDagger), 0);
      expect(newState.inventory.countOfItem(bronzeHelmet), 0);
      expect(newState.inventory.countOfItem(bronzeShield), 0);
    });
  });

  group('GlobalState.unequipGear', () {
    test('moves item from equipment slot to inventory', () {
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeDagger},
      );
      final state = GlobalState.test(testRegistries, equipment: equipment);

      final newState = state.unequipGear(EquipmentSlot.weapon);

      expect(newState, isNotNull);
      expect(newState!.equipment.gearInSlot(EquipmentSlot.weapon), isNull);
      expect(newState.inventory.countOfItem(bronzeDagger), 1);
    });

    test('returns null when slot is empty', () {
      final state = GlobalState.test(testRegistries);

      final newState = state.unequipGear(EquipmentSlot.weapon);

      expect(newState, isNull);
    });

    test('stacks with existing inventory items', () {
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeDagger},
      );
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(bronzeDagger, count: 3),
        ]),
        equipment: equipment,
      );

      final newState = state.unequipGear(EquipmentSlot.weapon);

      expect(newState, isNotNull);
      expect(newState!.equipment.gearInSlot(EquipmentSlot.weapon), isNull);
      // Should stack: 3 + 1 = 4
      expect(newState.inventory.countOfItem(bronzeDagger), 4);
    });

    test('throws StateError when inventory is full', () {
      // Fill inventory with different items
      final items = <ItemStack>[];
      for (var i = 0; i < initialBankSlots; i++) {
        items.add(ItemStack(Item.test('Test Item $i', gp: 1), count: 1));
      }

      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeDagger},
      );
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, items),
        equipment: equipment,
      );

      expect(() => state.unequipGear(EquipmentSlot.weapon), throwsStateError);
    });

    test('succeeds when inventory full but has same item type', () {
      // Fill inventory but include the same item type
      final items = <ItemStack>[ItemStack(bronzeDagger, count: 2)];
      for (var i = 1; i < initialBankSlots; i++) {
        items.add(ItemStack(Item.test('Test Item $i', gp: 1), count: 1));
      }

      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeDagger},
      );
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, items),
        equipment: equipment,
      );

      // Should succeed because dagger can stack
      final newState = state.unequipGear(EquipmentSlot.weapon);
      expect(newState, isNotNull);
      expect(newState!.inventory.countOfItem(bronzeDagger), 3);
      expect(newState.equipment.gearInSlot(EquipmentSlot.weapon), isNull);
    });

    test('can unequip from any slot', () {
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {
          EquipmentSlot.weapon: bronzeDagger,
          EquipmentSlot.helmet: bronzeHelmet,
          EquipmentSlot.shield: bronzeShield,
        },
      );
      final state = GlobalState.test(testRegistries, equipment: equipment);

      // Unequip helmet only
      final newState = state.unequipGear(EquipmentSlot.helmet);

      expect(newState, isNotNull);
      expect(
        newState!.equipment.gearInSlot(EquipmentSlot.weapon),
        bronzeDagger,
      );
      expect(newState.equipment.gearInSlot(EquipmentSlot.helmet), isNull);
      expect(newState.equipment.gearInSlot(EquipmentSlot.shield), bronzeShield);
      expect(newState.inventory.countOfItem(bronzeHelmet), 1);
    });
  });

  group('GlobalState.setRecipeIndex', () {
    test('sets the selected recipe index for an action', () {
      final state = GlobalState.test(testRegistries);

      // Initially, action state should have no selected recipe index
      expect(state.actionState(normalTree.id).selectedRecipeIndex, isNull);

      // Set a recipe index
      final newState = state.setRecipeIndex(normalTree.id, 2);

      // Verify the recipe index was set
      expect(newState.actionState(normalTree.id).selectedRecipeIndex, 2);
    });

    test('updates existing action state with recipe index', () {
      // Create state with existing mastery XP
      final state = GlobalState.test(
        testRegistries,
        actionStates: {normalTree.id: const ActionState(masteryXp: 100)},
      );

      // Set a recipe index
      final newState = state.setRecipeIndex(normalTree.id, 1);

      // Verify mastery XP is preserved
      expect(newState.actionState(normalTree.id).masteryXp, 100);
      // Verify recipe index was set
      expect(newState.actionState(normalTree.id).selectedRecipeIndex, 1);
    });

    test('can change recipe index from one value to another', () {
      final state = GlobalState.test(
        testRegistries,
        actionStates: {
          normalTree.id: const ActionState(
            masteryXp: 50,
            selectedRecipeIndex: 0,
          ),
        },
      );

      // Change recipe index from 0 to 3
      final newState = state.setRecipeIndex(normalTree.id, 3);

      expect(newState.actionState(normalTree.id).selectedRecipeIndex, 3);
      expect(newState.actionState(normalTree.id).masteryXp, 50);
    });
  });

  group('GlobalState.plantCrop and harvestCrop', () {
    late FarmingCrop crop;
    late Item seed;
    late Item product;
    late MelvorId plotId;

    setUpAll(() {
      // Get a level-1 crop for testing
      final crops = testRegistries.farmingCrops.all;
      final levelOneCrops = crops.where((c) => c.level == 1).toList();
      crop = levelOneCrops.first;
      seed = testItems.byId(crop.seedId);
      product = testItems.byId(crop.productId);

      // Get an unlocked plot
      final initialPlots = testRegistries.farmingPlots.initialPlots();
      plotId = initialPlots.first;
    });

    test('plantCrop consumes seed and creates growing plot state', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost + 5),
        ]),
      );

      // Verify initial state
      expect(state.inventory.countOfItem(seed), crop.seedCost + 5);
      expect(state.plotStates[plotId], isNull);

      // Plant the crop
      state = state.plantCrop(plotId, crop);

      // Verify seed was consumed
      expect(state.inventory.countOfItem(seed), 5);

      // Verify plot state was created
      final plotState = state.plotStates[plotId]!;
      expect(plotState.cropId, crop.id);
      expect(plotState.growthTicksRemaining, crop.growthTicks);
      expect(plotState.isGrowing, true);
      expect(plotState.isReadyToHarvest, false);
    });

    test('plantCrop throws when plot is not unlocked', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost),
        ]),
        unlockedPlots: {}, // No plots unlocked
      );

      expect(() => state.plantCrop(plotId, crop), throwsStateError);
    });

    test('plantCrop throws when plot is not empty', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost * 2),
        ]),
      );

      // Plant first crop
      state = state.plantCrop(plotId, crop);

      // Try to plant again in the same plot
      expect(() => state.plantCrop(plotId, crop), throwsStateError);
    });

    test('plantCrop throws when not enough seeds', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost - 1), // Not enough
        ]),
      );

      expect(() => state.plantCrop(plotId, crop), throwsStateError);
    });

    test('harvestCrop yields product and clears plot', () {
      final random = Random(42);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost),
        ]),
      );

      // Plant the crop
      state = state.plantCrop(plotId, crop);

      // Manually set the crop as ready (growthTicksRemaining = 0)
      final readyPlotState = PlotState(
        cropId: crop.id,
        growthTicksRemaining: 0,
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      // Verify crop is ready
      expect(state.plotStates[plotId]!.isReadyToHarvest, true);

      // Harvest (note: 50% success rate with no compost, may fail)
      state = state.harvestCrop(plotId, random);

      // Plot should be cleared regardless of success/failure
      final plotStateAfterFirstHarvest = state.plotStates[plotId];
      expect(
        plotStateAfterFirstHarvest == null ||
            plotStateAfterFirstHarvest.isEmpty,
        true,
      );

      // Verify plot is cleared
      final plotStateAfter = state.plotStates[plotId];
      expect(
        plotStateAfter == null || plotStateAfter.isEmpty,
        true,
        reason: 'Plot should be empty after harvest',
      );
    });

    test('harvestCrop awards farming XP', () {
      final random = Random(42);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost),
        ]),
      );

      // Plant the crop
      state = state.plantCrop(plotId, crop);

      // Check if this crop's category gives XP on plant or harvest
      final category = testRegistries.farmingCategories.byId(crop.categoryId);
      final xpOnPlant = category?.giveXPOnPlant ?? false;

      // Get XP after planting
      final xpAfterPlant = state.skillState(Skill.farming).xp;

      // Set crop as ready
      final readyPlotState = PlotState(
        cropId: crop.id,
        growthTicksRemaining: 0,
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      // Harvest (note: 50% success rate, but we check XP regardless)
      state = state.harvestCrop(plotId, random);

      // Verify XP was awarded (either on plant or harvest, depending on category)
      final xpAfterHarvest = state.skillState(Skill.farming).xp;
      if (xpOnPlant) {
        // XP given on plant, so should have XP after plant
        expect(xpAfterPlant, greaterThan(0));
      } else {
        // XP given on harvest
        expect(xpAfterHarvest, greaterThan(xpAfterPlant));
      }
    });

    test('harvestCrop throws when plot has no ready crop', () {
      final random = Random(42);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost),
        ]),
      );

      // Plant the crop (still growing)
      state = state.plantCrop(plotId, crop);

      // Verify crop is NOT ready
      expect(state.plotStates[plotId]!.isGrowing, true);
      expect(state.plotStates[plotId]!.isReadyToHarvest, false);

      // Try to harvest - should throw
      expect(() => state.harvestCrop(plotId, random), throwsStateError);
    });

    test('harvestCrop throws when plot is empty', () {
      final random = Random(42);
      final state = GlobalState.empty(testRegistries);

      // No crop planted
      expect(state.plotStates[plotId], isNull);

      // Try to harvest - should throw
      expect(() => state.harvestCrop(plotId, random), throwsStateError);
    });

    test('harvestCrop applies harvest bonus to harvest quantity', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost * 2),
        ]),
      );

      // Plant first crop without harvest bonus
      state = state.plantCrop(plotId, crop);
      final compostNoBonus = testCompost(compostValue: 50, harvestBonus: 0);
      var readyPlotState = PlotState(
        cropId: crop.id,
        growthTicksRemaining: 0,
        compostItems: [compostNoBonus],
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      // Harvest without harvest bonus
      state = state.harvestCrop(plotId, Random(42));
      final harvestWithoutBonus = state.inventory.countOfItem(product);

      // Reset inventory for second harvest
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: crop.seedCost),
        ]),
      );

      // Plant second crop with harvest bonus (50%)
      state = state.plantCrop(plotId, crop);
      final compostWithBonus = testCompost(compostValue: 50, harvestBonus: 50);
      readyPlotState = PlotState(
        cropId: crop.id,
        growthTicksRemaining: 0,
        compostItems: [compostWithBonus],
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      // Harvest with harvest bonus
      state = state.harvestCrop(plotId, Random(42));
      final harvestWithBonus = state.inventory.countOfItem(product);

      // With 50% harvest bonus, should get more product
      expect(harvestWithBonus, greaterThan(harvestWithoutBonus));
    });
  });

  group('hasActiveBackgroundTimers', () {
    test('returns false with no background timers', () {
      final state = GlobalState.empty(testRegistries);
      expect(state.hasActiveBackgroundTimers, false);
    });

    test('returns true when farming plot is growing', () {
      // Get farming data
      final crops = testRegistries.farmingCrops.all;
      final levelOneCrops = crops.where((c) => c.level == 1).toList();
      final crop = levelOneCrops.first;
      final plotId = testRegistries.farmingPlots.initialPlots().first;

      final state = GlobalState.test(
        testRegistries,
        plotStates: {
          plotId: PlotState(cropId: crop.id, growthTicksRemaining: 100),
        },
      );

      expect(state.hasActiveBackgroundTimers, true);
    });

    test('returns false when farming plot is ready to harvest', () {
      // Get farming data
      final crops = testRegistries.farmingCrops.all;
      final levelOneCrops = crops.where((c) => c.level == 1).toList();
      final crop = levelOneCrops.first;
      final plotId = testRegistries.farmingPlots.initialPlots().first;

      final state = GlobalState.test(
        testRegistries,
        plotStates: {
          plotId: PlotState(
            cropId: crop.id,
            growthTicksRemaining: 0, // Ready to harvest
          ),
        },
      );

      expect(state.hasActiveBackgroundTimers, false);
    });

    test('returns true when player HP needs regeneration', () {
      final state = GlobalState.test(
        testRegistries,
        health: const HealthState(lostHp: 10),
      );

      expect(state.hasActiveBackgroundTimers, true);
    });

    test('returns false when player HP is full', () {
      final state = GlobalState.test(
        testRegistries,
        health: const HealthState.full(),
      );

      expect(state.hasActiveBackgroundTimers, false);
    });

    test('returns true with multiple growing plots', () {
      // Get farming data
      final crops = testRegistries.farmingCrops.all;
      final levelOneCrops = crops.where((c) => c.level == 1).toList();
      final crop = levelOneCrops.first;
      final initialPlots = testRegistries.farmingPlots.initialPlots().toList();
      final plotId1 = initialPlots[0];
      final plotId2 = initialPlots.length > 1
          ? initialPlots[1]
          : MelvorId('melvorD:Test_Plot_2');

      final state = GlobalState.test(
        testRegistries,
        plotStates: {
          plotId1: PlotState(cropId: crop.id, growthTicksRemaining: 100),
          plotId2: PlotState(
            cropId: crop.id,
            growthTicksRemaining: 0, // This one is ready
          ),
        },
      );

      // Should return true because plotId1 is still growing
      expect(state.hasActiveBackgroundTimers, true);
    });
  });

  group('isCombatPaused', () {
    test('returns false when no active action', () {
      final state = GlobalState.test(testRegistries);
      expect(state.isCombatPaused, false);
    });

    test('returns false when active action has no action state', () {
      final state = GlobalState.test(
        testRegistries,
        activeAction: ActiveAction(
          id: normalTree.id,
          remainingTicks: 15,
          totalTicks: 30,
        ),
      );
      expect(state.isCombatPaused, false);
    });

    test('returns false when action state has no combat state', () {
      final state = GlobalState.test(
        testRegistries,
        activeAction: ActiveAction(
          id: normalTree.id,
          remainingTicks: 15,
          totalTicks: 30,
        ),
        actionStates: {normalTree.id: const ActionState(masteryXp: 100)},
      );
      expect(state.isCombatPaused, false);
    });

    test('returns false when combat is not spawning', () {
      final combatActionId = ActionId.test(Skill.combat, 'Cow');
      final combatState = CombatActionState(
        monsterId: combatActionId,
        monsterHp: 50,
        playerAttackTicksRemaining: 24,
        monsterAttackTicksRemaining: 28,
        // spawnTicksRemaining is null - not spawning
      );
      final state = GlobalState.test(
        testRegistries,
        activeAction: ActiveAction(
          id: combatActionId,
          remainingTicks: 0,
          totalTicks: 0,
        ),
        actionStates: {
          combatActionId: ActionState(masteryXp: 0, combat: combatState),
        },
      );
      expect(state.isCombatPaused, false);
    });

    test('returns true when combat is spawning', () {
      final combatActionId = ActionId.test(Skill.combat, 'Cow');
      final combatState = CombatActionState(
        monsterId: combatActionId,
        monsterHp: 0,
        playerAttackTicksRemaining: 24,
        monsterAttackTicksRemaining: 28,
        spawnTicksRemaining: 30, // Monster is spawning
      );
      final state = GlobalState.test(
        testRegistries,
        activeAction: ActiveAction(
          id: combatActionId,
          remainingTicks: 0,
          totalTicks: 0,
        ),
        actionStates: {
          combatActionId: ActionState(masteryXp: 0, combat: combatState),
        },
      );
      expect(state.isCombatPaused, true);
    });
  });

  group('Equipment gear slots serialization', () {
    test('toJson/fromJson round-trip with gear equipped', () {
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {
          EquipmentSlot.weapon: bronzeDagger,
          EquipmentSlot.helmet: bronzeHelmet,
        },
      );
      final originalState = GlobalState.test(
        testRegistries,
        equipment: equipment,
        updatedAt: DateTime(2024, 1, 1, 12),
      );

      // Convert to JSON
      final json = originalState.toJson();

      // Convert back from JSON
      final loaded = GlobalState.fromJson(testRegistries, json);

      // Verify gear is preserved
      expect(loaded.equipment.gearInSlot(EquipmentSlot.weapon), bronzeDagger);
      expect(loaded.equipment.gearInSlot(EquipmentSlot.helmet), bronzeHelmet);
      expect(loaded.equipment.gearInSlot(EquipmentSlot.shield), isNull);
    });
  });
}
