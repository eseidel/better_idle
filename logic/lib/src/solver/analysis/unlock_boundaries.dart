/// Unlock boundary infrastructure for macro-step planning.
///
/// Boundaries are skill levels where new actions or upgrades become available,
/// representing meaningful decision points where the solver should re-evaluate
/// its strategy.
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/registries.dart';

/// Precomputed unlock boundaries for a skill.
///
/// These are the levels where new actions or upgrades become available.
/// Used by macro-step planning to determine when to stop training and
/// re-evaluate decisions.
class SkillBoundaries {
  const SkillBoundaries(this.skill, this.boundaries);

  final Skill skill;

  /// Sorted list of boundary levels (ascending order).
  /// Example for woodcutting: [1, 10, 25, 35, 45, 60, 75, 90]
  final List<int> boundaries;

  /// Returns the next boundary >= currentLevel, or null if at max.
  ///
  /// Example:
  /// - boundaries = [1, 10, 25, 35]
  /// - nextBoundary(5) → 10
  /// - nextBoundary(10) → 25
  /// - nextBoundary(35) → null
  int? nextBoundary(int currentLevel) {
    for (final boundary in boundaries) {
      if (boundary > currentLevel) {
        return boundary;
      }
    }
    return null; // Already at or past highest boundary
  }

  /// Returns the boundary index for a given level.
  ///
  /// The index represents which "zone" the level is in.
  /// Used for coarse state bucketing in dominance pruning.
  ///
  /// Example:
  /// - boundaries = [1, 10, 25, 35]
  /// - boundaryIndex(1) → 0 (at first boundary)
  /// - boundaryIndex(5) → 0 (before second boundary)
  /// - boundaryIndex(10) → 1 (at second boundary)
  /// - boundaryIndex(30) → 2 (between 25 and 35)
  /// - boundaryIndex(99) → 3 (past last boundary)
  int boundaryIndex(int currentLevel) {
    for (var i = 0; i < boundaries.length; i++) {
      if (currentLevel < boundaries[i]) {
        return i;
      }
    }
    return boundaries.length; // Past all boundaries
  }
}

/// Computes unlock boundaries for all skills given registries.
///
/// For each skill, collects:
/// - Action unlock levels from Registries
/// - Shop upgrade skill level requirements (future extension)
/// - Major mastery thresholds (future extension)
///
/// Returns a map from Skill to SkillBoundaries.
Map<Skill, SkillBoundaries> computeUnlockBoundaries(Registries registries) {
  final boundariesBySkill = <Skill, Set<int>>{};

  // Initialize with level 1 for all skills
  for (final skill in Skill.values) {
    boundariesBySkill[skill] = {1};
  }

  // Collect action unlock levels
  for (final action in registries.allActions) {
    if (action is! SkillAction) continue;

    final skill = action.skill;
    final unlockLevel = action.unlockLevel;

    boundariesBySkill[skill]!.add(unlockLevel);
  }

  // Convert sets to sorted lists
  final result = <Skill, SkillBoundaries>{};
  for (final entry in boundariesBySkill.entries) {
    final sortedBoundaries = entry.value.toList()..sort();
    result[entry.key] = SkillBoundaries(entry.key, sortedBoundaries);
  }

  return result;
}
