import 'package:logic/src/data/combat.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:test/test.dart';

void main() {
  group('MonsterLevels', () {
    group('combatLevel', () {
      test('calculates combat level for melee-focused monster', () {
        const levels = MonsterLevels(
          hitpoints: 10,
          attack: 8,
          strength: 9,
          defense: 5,
          ranged: 1,
          magic: 1,
        );
        // base = (5 + 10) / 4 = 3.75
        // melee = 8 + 9 = 17
        // ranged = 1 * 1.5 = 1.5
        // magic = 1 * 1.5 = 1.5
        // maxOffense = 17
        // combatLevel = floor(3.75 + 17 * 0.325) = floor(3.75 + 5.525) = 9
        expect(levels.combatLevel, 9);
      });

      test('calculates combat level for ranged-focused monster', () {
        const levels = MonsterLevels(
          hitpoints: 20,
          attack: 1,
          strength: 1,
          defense: 10,
          ranged: 30,
          magic: 1,
        );
        // base = (10 + 20) / 4 = 7.5
        // melee = 1 + 1 = 2
        // ranged = 30 * 1.5 = 45
        // magic = 1 * 1.5 = 1.5
        // maxOffense = 45
        // combatLevel = floor(7.5 + 45 * 0.325) = floor(7.5 + 14.625) = 22
        expect(levels.combatLevel, 22);
      });

      test('calculates combat level for magic-focused monster', () {
        const levels = MonsterLevels(
          hitpoints: 15,
          attack: 1,
          strength: 1,
          defense: 8,
          ranged: 1,
          magic: 25,
        );
        // base = (8 + 15) / 4 = 5.75
        // melee = 1 + 1 = 2
        // ranged = 1 * 1.5 = 1.5
        // magic = 25 * 1.5 = 37.5
        // maxOffense = 37.5
        // combatLevel = floor(5.75 + 37.5 * 0.325) = floor(5.75 + 12.1875) = 17
        expect(levels.combatLevel, 17);
      });

      test('calculates combat level for balanced monster', () {
        const levels = MonsterLevels(
          hitpoints: 50,
          attack: 40,
          strength: 45,
          defense: 30,
          ranged: 40,
          magic: 40,
        );
        // base = (30 + 50) / 4 = 20
        // melee = 40 + 45 = 85
        // ranged = 40 * 1.5 = 60
        // magic = 40 * 1.5 = 60
        // maxOffense = 85 (melee wins)
        // combatLevel = floor(20 + 85 * 0.325) = floor(20 + 27.625) = 47
        expect(levels.combatLevel, 47);
      });
    });
  });

  group('CombatAction', () {
    group('stats', () {
      test('uses strength for melee attack type', () {
        final action = CombatAction(
          id: MelvorId('test:melee_monster'),
          name: 'Melee Monster',
          levels: const MonsterLevels(
            hitpoints: 10,
            attack: 5,
            strength: 20,
            defense: 5,
            ranged: 10,
            magic: 10,
          ),
          attackType: AttackType.melee,
          attackSpeed: 2.4,
          lootChance: 0,
          minGpDrop: 0,
          maxGpDrop: 0,
        );

        final stats = action.stats;
        // effectiveLevel = strength = 20
        // maxHit = round(20 * 1.3) = round(26) = 26
        expect(stats.minHit, 0);
        expect(stats.maxHit, 26);
        expect(stats.damageReduction, 0);
        expect(stats.attackSpeed, 2.4);
      });

      test('uses ranged level for ranged attack type', () {
        final action = CombatAction(
          id: MelvorId('test:ranged_monster'),
          name: 'Ranged Monster',
          levels: const MonsterLevels(
            hitpoints: 10,
            attack: 5,
            strength: 10,
            defense: 5,
            ranged: 30,
            magic: 10,
          ),
          attackType: AttackType.ranged,
          attackSpeed: 3.0,
          lootChance: 0,
          minGpDrop: 0,
          maxGpDrop: 0,
        );

        final stats = action.stats;
        // effectiveLevel = ranged = 30
        // maxHit = round(30 * 1.3) = round(39) = 39
        expect(stats.minHit, 0);
        expect(stats.maxHit, 39);
        expect(stats.attackSpeed, 3.0);
      });

      test('uses magic level for magic attack type', () {
        final action = CombatAction(
          id: MelvorId('test:magic_monster'),
          name: 'Magic Monster',
          levels: const MonsterLevels(
            hitpoints: 10,
            attack: 5,
            strength: 10,
            defense: 5,
            ranged: 10,
            magic: 25,
          ),
          attackType: AttackType.magic,
          attackSpeed: 2.0,
          lootChance: 0,
          minGpDrop: 0,
          maxGpDrop: 0,
        );

        final stats = action.stats;
        // effectiveLevel = magic = 25
        // maxHit = round(25 * 1.3) = round(32.5) = 33
        expect(stats.minHit, 0);
        expect(stats.maxHit, 33);
        expect(stats.attackSpeed, 2.0);
      });

      test('uses highest offensive level for random attack type', () {
        final action = CombatAction(
          id: MelvorId('test:random_monster'),
          name: 'Random Monster',
          levels: const MonsterLevels(
            hitpoints: 10,
            attack: 5,
            strength: 15,
            defense: 5,
            ranged: 20,
            magic: 35,
          ),
          attackType: AttackType.random,
          attackSpeed: 2.4,
          lootChance: 0,
          minGpDrop: 0,
          maxGpDrop: 0,
        );

        final stats = action.stats;
        // effectiveLevel = max(strength=15, ranged=20, magic=35) = 35
        // maxHit = round(35 * 1.3) = round(45.5) = 46
        expect(stats.minHit, 0);
        expect(stats.maxHit, 46);
      });
    });
  });
}
