import 'package:better_idle/src/types/time_away.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TimeAway duration does not update on mergeChanges', () {
    final startTime = DateTime(2024, 1, 1, 12);
    final endTime = startTime.add(const Duration(seconds: 10));
    final t1 = TimeAway(
      startTime: startTime,
      endTime: endTime,
      activeSkill: null,
      changes: const Changes.empty(),
    );
    const changes = Changes.empty();
    final t2 = t1.mergeChanges(changes);

    expect(t2.duration, const Duration(seconds: 10));
  });

  test('TimeAway merge updates endTime to the latest endTime', () {
    final startTime1 = DateTime(2024, 1, 1, 12);
    final endTime1 = startTime1.add(const Duration(seconds: 10));
    final t1 = TimeAway(
      startTime: startTime1,
      endTime: endTime1,
      activeSkill: null,
      changes: const Changes.empty(),
    );

    final startTime2 = DateTime(2024, 1, 1, 12, 0, 5);
    final endTime2 = startTime2.add(const Duration(seconds: 15));
    final t2 = TimeAway(
      startTime: startTime2,
      endTime: endTime2,
      activeSkill: null,
      changes: const Changes.empty(),
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
    final t1 = TimeAway(
      startTime: startTime1,
      endTime: endTime1,
      activeSkill: null,
      changes: const Changes.empty(),
    );

    final startTime2 = DateTime(2024, 1, 1, 12);
    final endTime2 = startTime2.add(const Duration(seconds: 8));
    final t2 = TimeAway(
      startTime: startTime2,
      endTime: endTime2,
      activeSkill: null,
      changes: const Changes.empty(),
    );

    final merged = t1.maybeMergeInto(t2);

    // Merged should have the earliest startTime and latest endTime
    expect(merged.startTime, startTime2);
    expect(merged.endTime, endTime1);
    expect(merged.duration, const Duration(seconds: 15));
  });
}
