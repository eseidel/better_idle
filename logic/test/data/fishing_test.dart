import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('FishingAreaRegistry', () {
    test('has fishing areas loaded', () {
      final areas = testRegistries.fishingAreas.all;
      expect(areas, isNotEmpty);
    });

    test('byId returns correct area', () {
      final areas = testRegistries.fishingAreas.all;
      expect(areas, isNotEmpty);

      final firstArea = areas.first;
      final foundArea = testRegistries.fishingAreas.byId(firstArea.id);
      expect(foundArea, isNotNull);
      expect(foundArea!.id, equals(firstArea.id));
      expect(foundArea.name, equals(firstArea.name));
    });

    test('byId returns null for unknown id', () {
      const unknownId = MelvorId('test:Unknown_Area');
      final area = testRegistries.fishingAreas.byId(unknownId);
      expect(area, isNull);
    });

    test('areaForFish returns correct area', () {
      final areas = testRegistries.fishingAreas.all;
      expect(areas, isNotEmpty);

      // Find an area with fish
      final areaWithFish = areas.firstWhere((a) => a.fishIDs.isNotEmpty);
      final fishId = areaWithFish.fishIDs.first;

      final foundArea = testRegistries.fishingAreas.areaForFish(fishId);
      expect(foundArea, isNotNull);
      expect(foundArea!.id, equals(areaWithFish.id));
    });

    test('areaForFish returns null for unknown fish id', () {
      const unknownFishId = MelvorId('test:Unknown_Fish');
      final area = testRegistries.fishingAreas.areaForFish(unknownFishId);
      expect(area, isNull);
    });

    test('areas have valid fish chances', () {
      final areas = testRegistries.fishingAreas.all;
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
      final fishingActions = testActions
          .forSkill(Skill.fishing)
          .whereType<FishingAction>()
          .toList();
      expect(fishingActions, isNotEmpty);
    });

    test('fishing actions have valid properties', () {
      final fishingActions = testActions
          .forSkill(Skill.fishing)
          .whereType<FishingAction>()
          .toList();

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
      final fishingActions = testActions
          .forSkill(Skill.fishing)
          .whereType<FishingAction>()
          .toList();

      for (final action in fishingActions) {
        expect(action.skill, equals(Skill.fishing));
      }
    });
  });

  group('FishingArea', () {
    test('areas have non-empty names', () {
      final areas = testRegistries.fishingAreas.all;
      for (final area in areas) {
        expect(area.name, isNotEmpty);
      }
    });

    test('areas have fish IDs', () {
      final areas = testRegistries.fishingAreas.all;
      // At least some areas should have fish
      final areasWithFish = areas.where((a) => a.fishIDs.isNotEmpty);
      expect(areasWithFish, isNotEmpty);
    });
  });
}
