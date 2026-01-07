import 'package:logic/logic.dart';
import 'package:logic/src/solver/meta/milestone.dart';
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

  group('SkillLevelMilestone', () {
    test('isSatisfied returns true when level >= target', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {Skill.woodcutting: skillStateAtLevel(10)},
      );
      const milestone = SkillLevelMilestone(
        skill: Skill.woodcutting,
        level: 10,
      );

      expect(milestone.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when level > target', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {Skill.woodcutting: skillStateAtLevel(15)},
      );
      const milestone = SkillLevelMilestone(
        skill: Skill.woodcutting,
        level: 10,
      );

      expect(milestone.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when level < target', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {Skill.woodcutting: skillStateAtLevel(5)},
      );
      const milestone = SkillLevelMilestone(
        skill: Skill.woodcutting,
        level: 10,
      );

      expect(milestone.isSatisfied(state), isFalse);
    });

    test('id format is correct', () {
      const milestone = SkillLevelMilestone(skill: Skill.fishing, level: 25);

      expect(milestone.id, 'skill:Fishing:25');
    });

    test('describe includes skill and level', () {
      const milestone = SkillLevelMilestone(skill: Skill.mining, level: 50);

      expect(milestone.describe(), contains('Mining'));
      expect(milestone.describe(), contains('50'));
    });

    test('describe includes reason when provided', () {
      const milestone = SkillLevelMilestone(
        skill: Skill.mining,
        level: 15,
        reason: 'Unlocks Mithril',
      );

      expect(milestone.describe(), contains('Unlocks Mithril'));
    });

    test('toJson and fromJson roundtrip', () {
      const milestone = SkillLevelMilestone(
        skill: Skill.cooking,
        level: 30,
        reason: 'Unlocks Lobster',
      );

      final json = milestone.toJson();
      final restored = Milestone.fromJson(json) as SkillLevelMilestone;

      expect(restored.skill, milestone.skill);
      expect(restored.level, milestone.level);
      expect(restored.reason, milestone.reason);
    });

    test('equality works correctly', () {
      const milestone1 = SkillLevelMilestone(
        skill: Skill.woodcutting,
        level: 10,
      );
      const milestone2 = SkillLevelMilestone(
        skill: Skill.woodcutting,
        level: 10,
      );
      const milestone3 = SkillLevelMilestone(
        skill: Skill.woodcutting,
        level: 20,
      );

      expect(milestone1, equals(milestone2));
      expect(milestone1, isNot(equals(milestone3)));
    });
  });

  group('MilestoneGraph', () {
    test('frontier returns unsatisfied milestones', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {
          Skill.woodcutting: skillStateAtLevel(15),
          Skill.fishing: skillStateAtLevel(5),
        },
      );

      const nodes = [
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 10),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 25),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.fishing, level: 10),
        ),
      ];

      const graph = MilestoneGraph(nodes: nodes);
      final frontier = graph.frontier(state);

      // WC 10 is satisfied, WC 25 and Fish 10 are not
      expect(frontier.length, 2);
      expect(
        frontier.any(
          (n) =>
              n.milestone is SkillLevelMilestone &&
              (n.milestone as SkillLevelMilestone).skill == Skill.woodcutting &&
              (n.milestone as SkillLevelMilestone).level == 25,
        ),
        isTrue,
      );
      expect(
        frontier.any(
          (n) =>
              n.milestone is SkillLevelMilestone &&
              (n.milestone as SkillLevelMilestone).skill == Skill.fishing &&
              (n.milestone as SkillLevelMilestone).level == 10,
        ),
        isTrue,
      );
    });

    test('nodeById returns correct node', () {
      const milestone = SkillLevelMilestone(skill: Skill.mining, level: 30);
      const nodes = [MilestoneNode(milestone: milestone)];
      const graph = MilestoneGraph(nodes: nodes);

      final node = graph.nodeById('skill:Mining:30');
      expect(node, isNotNull);
      expect(node!.milestone, equals(milestone));
    });

    test('nodeById returns null for unknown id', () {
      const graph = MilestoneGraph(nodes: []);
      expect(graph.nodeById('unknown:id'), isNull);
    });

    test('countStatus returns correct counts', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {Skill.woodcutting: skillStateAtLevel(15)},
      );

      const nodes = [
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 10),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 25),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 50),
        ),
      ];

      const graph = MilestoneGraph(nodes: nodes);
      final status = graph.countStatus(state);

      expect(status.total, 3);
      expect(status.satisfied, 1); // Only level 10
      expect(status.unsatisfied, 2); // Levels 25 and 50
    });

    test('forSkill filters correctly', () {
      const nodes = [
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 10),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.fishing, level: 10),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 25),
        ),
      ];

      const graph = MilestoneGraph(nodes: nodes);
      final wcNodes = graph.forSkill(Skill.woodcutting);

      expect(wcNodes.length, 2);
      expect(
        wcNodes.every(
          (n) =>
              n.milestone is SkillLevelMilestone &&
              (n.milestone as SkillLevelMilestone).skill == Skill.woodcutting,
        ),
        isTrue,
      );
    });

    test('nextForSkill returns lowest unsatisfied milestone', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: {Skill.woodcutting: skillStateAtLevel(15)},
      );

      const nodes = [
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 10),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 50),
        ),
        MilestoneNode(
          milestone: SkillLevelMilestone(skill: Skill.woodcutting, level: 25),
        ),
      ];

      const graph = MilestoneGraph(nodes: nodes);
      final next = graph.nextForSkill(Skill.woodcutting, state);

      expect(next, isNotNull);
      expect((next!.milestone as SkillLevelMilestone).level, 25);
    });
  });
}
