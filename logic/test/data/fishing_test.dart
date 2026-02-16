import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  late Item messageInABottle;
  late Item barbarianGloves;
  late FishingArea secretArea;
  late FishingArea barbarianFishingArea;
  late FishingArea normalArea;

  setUpAll(() async {
    await loadTestRegistries();
    messageInABottle = testItems.byName('Message in a Bottle');
    barbarianGloves = testItems.byName('Barbarian Gloves');
    secretArea = testRegistries.fishing.areaById(
      const MelvorId('melvorD:SecretArea'),
    )!;
    barbarianFishingArea = testRegistries.fishing.areaById(
      const MelvorId('melvorD:BarbarianFishing'),
    )!;
    // Get a normal area (not secret, no required item)
    normalArea = testRegistries.fishing.areas.firstWhere(
      (a) => !a.isSecret && a.requiredItemID == null,
    );
  });

  group('FishingRegistry areas', () {
    test('has fishing areas loaded', () {
      final areas = testRegistries.fishing.areas;
      expect(areas, isNotEmpty);
    });

    test('areaById returns correct area', () {
      final areas = testRegistries.fishing.areas;
      expect(areas, isNotEmpty);

      final firstArea = areas.first;
      final foundArea = testRegistries.fishing.areaById(firstArea.id);
      expect(foundArea, isNotNull);
      expect(foundArea!.id, equals(firstArea.id));
      expect(foundArea.name, equals(firstArea.name));
    });

    test('areaById returns null for unknown id', () {
      const unknownId = MelvorId('test:Unknown_Area');
      final area = testRegistries.fishing.areaById(unknownId);
      expect(area, isNull);
    });

    test('areaForFish returns correct area', () {
      final areas = testRegistries.fishing.areas;
      expect(areas, isNotEmpty);

      // Find an area with fish
      final areaWithFish = areas.firstWhere((a) => a.fishIDs.isNotEmpty);
      final fishId = areaWithFish.fishIDs.first;

      final foundArea = testRegistries.fishing.areaForFish(fishId);
      expect(foundArea, isNotNull);
      expect(foundArea!.id, equals(areaWithFish.id));
    });

    test('areaForFish returns null for unknown fish id', () {
      const unknownFishId = MelvorId('test:Unknown_Fish');
      final area = testRegistries.fishing.areaForFish(unknownFishId);
      expect(area, isNull);
    });

    test('areas have valid fish chances', () {
      final areas = testRegistries.fishing.areas;
      for (final area in areas) {
        expect(area.fishChance, greaterThanOrEqualTo(0));
        expect(area.fishChance, lessThanOrEqualTo(1));
        expect(area.junkChance, greaterThanOrEqualTo(0));
        expect(area.junkChance, lessThanOrEqualTo(1));
        expect(area.specialChance, greaterThanOrEqualTo(0));
        expect(area.specialChance, lessThanOrEqualTo(1));
      }
    });
  });

  group('FishingAction', () {
    test('fishing actions are loaded from JSON', () {
      final fishingActions = testRegistries.fishing.actions;
      expect(fishingActions, isNotEmpty);
    });

    test('fishing actions have valid properties', () {
      final fishingActions = testRegistries.fishing.actions;

      for (final action in fishingActions) {
        expect(action.name, isNotEmpty);
        expect(action.unlockLevel, greaterThanOrEqualTo(1));
        expect(action.xp, greaterThan(0));
        expect(action.minDuration.inMilliseconds, greaterThan(0));
        expect(
          action.maxDuration.inMilliseconds,
          greaterThanOrEqualTo(action.minDuration.inMilliseconds),
        );
        expect(action.outputs, isNotEmpty);
      }
    });

    test('fishing actions belong to fishing skill', () {
      final fishingActions = testRegistries.fishing.actions;

      for (final action in fishingActions) {
        expect(action.skill, equals(Skill.fishing));
      }
    });
  });

  group('FishingArea', () {
    test('areas have non-empty names', () {
      final areas = testRegistries.fishing.areas;
      for (final area in areas) {
        expect(area.name, isNotEmpty);
      }
    });

    test('areas have fish IDs', () {
      final areas = testRegistries.fishing.areas;
      // At least some areas should have fish
      final areasWithFish = areas.where((a) => a.fishIDs.isNotEmpty);
      expect(areasWithFish, isNotEmpty);
    });
  });

  group('Fishing junk/special drops', () {
    test('DropsRegistry has fishing junk table', () {
      expect(testDrops.fishingJunk, isNotNull);
      expect(testDrops.fishingJunk!.entries.length, equals(8));
    });

    test('DropsRegistry has fishing special table', () {
      expect(testDrops.fishingSpecial, isNotNull);
      expect(testDrops.fishingSpecial!.entries.length, greaterThan(0));

      // Check for expected special items (names are human-readable)
      final itemNames = testDrops.fishingSpecial!.entries
          .map((e) => e.itemID.name)
          .toSet();
      expect(itemNames.contains('Topaz'), isTrue);
      expect(itemNames.contains('Sapphire'), isTrue);
      expect(itemNames.contains('Treasure Chest'), isTrue);
    });

    test('fishing actions have area reference', () {
      final actions = testRegistries.fishing.actions;
      for (final action in actions) {
        expect(action.area, isNotNull);
        expect(action.area.fishIDs.contains(action.productId), isTrue);
      }
    });

    test('allDropsForAction includes junk/special for fishing', () {
      final actions = testRegistries.fishing.actions;
      // Find an action in an area with both junk and special chances
      final actionWithDrops = actions.firstWhere(
        (a) => a.area.junkChance > 0 && a.area.specialChance > 0,
      );

      final drops = testDrops.allDropsForAction(
        actionWithDrops,
        const NoSelectedRecipe(),
      );

      // Should include at least the fish output, junk drop, and special drop
      // (may also include skill-level rare drops like rings)
      expect(drops.length, greaterThanOrEqualTo(3));

      // First drop should be the fish
      expect(drops[0], isA<Drop>());

      // Last two should be DropChance wrapping junk/special tables
      final dropChances = drops.whereType<DropChance>().toList();
      expect(dropChances.length, equals(2));
    });

    test('allDropsForAction excludes junk when area has 0% junk chance', () {
      final actions = testRegistries.fishing.actions;
      // Find an action in an area with no junk chance
      final actionNoJunk = actions.firstWhere(
        (a) => a.area.junkChance == 0,
        orElse: () => throw StateError('No area without junk found'),
      );

      final drops = testDrops.allDropsForAction(
        actionNoJunk,
        const NoSelectedRecipe(),
      );

      // Count DropChance instances (junk/special wrappers)
      final dropChances = drops.whereType<DropChance>().toList();

      // Should have 0 or 1 DropChance (special only if specialChance > 0)
      if (actionNoJunk.area.specialChance > 0) {
        expect(dropChances.length, equals(1));
      } else {
        expect(dropChances.length, equals(0));
      }
    });
  });

  group('Fishing area visibility', () {
    test('normal areas are always visible', () {
      final state = GlobalState.test(testRegistries);
      expect(state.isFishingAreaVisible(normalArea), isTrue);
    });

    test('secret area is hidden by default', () {
      final state = GlobalState.test(testRegistries);
      expect(secretArea.isSecret, isTrue);
      expect(state.isFishingAreaVisible(secretArea), isFalse);
    });

    test('secret area is visible after reading message in a bottle', () {
      var state = GlobalState.test(testRegistries);
      expect(state.isFishingAreaVisible(secretArea), isFalse);

      state = state.readItem(messageInABottle.id);
      expect(state.hasReadItem(messageInABottle.id), isTrue);
      expect(state.isFishingAreaVisible(secretArea), isTrue);
    });

    test('barbarian fishing area requires gloves equipped', () {
      final state = GlobalState.test(testRegistries);
      expect(barbarianFishingArea.requiredItemID, isNotNull);
      expect(state.isFishingAreaVisible(barbarianFishingArea), isFalse);
    });

    test('barbarian fishing area is visible with gloves equipped', () {
      // Equip the barbarian gloves
      const equipment = Equipment.empty();
      final (equippedEquipment, _) = equipment.equipGear(
        barbarianGloves,
        EquipmentSlot.gloves,
      );
      final state = GlobalState.test(
        testRegistries,
        equipment: equippedEquipment,
      );
      expect(state.isFishingAreaVisible(barbarianFishingArea), isTrue);
    });

    test('readItem throws for non-readable items', () {
      final state = GlobalState.test(testRegistries);
      final normalLogs = testItems.byName('Normal Logs');
      expect(() => state.readItem(normalLogs.id), throwsA(isA<StateError>()));
    });

    test('readItem is idempotent', () {
      var state = GlobalState.test(testRegistries);
      state = state.readItem(messageInABottle.id);
      final state2 = state.readItem(messageInABottle.id);
      // Should return same state (no change)
      expect(identical(state, state2), isTrue);
    });

    test('readItems persists through JSON serialization', () {
      var state = GlobalState.test(testRegistries);
      state = state.readItem(messageInABottle.id);

      final json = state.toJson();
      final loadedState = GlobalState.fromJson(testRegistries, json);

      expect(loadedState.hasReadItem(messageInABottle.id), isTrue);
      expect(loadedState.isFishingAreaVisible(secretArea), isTrue);
    });

    test('message in a bottle is a readable item', () {
      expect(messageInABottle.isReadable, isTrue);
    });
  });
}
