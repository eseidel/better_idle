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
}
