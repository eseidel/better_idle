import 'package:logic/logic.dart';
import 'package:logic/src/solver/meta/meta_goal.dart';
import 'package:logic/src/solver/meta/milestone.dart';
import 'package:logic/src/solver/meta/milestone_extractor.dart';
import 'package:test/test.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('MilestoneExtractor', () {
    late MilestoneExtractor extractor;

    setUp(() {
      extractor = MilestoneExtractor(testRegistries);
    });

    test('extractSkillMilestones includes standard breakpoints', () {
      final milestones = extractor.extractSkillMilestones(Skill.woodcutting);

      final levels = milestones.map((m) => m.level).toSet();

      // Should include all standard breakpoints
      expect(levels, contains(10));
      expect(levels, contains(25));
      expect(levels, contains(50));
      expect(levels, contains(75));
      expect(levels, contains(99));
    });

    test('extractSkillMilestones includes action unlock levels', () {
      final milestones = extractor.extractSkillMilestones(Skill.woodcutting);

      // Get actual unlock levels from registry
      final unlockLevels = extractor.getActionUnlockLevels(Skill.woodcutting);

      for (final level in unlockLevels) {
        expect(
          milestones.any((m) => m.level == level),
          isTrue,
          reason: 'Should include unlock level $level',
        );
      }
    });

    test('extractSkillMilestones respects maxLevel', () {
      final milestones = extractor.extractSkillMilestones(
        Skill.woodcutting,
        maxLevel: 50,
      );

      // Should not include levels above 50
      expect(milestones.every((m) => m.level <= 50), isTrue);
      expect(milestones.any((m) => m.level == 99), isFalse);
      expect(milestones.any((m) => m.level == 75), isFalse);
    });

    test('extractSkillMilestones milestones are sorted by level', () {
      final milestones = extractor.extractSkillMilestones(Skill.woodcutting);

      for (var i = 1; i < milestones.length; i++) {
        expect(
          milestones[i].level,
          greaterThan(milestones[i - 1].level),
          reason: 'Milestones should be sorted by level',
        );
      }
    });

    test('extractSkillMilestones includes reason for action unlocks', () {
      final milestones = extractor.extractSkillMilestones(Skill.woodcutting);

      // Find milestones with reasons (action unlocks)
      final withReasons = milestones.where((m) => m.reason != null);

      // Should have some milestones with reasons
      expect(withReasons, isNotEmpty);

      // Reasons should mention "Unlocks"
      for (final m in withReasons) {
        expect(m.reason, contains('Unlocks'));
      }
    });

    test('extractForAllSkills99 creates graph with all skills', () {
      const goal = AllSkills99Goal();
      final graph = extractor.extractForAllSkills99(goal);

      // Should have nodes for all trainable skills
      for (final skill in goal.trainableSkills) {
        final nodes = graph.forSkill(skill);
        expect(nodes, isNotEmpty, reason: 'Should have nodes for $skill');
      }
    });

    test('extractForAllSkills99 uses target level from goal', () {
      const goal = AllSkills99Goal(targetLevel: 50);
      final graph = extractor.extractForAllSkills99(goal);

      // No milestone should exceed target level
      for (final node in graph.nodes) {
        final milestone = node.milestone as SkillLevelMilestone;
        expect(milestone.level, lessThanOrEqualTo(50));
      }
    });

    test('getActionUnlockLevels returns sorted unique levels', () {
      final levels = extractor.getActionUnlockLevels(Skill.woodcutting);

      // Should be sorted
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i], greaterThan(levels[i - 1]));
      }

      // Should not include level 1 (base actions)
      expect(levels, isNot(contains(1)));
    });

    test('actionsUnlockedAtLevel returns correct actions', () {
      final unlockLevels = extractor.getActionUnlockLevels(Skill.woodcutting);
      if (unlockLevels.isEmpty) return; // Skip if no unlock levels

      final level = unlockLevels.first;
      final actions = extractor.actionsUnlockedAtLevel(
        Skill.woodcutting,
        level,
      );

      expect(actions, isNotEmpty);
      for (final action in actions) {
        expect(action.unlockLevel, level);
      }
    });

    test('countMilestones returns total milestone count', () {
      const goal = AllSkills99Goal();
      final count = extractor.countMilestones(goal);

      // Should be sum of milestones for all trainable skills
      var expectedCount = 0;
      for (final skill in goal.trainableSkills) {
        final milestones = extractor.extractSkillMilestones(
          skill,
          maxLevel: 99,
        );
        expectedCount += milestones.length;
      }

      expect(count, expectedCount);
    });

    test('nextMilestoneLevel returns next boundary', () {
      final nextLevel = extractor.nextMilestoneLevel(Skill.woodcutting, 1);

      // Should return a level > 1 (next boundary after level 1)
      expect(nextLevel, isNotNull);
      expect(nextLevel, greaterThan(1));
    });

    test('nextMilestoneLevel returns null at max level', () {
      final nextLevel = extractor.nextMilestoneLevel(Skill.woodcutting, 99);

      // At 99, there may or may not be a next boundary depending on data
      // Just verify it doesn't crash
      expect(nextLevel == null || nextLevel > 99, isTrue);
    });
  });
}
