import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('MasteryLevelUnlock', () {
    test('fromJson parses correctly', () {
      final json = {'level': 5, 'description': 'Unlock bonus'};
      final unlock = MasteryLevelUnlock.fromJson(json);
      expect(unlock.level, 5);
      expect(unlock.description, 'Unlock bonus');
    });
  });

  group('SkillMasteryUnlocks', () {
    test('has correct properties', () {
      const unlocks = SkillMasteryUnlocks(
        skillId: MelvorId('melvorD:Woodcutting'),
        unlocks: [
          MasteryLevelUnlock(level: 1, description: 'First unlock'),
          MasteryLevelUnlock(level: 99, description: 'Max unlock'),
        ],
      );
      expect(unlocks.skillId, const MelvorId('melvorD:Woodcutting'));
      expect(unlocks.unlocks, hasLength(2));
    });
  });

  group('MasteryUnlockRegistry', () {
    test('forSkill returns unlocks for known skill', () {
      final registry = MasteryUnlockRegistry(const [
        SkillMasteryUnlocks(
          skillId: MelvorId('melvorD:Woodcutting'),
          unlocks: [MasteryLevelUnlock(level: 1, description: 'Test')],
        ),
      ]);
      final unlocks = registry.forSkill(const MelvorId('melvorD:Woodcutting'));
      expect(unlocks, isNotNull);
      expect(unlocks!.skillId, const MelvorId('melvorD:Woodcutting'));
    });

    test('forSkill returns null for unknown skill', () {
      final registry = MasteryUnlockRegistry(const []);
      expect(registry.forSkill(const MelvorId('melvorD:Woodcutting')), isNull);
    });

    test('skillIds returns all registered skills', () {
      final registry = MasteryUnlockRegistry(const [
        SkillMasteryUnlocks(
          skillId: MelvorId('melvorD:Woodcutting'),
          unlocks: [],
        ),
        SkillMasteryUnlocks(skillId: MelvorId('melvorD:Fishing'), unlocks: []),
      ]);
      expect(registry.skillIds, hasLength(2));
      expect(
        registry.skillIds,
        containsAll([
          const MelvorId('melvorD:Woodcutting'),
          const MelvorId('melvorD:Fishing'),
        ]),
      );
    });
  });

  group('parseMasteryLevelUnlocks', () {
    test('returns empty list for null', () {
      expect(parseMasteryLevelUnlocks({}), isEmpty);
    });

    test('returns empty list for missing key', () {
      expect(parseMasteryLevelUnlocks({'other': 'data'}), isEmpty);
    });

    test('parses and sorts unlocks by level', () {
      final skillData = {
        'masteryLevelUnlocks': [
          {'level': 99, 'description': 'Max'},
          {'level': 1, 'description': 'First'},
          {'level': 50, 'description': 'Mid'},
        ],
      };
      final unlocks = parseMasteryLevelUnlocks(skillData);
      expect(unlocks, hasLength(3));
      expect(unlocks[0].level, 1);
      expect(unlocks[1].level, 50);
      expect(unlocks[2].level, 99);
    });
  });
}
