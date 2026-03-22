import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Returns action states with max mastery for all herblore actions,
/// so potion upgrades are unrestricted by mastery.
Map<ActionId, ActionState> _maxHerbloreMastery() {
  final maxMasteryXp = startXpForLevel(99);
  return {
    for (final action in testRegistries.herblore.actions)
      action.id: ActionState(masteryXp: maxMasteryXp),
  };
}

void main() {
  late Item potionI;
  late Item potionII;
  late Item potionIII;
  late Item potionIV;
  late Item normalLogs;

  setUpAll(() async {
    await loadTestRegistries();
    potionI = testItems.byName('Bird Nest Potion I');
    potionII = testItems.byName('Bird Nest Potion II');
    potionIII = testItems.byName('Bird Nest Potion III');
    potionIV = testItems.byName('Bird Nest Potion IV');
    normalLogs = testItems.byName('Normal Logs');
  });

  group('upgradeAllPotions', () {
    test('basic upgrade: 9 tier-I cascades to 1 tier-III', () {
      final state = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 9),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      expect(result.hasUpgrades, isTrue);
      // 9 I -> 3 II (3 upgrades), 3 II -> 1 III (1 upgrade) = 4 total
      expect(result.totalUpgradesMade, 4);
      expect(newState.inventory.countOfItem(potionI), 0);
      expect(newState.inventory.countOfItem(potionII), 0);
      expect(newState.inventory.countOfItem(potionIII), 1);
    });

    test('cascading: 27 tier-I becomes 1 tier-IV', () {
      final state = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 27),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      expect(result.hasUpgrades, isTrue);
      // 27 I -> 9 II (9 upgrades), 9 II -> 3 III (3), 3 III -> 1 IV (1)
      expect(result.totalUpgradesMade, 13);
      expect(newState.inventory.countOfItem(potionI), 0);
      expect(newState.inventory.countOfItem(potionII), 0);
      expect(newState.inventory.countOfItem(potionIII), 0);
      expect(newState.inventory.countOfItem(potionIV), 1);
    });

    test('remainders: 10 tier-I cascades with remainders', () {
      final state = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 10),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      expect(result.hasUpgrades, isTrue);
      // 10 I -> 3 II + 1 I remainder (3 upgrades)
      // 3 II -> 1 III (1 upgrade) = 4 total
      expect(result.totalUpgradesMade, 4);
      expect(newState.inventory.countOfItem(potionI), 1);
      expect(newState.inventory.countOfItem(potionII), 0);
      expect(newState.inventory.countOfItem(potionIII), 1);
    });

    test('no potions: no upgrades', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 100),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      expect(result.hasUpgrades, isFalse);
      expect(result.totalUpgradesMade, 0);
      expect(newState.inventory.countOfItem(normalLogs), 100);
    });

    test('not enough potions: 2 tier-I, no upgrades', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 2),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      expect(result.hasUpgrades, isFalse);
      expect(result.totalUpgradesMade, 0);
      expect(newState.inventory.countOfItem(potionI), 2);
    });

    test('inventory full + output is new item + remainder: skipped', () {
      // Fill inventory to capacity with different items.
      // Use bankSlotsPurchased=0, so capacity = initialBankSlots.
      // We need exactly capacity items, including the potion.
      final state = GlobalState.test(testRegistries);
      final capacity = state.inventoryCapacity;

      // Create filler items plus 4 potions (not enough to fully consume).
      // We need capacity-1 filler items + potionI.
      final fillerItems = <ItemStack>[];
      var added = 0;
      for (final item in testItems.all) {
        if (item == potionI || item == potionII) continue;
        fillerItems.add(ItemStack(item, count: 1));
        added++;
        if (added >= capacity - 1) break;
      }
      fillerItems.add(ItemStack(potionI, count: 4));

      final fullState = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, fillerItems),
      );

      expect(fullState.isInventoryFull, isTrue);
      // potionII is NOT in inventory, so it would need a new slot.
      // 4 potionI / 3 = 1 upgrade with 1 remainder, so input is NOT fully
      // consumed. Should be skipped.
      expect(fullState.inventory.countOfItem(potionII), 0);

      final (newState, result) = fullState.upgradeAllPotions();

      expect(result.hasUpgrades, isFalse);
      expect(newState.inventory.countOfItem(potionI), 4);
    });

    test('inventory full + input fully consumed: allowed (slot freed)', () {
      final state = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
      );
      final capacity = state.inventoryCapacity;

      // Fill with capacity-1 filler + exactly 3 potionI (fully consumed).
      final fillerItems = <ItemStack>[];
      var added = 0;
      for (final item in testItems.all) {
        if (item == potionI || item == potionII) continue;
        fillerItems.add(ItemStack(item, count: 1));
        added++;
        if (added >= capacity - 1) break;
      }
      fillerItems.add(ItemStack(potionI, count: 3));

      final fullState = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
        inventory: Inventory.fromItems(testItems, fillerItems),
      );

      expect(fullState.isInventoryFull, isTrue);
      expect(fullState.inventory.countOfItem(potionII), 0);

      final (newState, result) = fullState.upgradeAllPotions();

      // 3 potionI fully consumed -> 1 potionII, slot freed.
      expect(result.hasUpgrades, isTrue);
      expect(result.totalUpgradesMade, 1);
      expect(newState.inventory.countOfItem(potionI), 0);
      expect(newState.inventory.countOfItem(potionII), 1);
    });

    test('inventory full + output already exists: allowed (stacks)', () {
      final state = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
      );
      final capacity = state.inventoryCapacity;

      // Fill with capacity-2 filler + potionI + potionII (already exists).
      final fillerItems = <ItemStack>[];
      var added = 0;
      for (final item in testItems.all) {
        if (item == potionI || item == potionII) continue;
        fillerItems.add(ItemStack(item, count: 1));
        added++;
        if (added >= capacity - 2) break;
      }
      fillerItems
        ..add(ItemStack(potionI, count: 4))
        ..add(ItemStack(potionII, count: 1));

      final fullState = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
        inventory: Inventory.fromItems(testItems, fillerItems),
      );

      expect(fullState.isInventoryFull, isTrue);
      // potionII IS in inventory, so it can stack.
      expect(fullState.inventory.countOfItem(potionII), 1);

      final (newState, result) = fullState.upgradeAllPotions();

      expect(result.hasUpgrades, isTrue);
      expect(result.totalUpgradesMade, 1);
      expect(newState.inventory.countOfItem(potionI), 1);
      expect(newState.inventory.countOfItem(potionII), 2);
    });

    test('multiple potion types upgraded simultaneously', () {
      // Use a second potion type.
      final otherPotionI = testItems.byName('Lucky Herb Potion I');
      final otherPotionII = testItems.byName('Lucky Herb Potion II');

      final state = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 9),
          ItemStack(otherPotionI, count: 6),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      expect(result.hasUpgrades, isTrue);
      // 9 bird nest I -> 3 II -> 1 III (3+1=4 upgrades)
      // 6 lucky herb I -> 2 II (2 upgrades)
      expect(result.totalUpgradesMade, 6);
      expect(newState.inventory.countOfItem(potionI), 0);
      expect(newState.inventory.countOfItem(potionII), 0);
      expect(newState.inventory.countOfItem(otherPotionI), 0);
      expect(newState.inventory.countOfItem(otherPotionII), 2);
    });
  });

  group('canUpgradeAllPotions', () {
    test('returns true when upgradeable potions exist', () {
      final state = GlobalState.test(
        testRegistries,
        actionStates: _maxHerbloreMastery(),
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 3),
        ]),
      );

      expect(state.canUpgradeAllPotions, isTrue);
    });

    test('returns false when no potions', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 100),
        ]),
      );

      expect(state.canUpgradeAllPotions, isFalse);
    });

    test('returns false when not enough potions', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 2),
        ]),
      );

      expect(state.canUpgradeAllPotions, isFalse);
    });

    test('returns false with empty inventory', () {
      final state = GlobalState.test(testRegistries);
      expect(state.canUpgradeAllPotions, isFalse);
    });

    test('returns false when mastery too low for upgrade', () {
      // At mastery level 1 (default), only tier I is allowed.
      // 3x tier I → 1x tier II should be blocked.
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 3),
        ]),
      );

      expect(state.canUpgradeAllPotions, isFalse);
    });
  });

  group('mastery-gated upgrades', () {
    test('mastery 20 allows upgrade to tier II but not III', () {
      final recipeId = testRegistries.herblore.recipeIdForPotionItem(
        potionI.id,
      )!;
      final action = testRegistries.herblore.byId(recipeId)!;

      final state = GlobalState.test(
        testRegistries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(20))},
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 9),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      // 9 I → 3 II (3 upgrades). Can't go to III (needs mastery 50).
      expect(result.totalUpgradesMade, 3);
      expect(newState.inventory.countOfItem(potionI), 0);
      expect(newState.inventory.countOfItem(potionII), 3);
      expect(newState.inventory.countOfItem(potionIII), 0);
    });

    test('mastery 50 allows upgrade to tier III but not IV', () {
      final recipeId = testRegistries.herblore.recipeIdForPotionItem(
        potionI.id,
      )!;
      final action = testRegistries.herblore.byId(recipeId)!;

      final state = GlobalState.test(
        testRegistries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(50))},
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 27),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      // 27 I → 9 II → 3 III. Can't go to IV (needs mastery 90).
      expect(result.totalUpgradesMade, 12);
      expect(newState.inventory.countOfItem(potionI), 0);
      expect(newState.inventory.countOfItem(potionII), 0);
      expect(newState.inventory.countOfItem(potionIII), 3);
      expect(newState.inventory.countOfItem(potionIV), 0);
    });

    test('mastery 90 allows full cascade to tier IV', () {
      final recipeId = testRegistries.herblore.recipeIdForPotionItem(
        potionI.id,
      )!;
      final action = testRegistries.herblore.byId(recipeId)!;

      final state = GlobalState.test(
        testRegistries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(90))},
        inventory: Inventory.fromItems(testItems, [
          ItemStack(potionI, count: 27),
        ]),
      );

      final (newState, result) = state.upgradeAllPotions();

      expect(result.totalUpgradesMade, 13);
      expect(newState.inventory.countOfItem(potionIV), 1);
    });
  });
}
