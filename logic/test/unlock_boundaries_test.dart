import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/unlock_boundaries.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('SkillBoundaries', () {
    test('nextBoundary returns next level above current', () {
      const boundaries = SkillBoundaries(Skill.woodcutting, [1, 10, 25, 35]);

      expect(boundaries.nextBoundary(0), 1);
      expect(boundaries.nextBoundary(1), 10);
      expect(boundaries.nextBoundary(5), 10);
      expect(boundaries.nextBoundary(10), 25);
      expect(boundaries.nextBoundary(20), 25);
      expect(boundaries.nextBoundary(25), 35);
      expect(boundaries.nextBoundary(30), 35);
      expect(boundaries.nextBoundary(35), null);
      expect(boundaries.nextBoundary(99), null);
    });

    test('boundaryIndex returns correct zone index', () {
      const boundaries = SkillBoundaries(Skill.woodcutting, [1, 10, 25, 35]);

      expect(boundaries.boundaryIndex(0), 0); // Before first boundary
      expect(boundaries.boundaryIndex(1), 1); // At first boundary
      expect(boundaries.boundaryIndex(5), 1); // Between first and second
      expect(boundaries.boundaryIndex(10), 2); // At second boundary
      expect(boundaries.boundaryIndex(20), 2); // Between second and third
      expect(boundaries.boundaryIndex(25), 3); // At third boundary
      expect(boundaries.boundaryIndex(30), 3); // Between third and fourth
      expect(boundaries.boundaryIndex(35), 4); // At fourth boundary
      expect(boundaries.boundaryIndex(99), 4); // Past all boundaries
    });
  });

  group('computeUnlockBoundaries', () {
    test('produces boundaries for all skills', () {
      final boundaries = computeUnlockBoundaries(testRegistries);

      // Should have boundaries for all skills
      expect(boundaries.keys.toSet(), Skill.values.toSet());
    });

    test('includes level 1 for all skills', () {
      final boundaries = computeUnlockBoundaries(testRegistries);

      for (final skill in Skill.values) {
        final skillBoundaries = boundaries[skill]!;
        expect(
          skillBoundaries.boundaries,
          contains(1),
          reason: '${skill.name} should include level 1',
        );
      }
    });

    test('boundaries are sorted in ascending order', () {
      final boundaries = computeUnlockBoundaries(testRegistries);

      for (final entry in boundaries.entries) {
        final levels = entry.value.boundaries;
        final sorted = [...levels]..sort();
        expect(
          levels,
          sorted,
          reason: '${entry.key.name} boundaries should be sorted',
        );
      }
    });

    test('includes action unlock levels', () {
      final boundaries = computeUnlockBoundaries(testRegistries);

      // Woodcutting should include tree unlock levels
      final wcBoundaries = boundaries[Skill.woodcutting]!.boundaries;
      // Normal Tree unlocks at level 1
      expect(wcBoundaries, contains(1));
      // Oak Tree unlocks at level 10
      expect(wcBoundaries, contains(10));

      // Fishing should include fish unlock levels
      final fishBoundaries = boundaries[Skill.fishing]!.boundaries;
      // Raw Shrimp unlocks at level 1
      expect(fishBoundaries, contains(1));
      // Raw Sardine unlocks at level 5
      expect(fishBoundaries, contains(5));
    });

    test('has no duplicate levels', () {
      final boundaries = computeUnlockBoundaries(testRegistries);

      for (final entry in boundaries.entries) {
        final levels = entry.value.boundaries;
        final unique = levels.toSet();
        expect(
          levels.length,
          unique.length,
          reason: '${entry.key.name} should have no duplicate boundaries',
        );
      }
    });

    test('woodcutting has reasonable number of boundaries', () {
      final boundaries = computeUnlockBoundaries(testRegistries);
      final wcBoundaries = boundaries[Skill.woodcutting]!.boundaries;

      // Should have at least a few tree types
      expect(wcBoundaries.length, greaterThanOrEqualTo(5));
      // But not an excessive number
      expect(wcBoundaries.length, lessThan(30));
    });

    test('fishing has reasonable number of boundaries', () {
      final boundaries = computeUnlockBoundaries(testRegistries);
      final fishBoundaries = boundaries[Skill.fishing]!.boundaries;

      // Should have at least a few fish types
      expect(fishBoundaries.length, greaterThanOrEqualTo(5));
      // But not an excessive number
      expect(fishBoundaries.length, lessThan(30));
    });
  });
}
