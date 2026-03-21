import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('CombatType', () {
    group('values', () {
      test('has exactly 3 values', () {
        expect(CombatType.values.length, equals(3));
      });

      test('contains melee, ranged, and magic', () {
        expect(CombatType.values, contains(CombatType.melee));
        expect(CombatType.values, contains(CombatType.ranged));
        expect(CombatType.values, contains(CombatType.magic));
      });
    });

    group('fromJson', () {
      test('parses melee correctly', () {
        expect(CombatType.fromJson('melee'), equals(CombatType.melee));
      });

      test('parses ranged correctly', () {
        expect(CombatType.fromJson('ranged'), equals(CombatType.ranged));
      });

      test('parses magic correctly', () {
        expect(CombatType.fromJson('magic'), equals(CombatType.magic));
      });

      test('throws for invalid value', () {
        expect(() => CombatType.fromJson('invalid'), throwsStateError);
      });

      test('throws for empty string', () {
        expect(() => CombatType.fromJson(''), throwsStateError);
      });
    });

    group('toJson', () {
      test('serializes melee correctly', () {
        expect(CombatType.melee.toJson(), equals('melee'));
      });

      test('serializes ranged correctly', () {
        expect(CombatType.ranged.toJson(), equals('ranged'));
      });

      test('serializes magic correctly', () {
        expect(CombatType.magic.toJson(), equals('magic'));
      });
    });

    group('JSON round-trip', () {
      test('all values survive serialization round-trip', () {
        for (final type in CombatType.values) {
          final json = type.toJson();
          final restored = CombatType.fromJson(json);
          expect(restored, equals(type));
        }
      });
    });

    group('attackStyles', () {
      test('melee returns stab, slash, and block styles', () {
        final styles = CombatType.melee.attackStyles;
        expect(styles.length, equals(3));
        expect(styles, contains(AttackStyle.stab));
        expect(styles, contains(AttackStyle.slash));
        expect(styles, contains(AttackStyle.block));
      });

      test('ranged returns accurate, rapid, and longRange styles', () {
        final styles = CombatType.ranged.attackStyles;
        expect(styles.length, equals(3));
        expect(styles, contains(AttackStyle.accurate));
        expect(styles, contains(AttackStyle.rapid));
        expect(styles, contains(AttackStyle.longRange));
      });

      test('magic returns standard and defensive styles', () {
        final styles = CombatType.magic.attackStyles;
        expect(styles.length, equals(2));
        expect(styles, contains(AttackStyle.standard));
        expect(styles, contains(AttackStyle.defensive));
      });

      test('melee styles do not contain ranged styles', () {
        final styles = CombatType.melee.attackStyles;
        expect(styles, isNot(contains(AttackStyle.accurate)));
        expect(styles, isNot(contains(AttackStyle.rapid)));
        expect(styles, isNot(contains(AttackStyle.longRange)));
      });

      test('melee styles do not contain magic styles', () {
        final styles = CombatType.melee.attackStyles;
        expect(styles, isNot(contains(AttackStyle.standard)));
        expect(styles, isNot(contains(AttackStyle.defensive)));
      });

      test('ranged styles do not contain melee styles', () {
        final styles = CombatType.ranged.attackStyles;
        expect(styles, isNot(contains(AttackStyle.stab)));
        expect(styles, isNot(contains(AttackStyle.slash)));
        expect(styles, isNot(contains(AttackStyle.block)));
      });

      test('ranged styles do not contain magic styles', () {
        final styles = CombatType.ranged.attackStyles;
        expect(styles, isNot(contains(AttackStyle.standard)));
        expect(styles, isNot(contains(AttackStyle.defensive)));
      });

      test('magic styles do not contain melee styles', () {
        final styles = CombatType.magic.attackStyles;
        expect(styles, isNot(contains(AttackStyle.stab)));
        expect(styles, isNot(contains(AttackStyle.slash)));
        expect(styles, isNot(contains(AttackStyle.block)));
      });

      test('magic styles do not contain ranged styles', () {
        final styles = CombatType.magic.attackStyles;
        expect(styles, isNot(contains(AttackStyle.accurate)));
        expect(styles, isNot(contains(AttackStyle.rapid)));
        expect(styles, isNot(contains(AttackStyle.longRange)));
      });

      test('primarySkill returns expected skill for each style', () {
        expect(AttackStyle.stab.primarySkill, Skill.attack);
        expect(AttackStyle.slash.primarySkill, Skill.strength);
        expect(AttackStyle.block.primarySkill, Skill.defence);
        expect(AttackStyle.accurate.primarySkill, Skill.ranged);
        expect(AttackStyle.rapid.primarySkill, Skill.ranged);
        expect(AttackStyle.longRange.primarySkill, Skill.ranged);
        expect(AttackStyle.standard.primarySkill, Skill.magic);
        expect(AttackStyle.defensive.primarySkill, Skill.magic);
      });
    });

    group('AttackStyle.primarySkill coverage', () {
      test('all attack styles are covered by exactly one combat type', () {
        final allStyles = <AttackStyle>{};
        for (final type in CombatType.values) {
          for (final style in type.attackStyles) {
            expect(
              allStyles.contains(style),
              isFalse,
              reason: '$style appears in multiple combat types',
            );
            allStyles.add(style);
          }
        }
        expect(allStyles, equals(AttackStyle.values.toSet()));
      });
    });
  });

  group('CombatRegistry.test', () {
    test('creates registry with empty sub-registries', () {
      final monster = CombatAction(
        id: ActionId.test(Skill.combat, 'Test Monster'),
        name: 'Test Monster',
        levels: const MonsterLevels(
          hitpoints: 10,
          attack: 1,
          strength: 1,
          defense: 1,
          ranged: 1,
          magic: 1,
        ),
        attackType: AttackType.melee,
        attackSpeed: 2.4,
        lootChance: 0,
        minGpDrop: 0,
        maxGpDrop: 0,
      );
      final registry = CombatRegistry.test([monster]);
      expect(registry.monsters, hasLength(1));
      expect(registry.areas.all, isEmpty);
      expect(registry.dungeons.all, isEmpty);
      expect(registry.strongholds.all, isEmpty);
    });
  });
}
