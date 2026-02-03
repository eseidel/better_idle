import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('tick utilities', () {
    test('msPerTick is 100ms', () {
      expect(msPerTick, 100);
    });

    test('tickDuration is 100ms', () {
      expect(tickDuration, const Duration(milliseconds: 100));
    });

    test('secondsToTicks converts correctly', () {
      expect(secondsToTicks(1), 10);
      expect(secondsToTicks(3), 30);
      expect(secondsToTicks(0.5), 5);
    });

    test('msToTicks converts correctly', () {
      expect(msToTicks(100), 1);
      expect(msToTicks(1000), 10);
      expect(msToTicks(150), 2); // Rounds to nearest
      expect(msToTicks(50), 1); // Rounds to nearest
    });

    test('ticksFromDuration converts correctly', () {
      expect(ticksFromDuration(const Duration(seconds: 1)), 10);
      expect(ticksFromDuration(const Duration(milliseconds: 300)), 3);
    });

    test('durationFromTicks converts correctly', () {
      expect(durationFromTicks(10), const Duration(seconds: 1));
      expect(durationFromTicks(30), const Duration(seconds: 3));
      expect(durationFromTicks(1), const Duration(milliseconds: 100));
    });

    test('ticksPer1Hp is 100 ticks (10 seconds)', () {
      expect(ticksPer1Hp, 100);
    });
  });
}
