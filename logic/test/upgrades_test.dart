import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('SkillUpgrade', () {
    test('description returns formatted duration modifier string', () {
      const upgrade = SkillUpgrade(
        name: 'Iron Axe',
        skill: Skill.woodcutting,
        requiredLevel: 1,
        cost: 50,
        durationPercentModifier: 0.95, // -5%
      );
      expect(upgrade.description, '-5% Woodcutting time');
    });

    test('requirementsString returns formatted level requirement', () {
      const upgrade = SkillUpgrade(
        name: 'Steel Axe',
        skill: Skill.woodcutting,
        requiredLevel: 10,
        cost: 750,
        durationPercentModifier: 0.95,
      );
      expect(upgrade.requirementsString, 'Requires Woodcutting level 10');
    });
  });

  group('nextUpgrade', () {
    test('returns first upgrade when level is 0', () {
      final upgrade = nextUpgrade(UpgradeType.axe, 0);
      expect(upgrade, isNotNull);
      expect(upgrade!.name, 'Iron Axe');
    });

    test('returns second upgrade when level is 1', () {
      final upgrade = nextUpgrade(UpgradeType.axe, 1);
      expect(upgrade, isNotNull);
      expect(upgrade!.name, 'Steel Axe');
    });

    test('returns null when all upgrades are owned', () {
      final allAxes = upgradeRegistry[UpgradeType.axe]!;
      final upgrade = nextUpgrade(UpgradeType.axe, allAxes.length);
      expect(upgrade, isNull);
    });
  });

  group('totalDurationPercentModifier', () {
    test('returns 0.0 when no upgrades owned', () {
      final modifier = totalDurationPercentModifier(UpgradeType.axe, 0);
      expect(modifier, 0.0);
    });

    test('returns single upgrade modifier when level is 1', () {
      final modifier = totalDurationPercentModifier(UpgradeType.axe, 1);
      // Iron Axe has durationPercentModifier of 0.95 (stored as 1.0 + -5/100)
      expect(modifier, 0.95);
    });

    test('returns cumulative modifier for multiple upgrades', () {
      final modifier = totalDurationPercentModifier(UpgradeType.axe, 2);
      // Iron (0.95) + Steel (0.95) = 1.90
      expect(modifier, 1.90);
    });
  });
}
