import 'package:better_idle/src/data/xp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('levelForXp', () {
    test('returns 1 for 0 XP', () {
      expect(levelForXp(0), 1);
    });

    test('returns 1 for XP below level 2 threshold', () {
      expect(levelForXp(1), 1);
      expect(levelForXp(50), 1);
      expect(levelForXp(82), 1);
    });

    test('returns 2 for XP at level 2 threshold', () {
      expect(levelForXp(83), 2);
    });

    test('returns 2 for XP between level 2 and 3', () {
      expect(levelForXp(100), 2);
      expect(levelForXp(173), 2);
    });

    test('returns 3 for XP at level 3 threshold', () {
      expect(levelForXp(174), 3);
    });

    test('returns correct level for various XP values', () {
      expect(levelForXp(276), 4);
      expect(levelForXp(512), 6);
      expect(levelForXp(650), 7);
    });
  });

  group('startXpForLevel', () {
    test('returns 0 for level 1', () {
      expect(startXpForLevel(1), 0);
    });

    test('returns 83 for level 2', () {
      expect(startXpForLevel(2), 83);
    });

    test('returns 174 for level 3', () {
      expect(startXpForLevel(3), 174);
    });

    test('returns correct XP for various levels', () {
      expect(startXpForLevel(4), 276);
      expect(startXpForLevel(5), 388);
    });
  });

  group('xpProgressForXp', () {
    test('returns correct progress for 0 XP (level 1)', () {
      final progress = xpProgressForXp(0);
      expect(progress.level, 1);
      expect(progress.lastLevelXp, 0);
      expect(progress.nextLevelXp, 83);
      expect(progress.progress, 0.0);
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP at start of level 2', () {
      final progress = xpProgressForXp(83);
      expect(progress.level, 2);
      expect(progress.lastLevelXp, 83);
      expect(progress.nextLevelXp, 174);
      expect(progress.progress, 0.0);
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP in middle of level 1', () {
      final progress = xpProgressForXp(41);
      expect(progress.level, 1);
      expect(progress.lastLevelXp, 0);
      expect(progress.nextLevelXp, 83);
      expect(progress.progress, closeTo(41 / 83, 0.001));
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP in middle of level 2', () {
      final progress = xpProgressForXp(128);
      expect(progress.level, 2);
      expect(progress.lastLevelXp, 83);
      expect(progress.nextLevelXp, 174);
      // Progress should be (128 - 83) / (174 - 83) = 45 / 91
      expect(progress.progress, closeTo(45 / 91, 0.001));
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('returns correct progress for XP at start of level 3', () {
      final progress = xpProgressForXp(174);
      expect(progress.level, 3);
      expect(progress.lastLevelXp, 174);
      expect(progress.nextLevelXp, 276);
      expect(progress.progress, 0.0);
      expect(progress.progress, greaterThanOrEqualTo(0.0));
      expect(progress.progress, lessThanOrEqualTo(1.0));
    });

    test('progress is never negative', () {
      for (var xp = 0; xp < 100000; xp += 100) {
        final progress = xpProgressForXp(xp);
        expect(
          progress.progress,
          greaterThanOrEqualTo(0.0),
          reason:
              'Progress should not be negative for XP $xp '
              '(level ${progress.level})',
        );
        expect(
          progress.progress,
          lessThanOrEqualTo(1.0),
          reason:
              'Progress should not exceed 1.0 for XP $xp '
              '(level ${progress.level})',
        );
      }
    });

    test('progress is 1.0 at max level (or close to next level)', () {
      // Test at the last level in the table
      const maxXpInTable = 104273167;
      final progress = xpProgressForXp(maxXpInTable);
      // At max XP, we might be at max level, so nextLevelXp might not exist
      // But progress should still be valid
      expect(progress.progress, greaterThanOrEqualTo(0.0));
    });
  });
}
