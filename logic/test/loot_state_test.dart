import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item bones;
  late Item rawChicken;
  late Item feathers;

  setUpAll(() async {
    await loadTestRegistries();
    bones = testItems.byName('Bones');
    rawChicken = testItems.byName('Raw Chicken');
    feathers = testItems.byName('Feathers');
  });

  group('LootState toJson/fromJson', () {
    test('empty state round-trips', () {
      const original = LootState.empty();

      final json = original.toJson();
      final loaded = LootState.fromJson(testItems, json);

      expect(loaded.isEmpty, true);
      expect(loaded.stacks, isEmpty);
    });

    test('state with single stack round-trips', () {
      final original = LootState(stacks: [ItemStack(bones, count: 5)]);

      final json = original.toJson();
      final loaded = LootState.fromJson(testItems, json);

      expect(loaded.stacks.length, 1);
      expect(loaded.stacks[0].item.id, bones.id);
      expect(loaded.stacks[0].count, 5);
    });

    test('state with multiple stacks round-trips', () {
      final original = LootState(
        stacks: [
          ItemStack(bones, count: 3),
          ItemStack(rawChicken, count: 1),
          ItemStack(feathers, count: 10),
        ],
      );

      final json = original.toJson();
      final loaded = LootState.fromJson(testItems, json);

      expect(loaded.stacks.length, 3);

      expect(loaded.stacks[0].item.id, bones.id);
      expect(loaded.stacks[0].count, 3);

      expect(loaded.stacks[1].item.id, rawChicken.id);
      expect(loaded.stacks[1].count, 1);

      expect(loaded.stacks[2].item.id, feathers.id);
      expect(loaded.stacks[2].count, 10);
    });

    test('maybeFromJson returns null for null input', () {
      final result = LootState.maybeFromJson(testItems, null);
      expect(result, isNull);
    });

    test('maybeFromJson parses valid json', () {
      final original = LootState(stacks: [ItemStack(bones, count: 2)]);

      final json = original.toJson();
      final loaded = LootState.maybeFromJson(testItems, json);

      expect(loaded, isNotNull);
      expect(loaded!.stacks.length, 1);
      expect(loaded.stacks[0].item.id, bones.id);
      expect(loaded.stacks[0].count, 2);
    });
  });

  group('LootState FIFO behavior', () {
    test('addItem appends new non-bones item as new stack', () {
      final state = LootState(stacks: [ItemStack(bones, count: 1)]);

      final (newState, lost) = state.addItem(
        ItemStack(rawChicken, count: 1),
        isBones: false,
      );

      expect(lost, isEmpty);
      expect(newState.stacks.length, 2);
      expect(newState.stacks[0].item.id, bones.id);
      expect(newState.stacks[1].item.id, rawChicken.id);
    });

    test('addItem stacks bones with existing bones of same type', () {
      final state = LootState(
        stacks: [ItemStack(bones, count: 3), ItemStack(rawChicken, count: 1)],
      );

      final (newState, lost) = state.addItem(
        ItemStack(bones, count: 2),
        isBones: true,
      );

      expect(lost, isEmpty);
      expect(newState.stacks.length, 2);
      expect(newState.stacks[0].item.id, bones.id);
      expect(newState.stacks[0].count, 5); // 3 + 2
      expect(newState.stacks[1].item.id, rawChicken.id);
    });

    test('addItem removes oldest item when full (FIFO)', () {
      // Create a full loot state with maxLootStacks items
      final stacks = <ItemStack>[];
      for (var i = 0; i < maxLootStacks; i++) {
        stacks.add(ItemStack(rawChicken, count: 1));
      }
      final state = LootState(stacks: stacks);

      expect(state.isFull, true);
      expect(state.stackCount, maxLootStacks);

      // Add a new item - should remove the oldest (first) item
      final (newState, lost) = state.addItem(
        ItemStack(feathers, count: 5),
        isBones: false,
      );

      expect(lost.length, 1);
      expect(lost[0].item.id, rawChicken.id);
      expect(lost[0].count, 1);

      expect(newState.stackCount, maxLootStacks);
      // Newest item should be at the end
      expect(newState.stacks.last.item.id, feathers.id);
      expect(newState.stacks.last.count, 5);
    });

    test('bones stack even when container is full', () {
      // Create a full loot state with bones as the first item
      final stacks = <ItemStack>[ItemStack(bones, count: 1)];
      for (var i = 1; i < maxLootStacks; i++) {
        stacks.add(ItemStack(rawChicken, count: 1));
      }
      final state = LootState(stacks: stacks);

      expect(state.isFull, true);

      // Add more bones - should stack, not evict
      final (newState, lost) = state.addItem(
        ItemStack(bones, count: 3),
        isBones: true,
      );

      expect(lost, isEmpty);
      expect(newState.stackCount, maxLootStacks);
      expect(newState.stacks[0].item.id, bones.id);
      expect(newState.stacks[0].count, 4); // 1 + 3
    });

    test('new bones type when full evicts oldest item', () {
      // Create a full loot state without any bones
      final stacks = <ItemStack>[];
      for (var i = 0; i < maxLootStacks; i++) {
        stacks.add(ItemStack(rawChicken, count: 1));
      }
      final state = LootState(stacks: stacks);

      expect(state.isFull, true);

      // Add bones (new type) - should evict oldest
      final (newState, lost) = state.addItem(
        ItemStack(bones, count: 2),
        isBones: true,
      );

      expect(lost.length, 1);
      expect(lost[0].item.id, rawChicken.id);

      expect(newState.stackCount, maxLootStacks);
      expect(newState.stacks.last.item.id, bones.id);
      expect(newState.stacks.last.count, 2);
    });
  });

  group('StateUpdateBuilder.collectAllLoot', () {
    test('collects all loot when inventory has space', () {
      final state = GlobalState.test(
        testRegistries,
        loot: LootState(
          stacks: [ItemStack(bones, count: 5), ItemStack(rawChicken, count: 3)],
        ),
      );

      final builder = StateUpdateBuilder(state)..collectAllLoot();
      final result = builder.build();

      // Loot should be empty
      expect(result.loot.isEmpty, true);

      // Items should be in inventory
      expect(result.inventory.countOfItem(bones), 5);
      expect(result.inventory.countOfItem(rawChicken), 3);

      // Changes should track the additions
      expect(builder.changes.inventoryChanges.counts[bones.id], 5);
      expect(builder.changes.inventoryChanges.counts[rawChicken.id], 3);
    });

    test('keeps items in loot when inventory is full', () {
      // Create inventory at capacity - fill all 20 slots with different items
      var inv = Inventory.empty(testItems);
      final itemsToFill = [
        testItems.byName('Normal Logs'),
        testItems.byName('Oak Logs'),
        testItems.byName('Willow Logs'),
        testItems.byName('Teak Logs'),
        testItems.byName('Maple Logs'),
        testItems.byName('Mahogany Logs'),
        testItems.byName('Yew Logs'),
        testItems.byName('Magic Logs'),
        testItems.byName('Redwood Logs'),
        testItems.byName('Raw Shrimp'),
        testItems.byName('Raw Sardine'),
        testItems.byName('Raw Herring'),
        testItems.byName('Raw Trout'),
        testItems.byName('Raw Salmon'),
        testItems.byName('Raw Lobster'),
        testItems.byName('Raw Swordfish'),
        testItems.byName('Raw Crab'),
        testItems.byName('Raw Shark'),
        testItems.byName('Raw Cave Fish'),
        testItems.byName('Raw Manta Ray'),
      ];
      for (final item in itemsToFill) {
        inv = inv.adding(ItemStack(item, count: 1));
      }

      final state = GlobalState.test(
        testRegistries,
        inventory: inv,
        loot: LootState(
          stacks: [ItemStack(bones, count: 5), ItemStack(rawChicken, count: 3)],
        ),
      );

      final builder = StateUpdateBuilder(state)..collectAllLoot();
      final result = builder.build();

      // Loot should still have the items
      expect(result.loot.stackCount, 2);
      expect(result.loot.stacks[0].item.id, bones.id);
      expect(result.loot.stacks[1].item.id, rawChicken.id);

      // Inventory should remain unchanged
      expect(result.inventory.countOfItem(bones), 0);
      expect(result.inventory.countOfItem(rawChicken), 0);
    });

    test('partially collects loot when inventory has limited space', () {
      // Create inventory with only one slot remaining (19 slots filled)
      var inv = Inventory.empty(testItems);
      final itemsToFill = [
        testItems.byName('Normal Logs'),
        testItems.byName('Oak Logs'),
        testItems.byName('Willow Logs'),
        testItems.byName('Teak Logs'),
        testItems.byName('Maple Logs'),
        testItems.byName('Mahogany Logs'),
        testItems.byName('Yew Logs'),
        testItems.byName('Magic Logs'),
        testItems.byName('Redwood Logs'),
        testItems.byName('Raw Shrimp'),
        testItems.byName('Raw Sardine'),
        testItems.byName('Raw Herring'),
        testItems.byName('Raw Trout'),
        testItems.byName('Raw Salmon'),
        testItems.byName('Raw Lobster'),
        testItems.byName('Raw Swordfish'),
        testItems.byName('Raw Crab'),
        testItems.byName('Raw Shark'),
        testItems.byName('Raw Cave Fish'),
      ];
      for (final item in itemsToFill) {
        inv = inv.adding(ItemStack(item, count: 1));
      }

      final state = GlobalState.test(
        testRegistries,
        inventory: inv,
        loot: LootState(
          stacks: [ItemStack(bones, count: 5), ItemStack(rawChicken, count: 3)],
        ),
      );

      final builder = StateUpdateBuilder(state)..collectAllLoot();
      final result = builder.build();

      // First item should be collected, second should remain
      expect(result.inventory.countOfItem(bones), 5);
      expect(result.loot.stackCount, 1);
      expect(result.loot.stacks[0].item.id, rawChicken.id);
    });

    test('collects empty loot without error', () {
      final state = GlobalState.test(testRegistries);

      final builder = StateUpdateBuilder(state)..collectAllLoot();
      final result = builder.build();

      expect(result.loot.isEmpty, true);
      expect(result.inventory.items, isEmpty);
    });
  });

  group('StateUpdateBuilder.addToLoot', () {
    test('tracks overflow items in Changes', () {
      // Create a full loot state
      final stacks = <ItemStack>[];
      for (var i = 0; i < maxLootStacks; i++) {
        stacks.add(ItemStack(rawChicken, count: 1));
      }

      final state = GlobalState.test(
        testRegistries,
        loot: LootState(stacks: stacks),
      );

      final builder = StateUpdateBuilder(state)
        ..addToLoot(ItemStack(feathers, count: 10), isBones: false);

      // The oldest item should be lost and tracked in Changes
      expect(builder.changes.lostFromLoot.counts[rawChicken.id], 1);

      // New item should be in loot
      final result = builder.build();
      expect(result.loot.stacks.last.item.id, feathers.id);
      expect(result.loot.stacks.last.count, 10);
    });

    test('does not track lost items when loot has space', () {
      final state = GlobalState.test(
        testRegistries,
        loot: LootState(stacks: [ItemStack(bones, count: 1)]),
      );

      final builder = StateUpdateBuilder(state)
        ..addToLoot(ItemStack(feathers, count: 5), isBones: false);

      // No items should be lost
      expect(builder.changes.lostFromLoot.isEmpty, true);

      final result = builder.build();
      expect(result.loot.stackCount, 2);
    });

    test('tracks multiple overflow items correctly', () {
      // Create a full loot state
      final stacks = <ItemStack>[];
      for (var i = 0; i < maxLootStacks; i++) {
        stacks.add(ItemStack(rawChicken, count: i + 1));
      }

      final state = GlobalState.test(
        testRegistries,
        loot: LootState(stacks: stacks),
      );

      final builder = StateUpdateBuilder(state)
        // Add two items, causing two evictions
        ..addToLoot(ItemStack(feathers, count: 10), isBones: false)
        ..addToLoot(ItemStack(bones, count: 5), isBones: false);

      // First eviction: rawChicken count 1
      // Second eviction: rawChicken count 2
      // Total lost: 3 rawChicken
      expect(builder.changes.lostFromLoot.counts[rawChicken.id], 3);
    });
  });
}
