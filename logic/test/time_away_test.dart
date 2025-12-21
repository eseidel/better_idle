import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late SkillAction normalTree;

  setUpAll(() async {
    await loadTestRegistries();
    normalTree = testActions.byName('Normal Tree') as SkillAction;
  });

  test('TimeAway duration does not update on mergeChanges', () {
    final startTime = DateTime(2024, 1, 1, 12);
    final endTime = startTime.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(
      testRegistries,
      startTime: startTime,
      endTime: endTime,
    );
    final t2 = t1.mergeChanges(const Changes.empty());

    expect(t2.duration, const Duration(seconds: 10));
  });

  test('TimeAway merge updates endTime to the latest endTime', () {
    final startTime1 = DateTime(2024, 1, 1, 12);
    final endTime1 = startTime1.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(
      testRegistries,
      startTime: startTime1,
      endTime: endTime1,
    );

    final startTime2 = DateTime(2024, 1, 1, 12, 0, 5);
    final endTime2 = startTime2.add(const Duration(seconds: 15));
    final t2 = TimeAway.test(
      testRegistries,
      startTime: startTime2,
      endTime: endTime2,
    );

    final merged = t1.maybeMergeInto(t2);

    // Merged should have the earliest startTime and latest endTime
    expect(merged.startTime, startTime1);
    expect(merged.endTime, endTime2);
    expect(merged.duration, const Duration(seconds: 20));
  });

  test('TimeAway merge updates startTime to the earliest startTime', () {
    final startTime1 = DateTime(2024, 1, 1, 12, 0, 5);
    final endTime1 = startTime1.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(
      testRegistries,
      startTime: startTime1,
      endTime: endTime1,
    );

    final startTime2 = DateTime(2024, 1, 1, 12);
    final endTime2 = startTime2.add(const Duration(seconds: 8));
    final t2 = TimeAway.test(
      testRegistries,
      startTime: startTime2,
      endTime: endTime2,
    );

    final merged = t1.maybeMergeInto(t2);

    // Merged should have the earliest startTime and latest endTime
    expect(merged.startTime, startTime2);
    expect(merged.endTime, endTime1);
    expect(merged.duration, const Duration(seconds: 15));
  });

  group('itemsGainedPerHour', () {
    test('returns empty map when no active action', () {
      final timeAway = TimeAway.test(testRegistries);
      expect(timeAway.itemsGainedPerHour, isEmpty);
    });

    test('returns empty map for combat action', () {
      final plantAction = combatActionByName('Plant');
      final timeAway = TimeAway.test(testRegistries, activeAction: plantAction);
      expect(timeAway.itemsGainedPerHour, isEmpty);
    });

    test('returns correct items per hour for skill action', () {
      // Normal Tree takes 3 seconds per action and outputs 1 Normal Logs
      // Actions per hour = 3600 / 3 = 1200
      // Items per hour = 1 * 1200 = 1200
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: normalTree,
        masteryLevels: {'Normal Tree': 0},
      );

      final itemsPerHour = timeAway.itemsGainedPerHour;
      expect(itemsPerHour['Normal Logs'], closeTo(1200, 1));
    });

    test('includes skill-level drops in calculation', () {
      // Woodcutting has a Bird Nest drop at 0.5% rate
      // Normal Tree: 1200 actions per hour
      // Bird Nest expected per hour = 1200 * 0.005 = 6
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: normalTree,
        masteryLevels: {'Normal Tree': 0},
      );

      final itemsPerHour = timeAway.itemsGainedPerHour;
      expect(itemsPerHour['Bird Nest'], closeTo(6, 0.1));
    });

    test('accounts for mastery level doubling chance', () {
      // Woodcutting gets 5% doubling chance every 10 mastery levels.
      // At mastery level 80, doubling chance = 40%
      // Expected logs = 1 * (1 + 0.40) = 1.40 per action
      // Items per hour = 1.40 * 1200 = 1680
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: normalTree,
        masteryLevels: {'Normal Tree': 80},
      );

      final itemsPerHour = timeAway.itemsGainedPerHour;
      expect(itemsPerHour['Normal Logs'], 1680);
    });
  });
}
