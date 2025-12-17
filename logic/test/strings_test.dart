import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('approximateDuration', () {
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
      expect(percentToString(0.0), '0%');
      expect(percentToString(0.05), '5%');
      expect(percentToString(0.50), '50%');
      expect(percentToString(1.0), '100%');
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
      expect(signedPercentToString(0.0), '0%');
    });
  });
}
