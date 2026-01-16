import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  late Item normalLogs;
  late Item oakLogs;
  late Item birdNest;
  late Item lobster;

  setUpAll(() async {
    await loadTestRegistries();
    normalLogs = testItems.byName('Normal Logs');
    oakLogs = testItems.byName('Oak Logs');
    birdNest = testItems.byName('Bird Nest');
    lobster = testItems.byName('Lobster');
  });

  group('Inventory.canAdd', () {
    test('returns true when inventory has existing stack of item', () {
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
        ItemStack(oakLogs, count: 3),
      ]);
      // Can add more normal logs even if at capacity
      expect(inventory.canAdd(normalLogs, capacity: 2), isTrue);
    });

    test('returns true when inventory has room for new item', () {
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
      ]);
      // Can add oak logs because we have room (1 slot used, capacity 2)
      expect(inventory.canAdd(oakLogs, capacity: 2), isTrue);
    });

    test('returns false when inventory is full with different items', () {
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
        ItemStack(oakLogs, count: 3),
      ]);
      // Cannot add bird nest because inventory is full (2 slots, capacity 2)
      expect(inventory.canAdd(birdNest, capacity: 2), isFalse);
    });

    test('returns true for empty inventory', () {
      final inventory = Inventory.empty(testItems);
      expect(inventory.canAdd(normalLogs, capacity: 20), isTrue);
    });
  });

  group('Inventory.sorted', () {
    test('sorts items using custom comparator', () {
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(birdNest, count: 1),
        ItemStack(lobster, count: 2),
        ItemStack(normalLogs, count: 3),
        ItemStack(oakLogs, count: 4),
      ]);

      // Sort alphabetically by name
      final sorted = inventory.sorted((a, b) => a.name.compareTo(b.name));
      final items = sorted.items;

      // Items should be in alphabetical order
      expect(items.length, 4);
      expect(items[0].item, birdNest); // Bird Nest
      expect(items[0].count, 1);
      expect(items[1].item, lobster); // Lobster
      expect(items[1].count, 2);
      expect(items[2].item, normalLogs); // Normal Logs
      expect(items[2].count, 3);
      expect(items[3].item, oakLogs); // Oak Logs
      expect(items[3].count, 4);
    });

    test('preserves item counts after sorting', () {
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(oakLogs, count: 100),
        ItemStack(normalLogs, count: 50),
      ]);

      final sorted = inventory.sorted();

      expect(sorted.countOfItem(normalLogs), 50);
      expect(sorted.countOfItem(oakLogs), 100);
    });

    test('sorting empty inventory returns empty inventory', () {
      final inventory = Inventory.empty(testItems);
      final sorted = inventory.sorted();
      expect(sorted.items, isEmpty);
    });

    test('sorting single item inventory returns same item', () {
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(normalLogs, count: 5),
      ]);

      final sorted = inventory.sorted();

      expect(sorted.items.length, 1);
      expect(sorted.items[0].item, normalLogs);
      expect(sorted.items[0].count, 5);
    });
  });

  group('Inventory.totalAcquired', () {
    test('hasEverAcquired returns false for never-acquired items', () {
      final inventory = Inventory.empty(testItems);
      expect(inventory.hasEverAcquired(normalLogs.id), isFalse);
    });

    test('hasEverAcquired returns true after adding item', () {
      var inventory = Inventory.empty(testItems);
      inventory = inventory.adding(ItemStack(normalLogs, count: 1));
      expect(inventory.hasEverAcquired(normalLogs.id), isTrue);
    });

    test('totalAcquiredCount accumulates across multiple adds', () {
      var inventory = Inventory.empty(testItems);
      inventory = inventory.adding(ItemStack(normalLogs, count: 5));
      inventory = inventory.adding(ItemStack(normalLogs, count: 3));
      expect(inventory.totalAcquiredCount(normalLogs.id), 8);
    });

    test('removing does not decrement totalAcquired', () {
      var inventory = Inventory.empty(testItems);
      inventory = inventory.adding(ItemStack(normalLogs, count: 10));
      inventory = inventory.removing(ItemStack(normalLogs, count: 7));

      // Current count should be 3
      expect(inventory.countOfItem(normalLogs), 3);
      // Total acquired should still be 10
      expect(inventory.totalAcquiredCount(normalLogs.id), 10);
      // hasEverAcquired should still be true
      expect(inventory.hasEverAcquired(normalLogs.id), isTrue);
    });

    test('removing all items still tracks totalAcquired', () {
      var inventory = Inventory.empty(testItems);
      inventory = inventory.adding(ItemStack(normalLogs, count: 5));
      inventory = inventory.removing(ItemStack(normalLogs, count: 5));

      // Item should be removed from inventory
      expect(inventory.countOfItem(normalLogs), 0);
      // But still tracked as ever acquired
      expect(inventory.hasEverAcquired(normalLogs.id), isTrue);
      expect(inventory.totalAcquiredCount(normalLogs.id), 5);
    });

    test('sorting preserves totalAcquired', () {
      var inventory = Inventory.empty(testItems);
      inventory = inventory.adding(ItemStack(normalLogs, count: 5));
      inventory = inventory.adding(ItemStack(oakLogs, count: 3));
      inventory = inventory.sorted();

      expect(inventory.totalAcquiredCount(normalLogs.id), 5);
      expect(inventory.totalAcquiredCount(oakLogs.id), 3);
    });

    test('JSON round-trip preserves totalAcquired', () {
      var inventory = Inventory.empty(testItems);
      inventory = inventory.adding(ItemStack(normalLogs, count: 5));
      inventory = inventory.adding(ItemStack(oakLogs, count: 3));

      final json = inventory.toJson();
      final restored = Inventory.fromJson(testItems, json);

      expect(restored.totalAcquiredCount(normalLogs.id), 5);
      expect(restored.totalAcquiredCount(oakLogs.id), 3);
      expect(restored.hasEverAcquired(normalLogs.id), isTrue);
      expect(restored.hasEverAcquired(birdNest.id), isFalse);
    });

    test('fromJson handles missing totalAcquired for backwards compat', () {
      // Simulate old save format without totalAcquired
      final oldJson = {
        'counts': {normalLogs.id.toJson(): 5},
        'orderedItems': [normalLogs.id.toJson()],
        // No totalAcquired key
      };

      final inventory = Inventory.fromJson(testItems, oldJson);

      // Should load without error, totalAcquired starts empty
      expect(inventory.countOfItem(normalLogs), 5);
      expect(inventory.hasEverAcquired(normalLogs.id), isFalse);
    });
  });
}
