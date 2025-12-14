import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  test('TimeAway duration does not update on mergeChanges', () {
    final startTime = DateTime(2024, 1, 1, 12);
    final endTime = startTime.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(startTime: startTime, endTime: endTime);
    final t2 = t1.mergeChanges(const Changes.empty());

    expect(t2.duration, const Duration(seconds: 10));
  });

  test('TimeAway merge updates endTime to the latest endTime', () {
    final startTime1 = DateTime(2024, 1, 1, 12);
    final endTime1 = startTime1.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(startTime: startTime1, endTime: endTime1);

    final startTime2 = DateTime(2024, 1, 1, 12, 0, 5);
    final endTime2 = startTime2.add(const Duration(seconds: 15));
    final t2 = TimeAway.test(startTime: startTime2, endTime: endTime2);

    final merged = t1.maybeMergeInto(t2);

    // Merged should have the earliest startTime and latest endTime
    expect(merged.startTime, startTime1);
    expect(merged.endTime, endTime2);
    expect(merged.duration, const Duration(seconds: 20));
  });

  test('TimeAway merge updates startTime to the earliest startTime', () {
    final startTime1 = DateTime(2024, 1, 1, 12, 0, 5);
    final endTime1 = startTime1.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(startTime: startTime1, endTime: endTime1);

    final startTime2 = DateTime(2024, 1, 1, 12);
    final endTime2 = startTime2.add(const Duration(seconds: 8));
    final t2 = TimeAway.test(startTime: startTime2, endTime: endTime2);

    final merged = t1.maybeMergeInto(t2);

    // Merged should have the earliest startTime and latest endTime
    expect(merged.startTime, startTime2);
    expect(merged.endTime, endTime1);
    expect(merged.duration, const Duration(seconds: 15));
  });
}
