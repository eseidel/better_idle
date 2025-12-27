// Mastery Level Unlock Display System
//
// This module parses and stores mastery level unlock descriptions from the
// Melvor Idle JSON data files. These are display-only descriptions that tell
// the player what bonuses they receive at each mastery level.
//
// Unlike masteryLevelBonuses (which contain actual modifier data for game
// mechanics), masteryLevelUnlocks are purely for UI display purposes.

import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A single mastery level unlock entry.
///
/// Represents a description of what bonus is unlocked at a certain mastery
/// level. This is display-only data.
@immutable
class MasteryLevelUnlock {
  const MasteryLevelUnlock({required this.level, required this.description});

  factory MasteryLevelUnlock.fromJson(Map<String, dynamic> json) {
    return MasteryLevelUnlock(
      level: json['level'] as int,
      description: json['description'] as String,
    );
  }

  /// The mastery level at which this unlock activates.
  final int level;

  /// Human-readable description of the bonus.
  final String description;
}

/// Collection of mastery level unlocks for a single skill.
@immutable
class SkillMasteryUnlocks {
  const SkillMasteryUnlocks({required this.skillId, required this.unlocks});

  /// The skill these unlocks belong to.
  final MelvorId skillId;

  /// All mastery level unlocks for this skill, sorted by level.
  final List<MasteryLevelUnlock> unlocks;
}

/// Registry for looking up mastery unlocks by skill.
class MasteryUnlockRegistry {
  MasteryUnlockRegistry(List<SkillMasteryUnlocks> unlocks)
    : _bySkillId = {for (final u in unlocks) u.skillId: u};

  final Map<MelvorId, SkillMasteryUnlocks> _bySkillId;

  /// Get mastery unlocks for a skill, or null if not found.
  SkillMasteryUnlocks? forSkill(MelvorId skillId) => _bySkillId[skillId];

  /// All skills with mastery unlocks.
  Iterable<MelvorId> get skillIds => _bySkillId.keys;
}

/// Parses masteryLevelUnlocks from a skill's data entry.
List<MasteryLevelUnlock> parseMasteryLevelUnlocks(
  Map<String, dynamic> skillData,
) {
  final unlocksJson = skillData['masteryLevelUnlocks'] as List<dynamic>?;
  if (unlocksJson == null) return [];

  final unlocks =
      unlocksJson
          .map(
            (json) => MasteryLevelUnlock.fromJson(json as Map<String, dynamic>),
          )
          .toList()
        // Sort by level ascending
        ..sort((a, b) => a.level.compareTo(b.level));

  return unlocks;
}
