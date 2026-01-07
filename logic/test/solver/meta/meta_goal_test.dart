import 'package:logic/logic.dart';
import 'package:logic/src/solver/meta/meta_goal.dart';
import 'package:test/test.dart';

import '../../test_helper.dart';

/// Helper to create a SkillState at a specific level.
SkillState skillStateAtLevel(int level) {
  return SkillState(xp: startXpForLevel(level), masteryPoolXp: 0);
}

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('AllSkills99Goal', () {
    test('includedSkills excludes specified skills', () {
      const goal = AllSkills99Goal(excludedSkills: {Skill.combat, Skill.town});

      expect(goal.includedSkills, isNot(contains(Skill.combat)));
      expect(goal.includedSkills, isNot(contains(Skill.town)));
      expect(goal.includedSkills, contains(Skill.woodcutting));
    });

    test('trainableSkills filters non-trainable skills', () {
      const goal = AllSkills99Goal();
      final trainable = goal.trainableSkills;

      // Combat, hitpoints, town, farming are not trainable
      expect(trainable, isNot(contains(Skill.combat)));
      expect(trainable, isNot(contains(Skill.hitpoints)));
      expect(trainable, isNot(contains(Skill.town)));
      expect(trainable, isNot(contains(Skill.farming)));

      // Woodcutting is trainable
      expect(trainable, contains(Skill.woodcutting));
    });

    test('isSatisfied returns true when all skills at target', () {
      // Create state with all trainable skills at 99
      final skillStates = <Skill, SkillState>{};
      const goal = AllSkills99Goal();
      for (final skill in goal.trainableSkills) {
        skillStates[skill] = skillStateAtLevel(99);
      }

      final state = GlobalState.test(testRegistries, skillStates: skillStates);
      expect(goal.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when any skill below target', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {
          Skill.woodcutting: skillStateAtLevel(99),
          Skill.fishing: skillStateAtLevel(50), // Below 99
        },
      );

      const goal = AllSkills99Goal();
      expect(goal.isSatisfied(state), isFalse);
    });

    test('minSkillLevel returns lowest level', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {
          Skill.woodcutting: skillStateAtLevel(50),
          Skill.fishing: skillStateAtLevel(30),
          Skill.mining: skillStateAtLevel(75),
        },
      );

      const goal = AllSkills99Goal();
      expect(goal.minSkillLevel(state), 1); // Default is 1, not 30
    });

    test('minSkillLevel with explicit skills', () {
      // Set ALL trainable skills to specific levels
      final skillStates = <Skill, SkillState>{};
      const goal = AllSkills99Goal();
      for (final skill in goal.trainableSkills) {
        skillStates[skill] = skillStateAtLevel(50);
      }
      // Make one skill the minimum
      skillStates[Skill.fishing] = skillStateAtLevel(25);

      final state = GlobalState.test(testRegistries, skillStates: skillStates);
      expect(goal.minSkillLevel(state), 25);
    });

    test('unfinishedSkills returns skills below target', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {
          Skill.woodcutting: skillStateAtLevel(99),
          Skill.fishing: skillStateAtLevel(50),
        },
      );

      const goal = AllSkills99Goal();
      final unfinished = goal.unfinishedSkills(state);

      expect(unfinished, isNot(contains(Skill.woodcutting)));
      expect(unfinished, contains(Skill.fishing));
    });

    test('progress returns correct counts', () {
      // Set all trainable skills to 99 except two
      final skillStates = <Skill, SkillState>{};
      const goal = AllSkills99Goal();
      for (final skill in goal.trainableSkills) {
        skillStates[skill] = skillStateAtLevel(99);
      }
      skillStates[Skill.fishing] = skillStateAtLevel(50);
      skillStates[Skill.mining] = skillStateAtLevel(75);

      final state = GlobalState.test(testRegistries, skillStates: skillStates);
      final prog = goal.progress(state);

      expect(prog.total, goal.trainableSkills.length);
      expect(prog.completed, goal.trainableSkills.length - 2);
    });

    test('describe returns readable text', () {
      const goal1 = AllSkills99Goal();
      expect(goal1.describe(), 'All Skills 99');

      const goal2 = AllSkills99Goal(targetLevel: 50);
      expect(goal2.describe(), 'All Skills 50');

      const goal3 = AllSkills99Goal(excludedSkills: {Skill.combat});
      expect(goal3.describe(), contains('excluding'));
    });

    test('toJson and fromJson roundtrip', () {
      const goal = AllSkills99Goal(
        excludedSkills: {Skill.combat, Skill.farming},
        targetLevel: 75,
      );

      final json = goal.toJson();
      final restored = MetaGoal.fromJson(json) as AllSkills99Goal;

      expect(restored.excludedSkills, goal.excludedSkills);
      expect(restored.targetLevel, goal.targetLevel);
    });

    test('equality works correctly', () {
      const goal1 = AllSkills99Goal(targetLevel: 50);
      const goal2 = AllSkills99Goal(targetLevel: 50);
      const goal3 = AllSkills99Goal(targetLevel: 75);

      expect(goal1, equals(goal2));
      expect(goal1, isNot(equals(goal3)));
    });
  });
}
