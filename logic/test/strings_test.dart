import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('approximateDurationFromTicks', () {
    test('converts ticks to duration string', () {
      // 1 tick = 100ms, so 10 ticks = 1 second
      expect(approximateDurationFromTicks(10), '1 second');
      expect(approximateDurationFromTicks(600), '1 minute'); // 60 seconds
      expect(approximateDurationFromTicks(36000), '1 hour'); // 3600 seconds
      expect(approximateDurationFromTicks(864000), '1 day'); // 86400 seconds
    });
  });

  group('durationStringWithTicks', () {
    test('formats duration with ticks in parentheses', () {
      expect(durationStringWithTicks(600), '1 minute (600 ticks)');
      expect(durationStringWithTicks(36000), '1 hour (36,000 ticks)');
      expect(durationStringWithTicks(864000), '1 day (864,000 ticks)');
    });
  });

  group('signedDurationStringWithTicks', () {
    test('formats positive delta with plus sign', () {
      expect(signedDurationStringWithTicks(6000), '+10 minutes (+6,000 ticks)');
    });

    test('formats negative delta with minus sign', () {
      expect(
        signedDurationStringWithTicks(-6000),
        '-10 minutes (-6,000 ticks)',
      );
    });

    test('formats zero as positive', () {
      expect(signedDurationStringWithTicks(0), '+0 seconds (+0 ticks)');
    });
  });

  group('approximateDuration', () {
    test('formats days with rounding', () {
      expect(approximateDuration(const Duration(days: 1)), '1 day');
      expect(approximateDuration(const Duration(days: 2)), '2 days');
      expect(approximateDuration(const Duration(days: 1, hours: 12)), '2 days');
      expect(approximateDuration(const Duration(days: 1, hours: 11)), '1 day');
    });

    test('formats hours with rounding', () {
      expect(approximateDuration(const Duration(hours: 1)), '1 hour');
      expect(approximateDuration(const Duration(hours: 2)), '2 hours');
      expect(
        approximateDuration(const Duration(hours: 1, minutes: 30)),
        '2 hours',
      );
      expect(
        approximateDuration(const Duration(hours: 1, minutes: 29)),
        '1 hour',
      );
    });

    test('formats minutes with rounding', () {
      expect(approximateDuration(const Duration(minutes: 1)), '1 minute');
      expect(approximateDuration(const Duration(minutes: 5)), '5 minutes');
      expect(
        approximateDuration(const Duration(minutes: 1, seconds: 30)),
        '2 minutes',
      );
    });

    test('formats seconds with rounding', () {
      expect(approximateDuration(const Duration(seconds: 1)), '1 second');
      expect(approximateDuration(const Duration(seconds: 45)), '45 seconds');
      expect(
        approximateDuration(const Duration(seconds: 1, milliseconds: 500)),
        '2 seconds',
      );
    });
  });

  group('approximateCreditString', () {
    test('formats small values with commas', () {
      expect(approximateCreditString(0), '0');
      expect(approximateCreditString(999), '999');
      expect(approximateCreditString(1000), '1,000');
      expect(approximateCreditString(9999), '9,999');
    });

    test('formats thousands with K suffix', () {
      expect(approximateCreditString(10000), '10K');
      expect(approximateCreditString(50000), '50K');
      expect(approximateCreditString(999999), '999K');
    });

    test('formats millions with M suffix', () {
      expect(approximateCreditString(1000000), '1M');
      expect(approximateCreditString(5000000), '5M');
      expect(approximateCreditString(10000000), '10M');
    });
  });

  group('approximateCountString', () {
    test('formats values same as approximateCreditString', () {
      expect(approximateCountString(500), '500');
      expect(approximateCountString(15000), '15K');
      expect(approximateCountString(2000000), '2M');
    });
  });

  group('preciseNumberString', () {
    test('formats with commas and no abbreviation', () {
      expect(preciseNumberString(0), '0');
      expect(preciseNumberString(1000), '1,000');
      expect(preciseNumberString(1000000), '1,000,000');
      expect(preciseNumberString(123456789), '123,456,789');
    });
  });

  group('signedCountString', () {
    test('returns 0 for zero', () {
      expect(signedCountString(0), '0');
    });

    test('adds plus sign for positive values', () {
      expect(signedCountString(100), '+100');
      expect(signedCountString(15000), '+15K');
    });

    test('keeps minus sign for negative values', () {
      expect(signedCountString(-100), '-100');
      expect(signedCountString(-5000), '-5,000');
    });
  });

  group('percentToString', () {
    test('formats decimal as percentage', () {
      expect(percentToString(0), '0%');
      expect(percentToString(0.05), '5%');
      expect(percentToString(0.50), '50%');
      expect(percentToString(1), '100%');
    });

    test('handles negative values', () {
      expect(percentToString(-0.05), '-5%');
      expect(percentToString(-0.10), '-10%');
    });
  });

  group('signedPercentToString', () {
    test('adds plus sign for positive values', () {
      expect(signedPercentToString(0.05), '+5%');
      expect(signedPercentToString(0.10), '+10%');
    });

    test('keeps minus sign for negative values', () {
      expect(signedPercentToString(-0.05), '-5%');
      expect(signedPercentToString(-0.10), '-10%');
    });

    test('returns 0% for zero', () {
      expect(signedPercentToString(0), '0%');
    });
  });

  group('compactDuration', () {
    test('formats days with optional hours', () {
      expect(compactDuration(const Duration(days: 1)), '1d');
      expect(compactDuration(const Duration(days: 3)), '3d');
      expect(compactDuration(const Duration(days: 1, hours: 12)), '1d 12h');
      expect(compactDuration(const Duration(days: 2)), '2d');
    });

    test('formats hours with optional minutes', () {
      expect(compactDuration(const Duration(hours: 1)), '1h');
      expect(compactDuration(const Duration(hours: 5)), '5h');
      expect(compactDuration(const Duration(hours: 2, minutes: 30)), '2h 30m');
      expect(compactDuration(const Duration(hours: 12)), '12h');
    });

    test('formats minutes with optional seconds', () {
      expect(compactDuration(const Duration(minutes: 1)), '1m');
      expect(compactDuration(const Duration(minutes: 45)), '45m');
      expect(
        compactDuration(const Duration(minutes: 5, seconds: 30)),
        '5m 30s',
      );
      expect(compactDuration(const Duration(minutes: 10)), '10m');
    });

    test('formats seconds only', () {
      expect(compactDuration(const Duration(seconds: 1)), '1s');
      expect(compactDuration(const Duration(seconds: 45)), '45s');
      expect(compactDuration(Duration.zero), '0s');
    });

    test('shows only two most significant units', () {
      // Days + hours, ignores minutes/seconds
      expect(
        compactDuration(const Duration(days: 1, hours: 2, minutes: 30)),
        '1d 2h',
      );
      // Hours + minutes, ignores seconds
      expect(
        compactDuration(const Duration(hours: 3, minutes: 15, seconds: 45)),
        '3h 15m',
      );
    });
  });

  group('compactDurationFromTicks', () {
    test('converts ticks to compact duration string', () {
      // 1 tick = 100ms, so 10 ticks = 1 second
      expect(compactDurationFromTicks(10), '1s');
      expect(compactDurationFromTicks(600), '1m'); // 60 seconds
      expect(compactDurationFromTicks(36000), '1h'); // 3600 seconds
      expect(compactDurationFromTicks(864000), '1d'); // 86400 seconds
      expect(compactDurationFromTicks(1296000), '1d 12h'); // 1 day + 12 hours
    });
  });

  group('percentValueToString', () {
    test('formats integer values as percentage', () {
      expect(percentValueToString(0), '0%');
      expect(percentValueToString(50), '50%');
      expect(percentValueToString(100), '100%');
    });

    test('rounds decimal values', () {
      expect(percentValueToString(50.4), '50%');
      expect(percentValueToString(50.5), '51%');
      expect(percentValueToString(99.9), '100%');
    });

    test('handles negative values', () {
      expect(percentValueToString(-10), '-10%');
      expect(percentValueToString(-5.5), '-6%');
    });
  });

  group('timeAgo', () {
    test('returns "Just now" for less than 60 seconds', () {
      final now = DateTime(2024, 1, 15, 12);
      expect(timeAgo(now, now: now), 'Just now');
      expect(
        timeAgo(now.subtract(const Duration(seconds: 1)), now: now),
        'Just now',
      );
      expect(
        timeAgo(now.subtract(const Duration(seconds: 59)), now: now),
        'Just now',
      );
    });

    test('returns minutes ago', () {
      final now = DateTime(2024, 1, 15, 12);
      expect(
        timeAgo(now.subtract(const Duration(minutes: 1)), now: now),
        '1 minute ago',
      );
      expect(
        timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
        '5 minutes ago',
      );
      expect(
        timeAgo(now.subtract(const Duration(minutes: 59)), now: now),
        '59 minutes ago',
      );
    });

    test('returns hours ago', () {
      final now = DateTime(2024, 1, 15, 12);
      expect(
        timeAgo(now.subtract(const Duration(hours: 1)), now: now),
        '1 hour ago',
      );
      expect(
        timeAgo(now.subtract(const Duration(hours: 5)), now: now),
        '5 hours ago',
      );
      expect(
        timeAgo(now.subtract(const Duration(hours: 23)), now: now),
        '23 hours ago',
      );
    });

    test('returns days ago', () {
      final now = DateTime(2024, 1, 15, 12);
      expect(
        timeAgo(now.subtract(const Duration(days: 1)), now: now),
        '1 day ago',
      );
      expect(
        timeAgo(now.subtract(const Duration(days: 5)), now: now),
        '5 days ago',
      );
      expect(
        timeAgo(now.subtract(const Duration(days: 30)), now: now),
        '30 days ago',
      );
    });

    test('rounds to nearest unit', () {
      final now = DateTime(2024, 1, 15, 12);
      // 1 hour 30 minutes should round to 2 hours
      expect(
        timeAgo(now.subtract(const Duration(hours: 1, minutes: 30)), now: now),
        '2 hours ago',
      );
      // 1 day 12 hours should round to 2 days
      expect(
        timeAgo(now.subtract(const Duration(days: 1, hours: 12)), now: now),
        '2 days ago',
      );
    });
  });
}
