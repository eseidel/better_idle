// Mastery Level Bonus System
//
// This module parses and stores mastery level bonuses from the Melvor Idle
// JSON data files. Mastery bonuses are per-skill bonuses that activate at
// certain mastery levels for individual actions.
//
// ## Template Modifiers
//
// All masteryLevelBonuses modifiers are **templates**. The scope keys
// (skillID, actionID) in the JSON are placeholder examples, not actual
// filters. At evaluation time, these get substituted with the actual action
// being evaluated.
//
// For example, Fishing's mastery bonus:
// ```json
// { "fishingMasteryDoublingChance": [{ "actionID": "melvorD:Raw_Shrimp", "value": 0.4 }] }
// ```
// The "Raw_Shrimp" is just an example - at runtime this applies to whatever
// fish you're catching.
//
// The `autoScopeToAction` field (default: true) controls template behavior.
// When false, the modifier applies globally without action substitution
// (e.g., Firemaking's level 99 bonus gives +0.25% Mastery XP to all skills).

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

/// A single mastery level bonus entry.
///
/// Represents a bonus that activates at a certain mastery level, optionally
/// repeating at intervals up to a maximum level.
@immutable
class MasteryLevelBonus extends Equatable {
  const MasteryLevelBonus({
    required this.modifiers,
    required this.level,
    this.levelScalingSlope,
    this.levelScalingMax,
    this.autoScopeToAction = true,
  });

  factory MasteryLevelBonus.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final modifiersJson = json['modifiers'] as Map<String, dynamic>?;
    final modifiers = modifiersJson != null
        ? ModifierDataSet.fromJson(modifiersJson, namespace: namespace)
        : const ModifierDataSet([]);

    return MasteryLevelBonus(
      modifiers: modifiers,
      level: json['level'] as int,
      levelScalingSlope: json['levelScalingSlope'] as int?,
      levelScalingMax: json['levelScalingMax'] as int?,
      autoScopeToAction: json['autoScopeToAction'] as bool? ?? true,
    );
  }

  /// The modifiers granted by this bonus.
  final ModifierDataSet modifiers;

  /// The mastery level at which this bonus first activates.
  final int level;

  /// If set, bonus repeats every N levels (e.g., slope=10 means 10, 20, 30...).
  final int? levelScalingSlope;

  /// Max level for scaling (bonus stops repeating after this level).
  final int? levelScalingMax;

  /// If true (default), actionID-only scopes are template placeholders.
  /// If false, modifiers apply as-is without substitution.
  final bool autoScopeToAction;

  /// Returns how many times this bonus applies at the given mastery level.
  ///
  /// For non-scaling bonuses, returns 1 if masteryLevel >= level, else 0.
  /// For scaling bonuses, counts how many times the bonus has triggered.
  int countAtLevel(int masteryLevel) {
    if (masteryLevel < level) return 0;
    if (levelScalingSlope == null) return 1;

    // Calculate how many times the bonus triggers
    // Triggers at: level, level + slope, level + 2*slope, ...
    // Up to levelScalingMax (if set)
    final maxLevel = levelScalingMax ?? masteryLevel;
    final effectiveMax = masteryLevel < maxLevel ? masteryLevel : maxLevel;

    if (effectiveMax < level) return 0;

    // Count triggers: (effectiveMax - level) / slope + 1
    return ((effectiveMax - level) ~/ levelScalingSlope!) + 1;
  }

  @override
  List<Object?> get props => [
    modifiers,
    level,
    levelScalingSlope,
    levelScalingMax,
    autoScopeToAction,
  ];
}

/// Collection of mastery level bonuses for a single skill.
@immutable
class SkillMasteryBonuses extends Equatable {
  const SkillMasteryBonuses({required this.skillId, required this.bonuses});

  /// The skill these bonuses belong to.
  final MelvorId skillId;

  /// All mastery level bonuses for this skill.
  final List<MasteryLevelBonus> bonuses;

  @override
  List<Object?> get props => [skillId, bonuses];
}

/// Registry for looking up mastery bonuses by skill.
class MasteryBonusRegistry {
  MasteryBonusRegistry(List<SkillMasteryBonuses> bonuses)
    : _bySkillId = {for (final b in bonuses) b.skillId: b};

  final Map<MelvorId, SkillMasteryBonuses> _bySkillId;

  /// Get mastery bonuses for a skill, or null if not found.
  SkillMasteryBonuses? forSkill(MelvorId skillId) => _bySkillId[skillId];

  /// All skills with mastery bonuses.
  Iterable<MelvorId> get skillIds => _bySkillId.keys;

  /// Total number of skills with mastery bonuses.
  int get length => _bySkillId.length;
}

/// Parses masteryLevelBonuses from a skill's data entry.
List<MasteryLevelBonus> parseMasteryLevelBonuses(
  Map<String, dynamic> skillData, {
  required String namespace,
}) {
  final bonusesJson = skillData['masteryLevelBonuses'] as List<dynamic>?;
  if (bonusesJson == null) return [];

  return bonusesJson
      .map(
        (json) => MasteryLevelBonus.fromJson(
          json as Map<String, dynamic>,
          namespace: namespace,
        ),
      )
      .toList();
}
