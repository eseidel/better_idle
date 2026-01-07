/// Milestone extraction from game data.
///
/// Extracts meaningful milestones from game data for use by the meta planner.
/// For v1, we extract:
/// - Action unlock levels from ActionRegistry
/// - Fixed breakpoints per skill (10, 25, 50, 75, 99)
///
/// ## Design Notes
///
/// We intentionally keep v1 simple - NO dependency graph yet.
/// Level 2 discovers prerequisites opportunistically.
/// Later iterations can add shop/mastery/dependency edges.
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/meta/meta_goal.dart';
import 'package:logic/src/solver/meta/milestone.dart';

/// Standard breakpoint levels added for all skills.
const List<int> _standardBreakpoints = [10, 25, 50, 75, 99];

/// Extracts meaningful milestones from game data.
class MilestoneExtractor {
  MilestoneExtractor(this.registries);

  final Registries registries;

  /// Cached unlock boundaries (computed once).
  Map<Skill, SkillBoundaries>? _unlockBoundaries;

  /// Get unlock boundaries, computing if needed.
  Map<Skill, SkillBoundaries> get unlockBoundaries {
    return _unlockBoundaries ??= computeUnlockBoundaries(registries);
  }

  /// Extracts all skill level milestones for a given skill.
  ///
  /// Returns milestones at:
  /// - Action unlock levels (from game data)
  /// - Standard breakpoints (10, 25, 50, 75, 99)
  ///
  /// Milestones are deduplicated and sorted by level.
  List<SkillLevelMilestone> extractSkillMilestones(
    Skill skill, {
    int? maxLevel,
  }) {
    final effectiveMaxLevel = maxLevel ?? 99;
    final milestoneLevels = <int, String?>{};

    // 1. Action unlock levels from ActionRegistry
    for (final action in registries.actions.forSkill(skill)) {
      final unlockLevel = action.unlockLevel;
      if (unlockLevel > 1 && unlockLevel <= effectiveMaxLevel) {
        // Record the reason (action name that unlocks)
        final existingReason = milestoneLevels[unlockLevel];
        if (existingReason == null) {
          milestoneLevels[unlockLevel] = 'Unlocks ${action.name}';
        } else {
          // Multiple unlocks at same level - append
          milestoneLevels[unlockLevel] = '$existingReason, ${action.name}';
        }
      }
    }

    // 2. Standard breakpoints (no specific reason)
    for (final level in _standardBreakpoints) {
      if (level <= effectiveMaxLevel) {
        milestoneLevels.putIfAbsent(level, () => null);
      }
    }

    // Convert to sorted list of milestones
    final sortedLevels = milestoneLevels.keys.toList()..sort();
    return sortedLevels.map((level) {
      return SkillLevelMilestone(
        skill: skill,
        level: level,
        reason: milestoneLevels[level],
      );
    }).toList();
  }

  /// Extracts milestones for the AllSkills99 goal.
  ///
  /// For each trainable skill, extracts action unlock and breakpoint
  /// milestones. Returns a [MilestoneGraph] with no dependency edges (v1).
  MilestoneGraph extractForAllSkills99(AllSkills99Goal goal) {
    final nodes = <MilestoneNode>[];

    for (final skill in goal.trainableSkills) {
      final skillMilestones = extractSkillMilestones(
        skill,
        maxLevel: goal.targetLevel,
      );

      for (final milestone in skillMilestones) {
        nodes.add(MilestoneNode(milestone: milestone));
      }
    }

    // No dependency edges in v1
    return MilestoneGraph(nodes: nodes);
  }

  /// Get the next milestone level for a skill given current level.
  ///
  /// Uses unlock boundaries for fast lookup.
  int? nextMilestoneLevel(Skill skill, int currentLevel) {
    final boundaries = unlockBoundaries[skill];
    if (boundaries == null) return null;
    return boundaries.nextBoundary(currentLevel);
  }

  /// Get all unlock levels for a skill (from action registry).
  List<int> getActionUnlockLevels(Skill skill) {
    final levels = <int>{};
    for (final action in registries.actions.forSkill(skill)) {
      if (action.unlockLevel > 1) {
        levels.add(action.unlockLevel);
      }
    }
    return levels.toList()..sort();
  }

  /// Get actions that unlock at a specific level for a skill.
  List<SkillAction> actionsUnlockedAtLevel(Skill skill, int level) {
    return registries.actions
        .forSkill(skill)
        .where((a) => a.unlockLevel == level)
        .toList();
  }

  /// Count total milestones that would be extracted for a goal.
  int countMilestones(AllSkills99Goal goal) {
    var count = 0;
    for (final skill in goal.trainableSkills) {
      final milestones = extractSkillMilestones(
        skill,
        maxLevel: goal.targetLevel,
      );
      count += milestones.length;
    }
    return count;
  }
}
