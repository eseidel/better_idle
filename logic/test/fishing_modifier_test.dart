import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late FishingAction actionWithJunkAndSpecial;
  late FishingAction actionNoJunk;

  setUpAll(() async {
    await loadTestRegistries();

    // Find a fishing action in an area with both junk and special chances.
    actionWithJunkAndSpecial = testRegistries.fishing.actions.firstWhere(
      (a) => a.area.junkChance > 0 && a.area.specialChance > 0,
    );

    // Find a fishing action in an area with no junk chance.
    actionNoJunk = testRegistries.fishing.actions.firstWhere(
      (a) => a.area.junkChance == 0,
    );
  });

  group('cannotFishJunk modifier', () {
    test('junk drops normally when cannotFishJunk is 0', () {
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final modifiers = StubModifierProvider();

      // Run many iterations to ensure junk has a chance to drop.
      var junkDropped = false;
      for (var i = 0; i < 200; i++) {
        final random = Random(i);
        rollAndCollectDrops(
          builder,
          actionWithJunkAndSpecial,
          modifiers,
          random,
          const NoSelectedRecipe(),
        );
      }

      // Check if any junk item was added to inventory.
      // Junk items are from the fishing junk table.
      final junkTable = testDrops.fishingJunk!;
      for (final entry in junkTable.entries) {
        if (builder.state.inventory.countById(entry.itemID) > 0) {
          junkDropped = true;
          break;
        }
      }
      expect(junkDropped, isTrue, reason: 'Junk should drop without modifier');
    });

    test('junk is suppressed when cannotFishJunk is active', () {
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      // cannotFishJunk > 0 means junk is suppressed.
      final modifiers = StubModifierProvider({'cannotFishJunk': 1});

      for (var i = 0; i < 200; i++) {
        final random = Random(i);
        rollAndCollectDrops(
          builder,
          actionWithJunkAndSpecial,
          modifiers,
          random,
          const NoSelectedRecipe(),
        );
      }

      // No junk items should have been added.
      final junkTable = testDrops.fishingJunk!;
      for (final entry in junkTable.entries) {
        expect(
          builder.state.inventory.countById(entry.itemID),
          equals(0),
          reason:
              'Junk item ${entry.itemID} should not drop with '
              'cannotFishJunk active',
        );
      }
    });
  });

  group('fishingSpecialChance modifier', () {
    test('special items drop more often with fishingSpecialChance bonus', () {
      // Run with and without modifier, compare special item counts.
      var specialCountWithout = 0;
      var specialCountWith = 0;
      final specialTable = testDrops.fishingSpecial!;
      final specialIds = specialTable.entries.map((e) => e.itemID).toSet();

      for (var i = 0; i < 500; i++) {
        // Without modifier
        final state1 = GlobalState.test(testRegistries);
        final builder1 = StateUpdateBuilder(state1);
        final random1 = Random(i);
        rollAndCollectDrops(
          builder1,
          actionWithJunkAndSpecial,
          StubModifierProvider(),
          random1,
          const NoSelectedRecipe(),
        );
        for (final id in specialIds) {
          specialCountWithout += builder1.state.inventory.countById(id);
        }

        // With 100% bonus to fishingSpecialChance
        final state2 = GlobalState.test(testRegistries);
        final builder2 = StateUpdateBuilder(state2);
        final random2 = Random(i);
        rollAndCollectDrops(
          builder2,
          actionWithJunkAndSpecial,
          StubModifierProvider({'fishingSpecialChance': 100}),
          random2,
          const NoSelectedRecipe(),
        );
        for (final id in specialIds) {
          specialCountWith += builder2.state.inventory.countById(id);
        }
      }

      expect(
        specialCountWith,
        greaterThan(specialCountWithout),
        reason: 'fishingSpecialChance should increase special drops',
      );
    });
  });

  group('bonusFishingSpecialChance modifier', () {
    test('increases special item drop rate', () {
      var specialCountWithout = 0;
      var specialCountWith = 0;
      final specialTable = testDrops.fishingSpecial!;
      final specialIds = specialTable.entries.map((e) => e.itemID).toSet();

      for (var i = 0; i < 500; i++) {
        // Without modifier
        final state1 = GlobalState.test(testRegistries);
        final builder1 = StateUpdateBuilder(state1);
        final random1 = Random(i);
        rollAndCollectDrops(
          builder1,
          actionWithJunkAndSpecial,
          StubModifierProvider(),
          random1,
          const NoSelectedRecipe(),
        );
        for (final id in specialIds) {
          specialCountWithout += builder1.state.inventory.countById(id);
        }

        // With bonus (action-scoped)
        final state2 = GlobalState.test(testRegistries);
        final builder2 = StateUpdateBuilder(state2);
        final random2 = Random(i);
        rollAndCollectDrops(
          builder2,
          actionWithJunkAndSpecial,
          StubModifierProvider({'bonusFishingSpecialChance': 100}),
          random2,
          const NoSelectedRecipe(),
        );
        for (final id in specialIds) {
          specialCountWith += builder2.state.inventory.countById(id);
        }
      }

      expect(
        specialCountWith,
        greaterThan(specialCountWithout),
        reason: 'bonusFishingSpecialChance should increase special drops',
      );
    });
  });

  group('fishingAdditionalSpecialItemChance modifier', () {
    test('increases special item drop rate', () {
      var specialCountWithout = 0;
      var specialCountWith = 0;
      final specialTable = testDrops.fishingSpecial!;
      final specialIds = specialTable.entries.map((e) => e.itemID).toSet();

      for (var i = 0; i < 500; i++) {
        // Without modifier
        final state1 = GlobalState.test(testRegistries);
        final builder1 = StateUpdateBuilder(state1);
        final random1 = Random(i);
        rollAndCollectDrops(
          builder1,
          actionWithJunkAndSpecial,
          StubModifierProvider(),
          random1,
          const NoSelectedRecipe(),
        );
        for (final id in specialIds) {
          specialCountWithout += builder1.state.inventory.countById(id);
        }

        // With modifier
        final state2 = GlobalState.test(testRegistries);
        final builder2 = StateUpdateBuilder(state2);
        final random2 = Random(i);
        rollAndCollectDrops(
          builder2,
          actionWithJunkAndSpecial,
          StubModifierProvider({'fishingAdditionalSpecialItemChance': 100}),
          random2,
          const NoSelectedRecipe(),
        );
        for (final id in specialIds) {
          specialCountWith += builder2.state.inventory.countById(id);
        }
      }

      expect(
        specialCountWith,
        greaterThan(specialCountWithout),
        reason:
            'fishingAdditionalSpecialItemChance should increase special drops',
      );
    });
  });

  group('fishingCookedChance modifier', () {
    test('raw fish is replaced with cooked fish when modifier triggers', () {
      final rawFishId = actionWithJunkAndSpecial.productId;
      final cookedId = testRegistries.cooking.cookedForRaw(rawFishId);

      // Skip if no cooking recipe exists for this fish.
      if (cookedId == null) {
        // Try another action that has a cooking counterpart.
        final actionWithCooking = testRegistries.fishing.actions.firstWhere(
          (a) => testRegistries.cooking.cookedForRaw(a.productId) != null,
          orElse: () => throw StateError(
            'No fishing action has a matching cooking recipe',
          ),
        );
        _testCookedChance(actionWithCooking);
        return;
      }

      _testCookedChance(actionWithJunkAndSpecial);
    });

    test('raw fish drops normally when fishingCookedChance is 0', () {
      final action = testRegistries.fishing.actions.firstWhere(
        (a) => testRegistries.cooking.cookedForRaw(a.productId) != null,
        orElse: () =>
            throw StateError('No fishing action has a matching cooking recipe'),
      );
      final rawFishId = action.productId;
      final cookedId = testRegistries.cooking.cookedForRaw(rawFishId)!;

      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);
      final modifiers = StubModifierProvider();

      // Run enough iterations to get drops.
      for (var i = 0; i < 100; i++) {
        final random = Random(i);
        rollAndCollectDrops(
          builder,
          action,
          modifiers,
          random,
          const NoSelectedRecipe(),
        );
      }

      // Should have raw fish and no cooked fish.
      expect(
        builder.state.inventory.countById(rawFishId),
        greaterThan(0),
        reason: 'Should get raw fish',
      );
      expect(
        builder.state.inventory.countById(cookedId),
        equals(0),
        reason: 'Should not get cooked fish without modifier',
      );
    });
  });

  group('FishingJunkDrop and FishingSpecialDrop types', () {
    test('allDropsForAction returns tagged fishing drop types', () {
      final drops = testDrops.allDropsForAction(
        actionWithJunkAndSpecial,
        const NoSelectedRecipe(),
      );

      final junkDrops = drops.whereType<FishingJunkDrop>().toList();
      final specialDrops = drops.whereType<FishingSpecialDrop>().toList();

      expect(junkDrops.length, equals(1));
      expect(specialDrops.length, equals(1));
    });

    test('area without junk has no FishingJunkDrop', () {
      final drops = testDrops.allDropsForAction(
        actionNoJunk,
        const NoSelectedRecipe(),
      );
      final junkDrops = drops.whereType<FishingJunkDrop>().toList();
      expect(junkDrops, isEmpty);
    });
  });

  group('CookingRegistry.cookedForRaw', () {
    test('returns cooked item for raw fish', () {
      // Raw Shrimp -> Shrimp (cooked)
      const rawShrimpId = MelvorId('melvorD:Raw_Shrimp');
      final cookedId = testRegistries.cooking.cookedForRaw(rawShrimpId);
      expect(cookedId, isNotNull);
      expect(cookedId!.name, equals('Shrimp'));
    });

    test('returns null for non-cookable item', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final cookedId = testRegistries.cooking.cookedForRaw(normalLogsId);
      expect(cookedId, isNull);
    });
  });
}

/// Helper to test the fishingCookedChance modifier with a given action.
void _testCookedChance(FishingAction action) {
  final rawFishId = action.productId;
  final cookedId = testRegistries.cooking.cookedForRaw(rawFishId)!;

  // Use 100% cooked chance to guarantee replacement.
  final state = GlobalState.test(testRegistries);
  final builder = StateUpdateBuilder(state);
  final modifiers = StubModifierProvider({'fishingCookedChance': 100});

  for (var i = 0; i < 100; i++) {
    final random = Random(i);
    rollAndCollectDrops(
      builder,
      action,
      modifiers,
      random,
      const NoSelectedRecipe(),
    );
  }

  // Should have cooked fish, not raw.
  expect(
    builder.state.inventory.countById(cookedId),
    greaterThan(0),
    reason: 'Should get cooked fish with 100% fishingCookedChance',
  );
  expect(
    builder.state.inventory.countById(rawFishId),
    equals(0),
    reason: 'Should not get raw fish with 100% fishingCookedChance',
  );
}
