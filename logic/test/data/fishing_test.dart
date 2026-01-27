import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
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

    test('areas have junk drop table when junkChance > 0', () {
      final areas = testRegistries.fishing.areas;
      for (final area in areas) {
        if (area.junkChance > 0) {
          expect(
            area.junkDropTable,
            isNotNull,
            reason: '${area.name} has junkChance but no junkDropTable',
          );
        }
      }
    });

    test('areas have special drop table when specialChance > 0', () {
      final areas = testRegistries.fishing.areas;
      for (final area in areas) {
        if (area.specialChance > 0) {
          expect(
            area.specialDropTable,
            isNotNull,
            reason: '${area.name} has specialChance but no specialDropTable',
          );
        }
      }
    });

    test('junk drop table has 8 items', () {
      final areas = testRegistries.fishing.areas;
      final areaWithJunk = areas.firstWhere((a) => a.junkChance > 0);
      final junkTable = areaWithJunk.junkDropTable!;
      expect(junkTable.entries.length, equals(8));
    });

    test('special drop table has gems and rare items', () {
      final areas = testRegistries.fishing.areas;
      final areaWithSpecial = areas.firstWhere((a) => a.specialChance > 0);
      final specialTable = areaWithSpecial.specialDropTable!;
      expect(specialTable.entries.length, greaterThan(0));

      // Check for expected special items (names are human-readable)
      final itemNames = specialTable.entries.map((e) => e.itemID.name).toSet();
      expect(itemNames.contains('Topaz'), isTrue);
      expect(itemNames.contains('Sapphire'), isTrue);
      expect(itemNames.contains('Treasure Chest'), isTrue);
    });
  });

  group('FishingAction with area drops', () {
    test('fishing actions have area reference', () {
      final actions = testRegistries.fishing.actions;
      for (final action in actions) {
        expect(action.area, isNotNull);
        expect(action.area.fishIDs.contains(action.productId), isTrue);
      }
    });

    test('fishing action rewards include junk/special drops', () {
      final actions = testRegistries.fishing.actions;
      // Find an action in an area with both junk and special chances
      final actionWithDrops = actions.firstWhere(
        (a) => a.area.junkChance > 0 && a.area.specialChance > 0,
      );

      final rewards = actionWithDrops.rewardsForSelection(
        const NoSelectedRecipe(),
      );

      // Should have fish output + junk drop + special drop
      expect(rewards.length, equals(3));

      // First reward should be the fish
      expect(rewards[0], isA<Drop>());

      // Second and third should be DropChance wrapping drop tables
      expect(rewards[1], isA<DropChance>());
      expect(rewards[2], isA<DropChance>());
    });

    test('area without junk has only fish and maybe special', () {
      final actions = testRegistries.fishing.actions;
      // Find an action in an area with no junk chance
      final actionNoJunk = actions.firstWhere(
        (a) => a.area.junkChance == 0,
        orElse: () => throw StateError('No area without junk found'),
      );

      final rewards = actionNoJunk.rewardsForSelection(
        const NoSelectedRecipe(),
      );

      // Should have fish output + possibly special
      if (actionNoJunk.area.specialChance > 0) {
        expect(rewards.length, equals(2));
      } else {
        expect(rewards.length, equals(1));
      }
    });
  });
}
