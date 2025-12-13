import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('logic package', () {
    test('exports Skill enum', () {
      expect(Skill.values, isNotEmpty);
    });

    test('exports Item class', () {
      final item = itemRegistry.byName('Normal Logs');
      expect(item.name, 'Normal Logs');
    });

    test('exports Tick typedef', () {
      final ticks = ticksFromDuration(const Duration(seconds: 1));
      expect(ticks, 10);
    });
  });
}
