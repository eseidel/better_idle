// Mastery Pool Bonus System
//
// This module parses and stores mastery pool bonuses (checkpoints) from the
// Melvor Idle JSON data files. These are per-skill bonuses that activate when
// the mastery pool reaches certain percentage thresholds (10%, 25%, 50%, 95%).
//
// Unlike masteryLevelBonuses (which are per-action mastery level bonuses),
// mastery pool bonuses apply skill-wide when you've accumulated enough total
// mastery XP in the pool.

import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

/// A single mastery pool bonus entry.
///
/// Represents a bonus that activates when the mastery pool reaches a certain
/// percentage threshold.
@immutable
class MasteryPoolBonus {
  const MasteryPoolBonus({
    required this.percent,
    required this.modifiers,
    this.realm,
  });

  factory MasteryPoolBonus.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final modifiersJson = json['modifiers'] as Map<String, dynamic>?;
    final modifiers = modifiersJson != null
        ? ModifierDataSet.fromJson(modifiersJson, namespace: namespace)
        : const ModifierDataSet([]);

    final realmString = json['realm'] as String?;

    return MasteryPoolBonus(
      percent: json['percent'] as int,
      modifiers: modifiers,
      realm: realmString != null ? MelvorId.fromJson(realmString) : null,
    );
  }

  /// The percentage threshold at which this bonus activates
  /// (e.g., 10, 25, 50, 95).
  final int percent;

  /// The modifiers granted by this bonus.
  final ModifierDataSet modifiers;

  /// The realm this bonus applies to (if realm-specific).
  final MelvorId? realm;

  /// Returns true if this bonus is active at the given pool percentage.
  bool isActiveAt(double poolPercent) => poolPercent >= percent;
}

/// Collection of mastery pool bonuses for a single skill.
@immutable
class SkillMasteryPoolBonuses {
  const SkillMasteryPoolBonuses({required this.skillId, required this.bonuses});

  /// The skill these bonuses belong to.
  final MelvorId skillId;

  /// All mastery pool bonuses for this skill, typically at 10%, 25%, 50%, 95%.
  final List<MasteryPoolBonus> bonuses;
}

/// Registry for looking up mastery pool bonuses by skill.
@immutable
class MasteryPoolBonusRegistry {
  MasteryPoolBonusRegistry(List<SkillMasteryPoolBonuses> bonuses)
    : _bySkillId = {for (final b in bonuses) b.skillId: b};

  final Map<MelvorId, SkillMasteryPoolBonuses> _bySkillId;

  /// Get mastery pool bonuses for a skill, or null if not found.
  SkillMasteryPoolBonuses? forSkill(MelvorId skillId) => _bySkillId[skillId];

  /// All skills with mastery pool bonuses.
  Iterable<MelvorId> get skillIds => _bySkillId.keys;
}

/// Parses masteryPoolBonuses from a skill's data entry.
List<MasteryPoolBonus> parseMasteryPoolBonuses(
  Map<String, dynamic> skillData, {
  required String namespace,
}) {
  final bonusesJson = skillData['masteryPoolBonuses'] as List<dynamic>?;
  if (bonusesJson == null) return [];

  final bonuses =
      bonusesJson
          .map(
            (json) => MasteryPoolBonus.fromJson(
              json as Map<String, dynamic>,
              namespace: namespace,
            ),
          )
          .toList()
        // Sort by percent ascending
        ..sort((a, b) => a.percent.compareTo(b.percent));

  return bonuses;
}
