import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('logic package', () {
    test('exports Skill enum', () {
      expect(Skill.values, isNotEmpty);
    });

    test('exports Item class', () {
      final item = testItems.byName('Normal Logs');
      expect(item.name, 'Normal Logs');
    });

    test('exports Tick typedef', () {
      final ticks = ticksFromDuration(const Duration(seconds: 1));
      expect(ticks, 10);
    });
  });
}
