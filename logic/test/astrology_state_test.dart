import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('ConstellationModifierState', () {
    group('toJson/fromJson', () {
      test('round-trips empty state', () {
        const original = ConstellationModifierState.empty();

        final json = original.toJson();
        final restored = ConstellationModifierState.fromJson(json);

        expect(restored.standardLevels, isEmpty);
        expect(restored.uniqueLevels, isEmpty);
      });

      test('round-trips with standard levels only', () {
        const original = ConstellationModifierState(
          standardLevels: [1, 3, 0, 5],
        );

        final json = original.toJson();
        final restored = ConstellationModifierState.fromJson(json);

        expect(restored.standardLevels, [1, 3, 0, 5]);
        expect(restored.uniqueLevels, isEmpty);
      });

      test('round-trips with unique levels only', () {
        const original = ConstellationModifierState(uniqueLevels: [2, 4]);

        final json = original.toJson();
        final restored = ConstellationModifierState.fromJson(json);

        expect(restored.standardLevels, isEmpty);
        expect(restored.uniqueLevels, [2, 4]);
      });

      test('round-trips with both standard and unique levels', () {
        const original = ConstellationModifierState(
          standardLevels: [1, 2, 3],
          uniqueLevels: [4, 5],
        );

        final json = original.toJson();
        final restored = ConstellationModifierState.fromJson(json);

        expect(restored.standardLevels, [1, 2, 3]);
        expect(restored.uniqueLevels, [4, 5]);
      });

      test('handles missing keys in json', () {
        final restored = ConstellationModifierState.fromJson(const {});

        expect(restored.standardLevels, isEmpty);
        expect(restored.uniqueLevels, isEmpty);
      });

      test('handles null values in json', () {
        final restored = ConstellationModifierState.fromJson(const {
          'standardLevels': null,
          'uniqueLevels': null,
        });

        expect(restored.standardLevels, isEmpty);
        expect(restored.uniqueLevels, isEmpty);
      });
    });
  });

  group('AstrologyState', () {
    group('toJson/fromJson', () {
      test('round-trips empty state', () {
        const original = AstrologyState.empty();

        final json = original.toJson();
        final restored = AstrologyState.fromJson(json);

        expect(restored.constellationStates, isEmpty);
      });

      test('round-trips with constellation states', () {
        const constellationId = MelvorId('melvorF:Deedree');
        final original = AstrologyState(
          constellationStates: {
            constellationId: const ConstellationModifierState(
              standardLevels: [1, 2],
              uniqueLevels: [3],
            ),
          },
        );

        final json = original.toJson();
        final restored = AstrologyState.fromJson(json);

        expect(restored.constellationStates.length, 1);
        expect(restored.constellationStates[constellationId], isNotNull);
        expect(restored.constellationStates[constellationId]!.standardLevels, [
          1,
          2,
        ]);
        expect(restored.constellationStates[constellationId]!.uniqueLevels, [
          3,
        ]);
      });

      test('round-trips with multiple constellations', () {
        const constId1 = MelvorId('melvorF:Deedree');
        const constId2 = MelvorId('melvorF:Iridan');
        final original = AstrologyState(
          constellationStates: {
            constId1: const ConstellationModifierState(standardLevels: [5]),
            constId2: const ConstellationModifierState(uniqueLevels: [2, 3]),
          },
        );

        final json = original.toJson();
        final restored = AstrologyState.fromJson(json);

        expect(restored.constellationStates.length, 2);
        expect(restored.constellationStates[constId1]!.standardLevels, [5]);
        expect(restored.constellationStates[constId2]!.uniqueLevels, [2, 3]);
      });

      test('handles missing constellationStates key', () {
        final restored = AstrologyState.fromJson(const {});

        expect(restored.constellationStates, isEmpty);
      });
    });
  });
}
