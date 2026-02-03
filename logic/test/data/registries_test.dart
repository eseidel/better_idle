import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('compareByIndex', () {
    test('returns 0 when both items not in map', () {
      final sortIndex = <String, int>{'a': 0, 'b': 1};
      expect(compareByIndex(sortIndex, 'c', 'd'), 0);
    });

    test('returns 1 when first item not in map', () {
      final sortIndex = <String, int>{'a': 0, 'b': 1};
      expect(compareByIndex(sortIndex, 'c', 'a'), 1);
    });

    test('returns -1 when second item not in map', () {
      final sortIndex = <String, int>{'a': 0, 'b': 1};
      expect(compareByIndex(sortIndex, 'a', 'c'), -1);
    });

    test('compares by index when both in map', () {
      final sortIndex = <String, int>{'a': 0, 'b': 1, 'c': 2};
      expect(compareByIndex(sortIndex, 'a', 'b'), lessThan(0));
      expect(compareByIndex(sortIndex, 'b', 'a'), greaterThan(0));
      expect(compareByIndex(sortIndex, 'a', 'a'), 0);
    });
  });

  group('Registries', () {
    test('allActions returns all skill actions', () {
      final actions = testRegistries.allActions;
      expect(actions, isNotEmpty);
    });

    test('actionsForSkill returns actions for woodcutting', () {
      final actions = testRegistries.actionsForSkill(Skill.woodcutting);
      expect(actions, isNotEmpty);
      expect(actions.every((a) => a.skill == Skill.woodcutting), isTrue);
    });

    test('actionsForSkill returns actions for firemaking', () {
      final actions = testRegistries.actionsForSkill(Skill.firemaking);
      expect(actions, isNotEmpty);
      expect(actions.every((a) => a.skill == Skill.firemaking), isTrue);
    });

    test('actionsForSkill returns actions for fishing', () {
      final actions = testRegistries.actionsForSkill(Skill.fishing);
      expect(actions, isNotEmpty);
      expect(actions.every((a) => a.skill == Skill.fishing), isTrue);
    });
  });
}
