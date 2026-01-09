import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item bronzeSword;
  late Item runeSword;

  setUpAll(() async {
    await loadTestRegistries();
    bronzeSword = testItems.byName('Bronze Sword');
    runeSword = testItems.byName('Rune Sword');
  });

  group('Item.equipRequirements', () {
    test('bronze sword requires level 1 Attack', () {
      expect(bronzeSword.equipRequirements, isNotEmpty);
      expect(bronzeSword.equipRequirements.length, 1);

      final req = bronzeSword.equipRequirements.first;
      expect(req, isA<SkillLevelRequirement>());

      final skillReq = req as SkillLevelRequirement;
      expect(skillReq.skill, Skill.attack);
      expect(skillReq.level, 1);
    });

    test('rune sword requires level 40 Attack', () {
      expect(runeSword.equipRequirements, isNotEmpty);

      final req = runeSword.equipRequirements.first;
      expect(req, isA<SkillLevelRequirement>());

      final skillReq = req as SkillLevelRequirement;
      expect(skillReq.skill, Skill.attack);
      expect(skillReq.level, 40);
    });
  });

  group('GlobalState.canEquipGear', () {
    test('returns true when requirements are met', () {
      final state = GlobalState.test(
        testRegistries,
        // Attack level 1 (default) meets bronze sword requirement
        skillStates: const {
          Skill.attack: SkillState(xp: 100, masteryPoolXp: 0),
        },
      );

      expect(state.canEquipGear(bronzeSword), isTrue);
    });

    test('returns true when skill level exceeds requirement', () {
      final state = GlobalState.test(
        testRegistries,
        // Attack level 50 exceeds rune sword's level 40 requirement
        skillStates: const {
          Skill.attack: SkillState(xp: 101333, masteryPoolXp: 0),
        },
      );

      expect(state.canEquipGear(runeSword), isTrue);
    });

    test('returns false when skill level is too low', () {
      final state = GlobalState.test(
        testRegistries,
        // Attack level 1 is below rune sword's level 40 requirement
        skillStates: const {
          Skill.attack: SkillState(xp: 100, masteryPoolXp: 0),
        },
      );

      expect(state.canEquipGear(runeSword), isFalse);
    });

    test('returns true for items with no requirements', () {
      // Create an item with no equip requirements
      final noReqItem = Item.test('No Req Weapon', gp: 100);

      final state = GlobalState.test(testRegistries);

      expect(state.canEquipGear(noReqItem), isTrue);
    });
  });

  group('GlobalState.unmetEquipRequirements', () {
    test('returns empty list when all requirements are met', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 101333, masteryPoolXp: 0),
        },
      );

      expect(state.unmetEquipRequirements(runeSword), isEmpty);
    });

    test('returns unmet requirements when skill is too low', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 100, masteryPoolXp: 0),
        },
      );

      final unmet = state.unmetEquipRequirements(runeSword);
      expect(unmet, hasLength(1));
      expect(unmet.first, isA<SkillLevelRequirement>());

      final req = unmet.first as SkillLevelRequirement;
      expect(req.skill, Skill.attack);
      expect(req.level, 40);
    });
  });

  group('GlobalState.equipGear with requirements', () {
    test('throws when requirements not met', () {
      // Create a state with a low attack level and rune sword in inventory
      var state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 100, masteryPoolXp: 0),
        },
      );

      // Add rune sword to inventory
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(runeSword, count: 1)),
      );

      expect(
        () => state.equipGear(runeSword, EquipmentSlot.weapon),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('requirements not met'),
          ),
        ),
      );
    });

    test('succeeds when requirements are met', () {
      // Create a state with sufficient attack level and rune sword in inventory
      var state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 101333, masteryPoolXp: 0),
        },
      );

      // Add rune sword to inventory
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(runeSword, count: 1)),
      );

      final newState = state.equipGear(runeSword, EquipmentSlot.weapon);

      expect(newState.equipment.gearInSlot(EquipmentSlot.weapon), runeSword);
      expect(newState.inventory.countOfItem(runeSword), 0);
    });
  });

  group('Multiple requirements', () {
    test('items with multiple requirements check all of them', () async {
      // Find an item with multiple requirements (Slayer Helmet needs Defence
      // and Slayer at level 30)
      final slayerHelmet = testItems.byName('Slayer Helmet (Strong)');

      expect(slayerHelmet.equipRequirements.length, greaterThanOrEqualTo(2));

      // XP for level 30 is 13363 (from xp.dart table, index 29)
      const level30Xp = 13363;

      // State with only Defence at level 30, Slayer at level 1
      final partialState = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.defence: SkillState(xp: level30Xp, masteryPoolXp: 0),
          // Slayer level 1 (default or unset)
        },
      );

      expect(partialState.canEquipGear(slayerHelmet), isFalse);

      final unmet = partialState.unmetEquipRequirements(slayerHelmet);
      expect(unmet.length, greaterThanOrEqualTo(1));

      // State with both Defence and Slayer at level 30
      final fullState = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.defence: SkillState(xp: level30Xp, masteryPoolXp: 0),
          Skill.slayer: SkillState(xp: level30Xp, masteryPoolXp: 0),
        },
      );

      expect(fullState.canEquipGear(slayerHelmet), isTrue);
      expect(fullState.unmetEquipRequirements(slayerHelmet), isEmpty);
    });
  });
}
