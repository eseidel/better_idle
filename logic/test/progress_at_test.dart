import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('ProgressAt', () {
    group('constructor', () {
      test('creates instance with required parameters', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 5,
          totalTicks: 10,
        );

        expect(progressAt.lastUpdateTime, time);
        expect(progressAt.progressTicks, 5);
        expect(progressAt.totalTicks, 10);
        expect(progressAt.isAdvancing, true);
      });

      test('isAdvancing defaults to true', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 0,
          totalTicks: 10,
        );

        expect(progressAt.isAdvancing, true);
      });

      test('isAdvancing can be set to false', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 0,
          totalTicks: 10,
          isAdvancing: false,
        );

        expect(progressAt.isAdvancing, false);
      });
    });

    group('ProgressAt.zero', () {
      test('creates zero progress with provided time', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt.zero(time);

        expect(progressAt.lastUpdateTime, time);
        expect(progressAt.progressTicks, 0);
        expect(progressAt.totalTicks, 1);
        expect(progressAt.isAdvancing, false);
      });

      test('creates zero progress with current time when null', () {
        final before = DateTime.timestamp();
        final progressAt = ProgressAt.zero(null);
        final after = DateTime.timestamp();

        expect(
          progressAt.lastUpdateTime.isAfter(before) ||
              progressAt.lastUpdateTime.isAtSameMomentAs(before),
          true,
        );
        expect(
          progressAt.lastUpdateTime.isBefore(after) ||
              progressAt.lastUpdateTime.isAtSameMomentAs(after),
          true,
        );
        expect(progressAt.progressTicks, 0);
        expect(progressAt.totalTicks, 1);
        expect(progressAt.isAdvancing, false);
      });
    });

    group('progress getter', () {
      test('returns 0 when progressTicks is 0', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 0,
          totalTicks: 10,
        );

        expect(progressAt.progress, 0.0);
      });

      test('returns 1 when progressTicks equals totalTicks', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 10,
          totalTicks: 10,
        );

        expect(progressAt.progress, 1.0);
      });

      test('returns correct fraction for partial progress', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 5,
          totalTicks: 10,
        );

        expect(progressAt.progress, 0.5);
      });

      test('clamps to 0 when totalTicks is 0', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 5,
          totalTicks: 0,
        );

        expect(progressAt.progress, 0.0);
      });

      test('clamps to 0 when totalTicks is negative', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 5,
          totalTicks: -1,
        );

        expect(progressAt.progress, 0.0);
      });

      test('clamps to 1 when progressTicks exceeds totalTicks', () {
        final progressAt = ProgressAt(
          lastUpdateTime: DateTime.timestamp(),
          progressTicks: 15,
          totalTicks: 10,
        );

        expect(progressAt.progress, 1.0);
      });
    });

    group('estimateProgressAt', () {
      test('returns base progress when already complete', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 10,
          totalTicks: 10,
        );

        final later = time.add(const Duration(seconds: 1));
        expect(progressAt.estimateProgressAt(later), 1.0);
      });

      test('returns base progress when not advancing', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 5,
          totalTicks: 10,
          isAdvancing: false,
        );

        final later = time.add(const Duration(seconds: 1));
        expect(progressAt.estimateProgressAt(later), 0.5);
      });

      test('estimates progress based on elapsed time', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 0,
          totalTicks: 10,
        );

        // 500ms later = 5 ticks at 100ms per tick
        final later = time.add(const Duration(milliseconds: 500));
        expect(progressAt.estimateProgressAt(later), 0.5);
      });

      test('estimates progress with custom tick duration', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 0,
          totalTicks: 10,
        );

        // 500ms later = 2.5 ticks at 200ms per tick
        final later = time.add(const Duration(milliseconds: 500));
        expect(
          progressAt.estimateProgressAt(
            later,
            tickDuration: const Duration(milliseconds: 200),
          ),
          0.25,
        );
      });

      test('clamps estimated progress to 1.0', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 5,
          totalTicks: 10,
        );

        // Way in the future
        final later = time.add(const Duration(seconds: 10));
        expect(progressAt.estimateProgressAt(later), 1.0);
      });

      test('handles zero elapsed time', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 3,
          totalTicks: 10,
        );

        expect(progressAt.estimateProgressAt(time), 0.3);
      });

      test('adds to existing progress', () {
        final time = DateTime(2024, 1, 1, 12);
        final progressAt = ProgressAt(
          lastUpdateTime: time,
          progressTicks: 5,
          totalTicks: 10,
        );

        // 200ms later = 2 ticks, so 5 + 2 = 7 out of 10
        final later = time.add(const Duration(milliseconds: 200));
        expect(progressAt.estimateProgressAt(later), 0.7);
      });
    });
  });

  group('ActiveActivityProgressAt extension', () {
    test('toProgressAt converts SkillActivity correctly', () {
      const activity = SkillActivity(
        skill: Skill.woodcutting,
        actionId: MelvorId('test_action'),
        progressTicks: 4,
        totalTicks: 10,
      );
      final time = DateTime(2024, 1, 1, 12);

      final progressAt = activity.toProgressAt(time);

      expect(progressAt.lastUpdateTime, time);
      expect(progressAt.progressTicks, 4);
      expect(progressAt.totalTicks, 10);
      expect(progressAt.isAdvancing, true);
    });

    test('toProgressAt handles activity at start', () {
      const activity = SkillActivity(
        skill: Skill.woodcutting,
        actionId: MelvorId('test_action'),
        progressTicks: 0,
        totalTicks: 10,
      );
      final time = DateTime.timestamp();

      final progressAt = activity.toProgressAt(time);

      expect(progressAt.progressTicks, 0);
      expect(progressAt.progress, 0.0);
    });

    test('toProgressAt handles activity near completion', () {
      const activity = SkillActivity(
        skill: Skill.woodcutting,
        actionId: MelvorId('test_action'),
        progressTicks: 9,
        totalTicks: 10,
      );
      final time = DateTime.timestamp();

      final progressAt = activity.toProgressAt(time);

      expect(progressAt.progressTicks, 9);
      expect(progressAt.progress, 0.9);
    });
  });
}
