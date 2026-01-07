/// Meta-level goals for the Level 3 meta planner.
///
/// [MetaGoal] represents high-level objectives like "all skills to 99" that
/// the meta planner decomposes into phases and milestones.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// High-level goal for the meta planner.
///
/// Unlike Goal in the Level 2 solver which tracks progress in fine-grained
/// units (XP, GP), [MetaGoal] represents strategic objectives that get
/// decomposed into milestones and phases.
@immutable
sealed class MetaGoal extends Equatable {
  const MetaGoal();

  /// Human-readable description of this goal.
  String describe();

  /// Check if this goal is satisfied in the given state.
  bool isSatisfied(GlobalState state);

  /// Serialization support.
  Map<String, dynamic> toJson();

  /// Deserialize a meta goal from JSON.
  static MetaGoal fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'AllSkills99Goal' => AllSkills99Goal.fromJson(json),
      _ => throw ArgumentError('Unknown MetaGoal type: $type'),
    };
  }
}

/// Train all skills to level 99.
///
/// This is the primary goal for the initial meta planner implementation.
/// Skills can be excluded (e.g., combat skills, farming) via [excludedSkills].
@immutable
class AllSkills99Goal extends MetaGoal {
  const AllSkills99Goal({
    this.excludedSkills = const {},
    this.targetLevel = 99,
  });

  factory AllSkills99Goal.fromJson(Map<String, dynamic> json) {
    final excludedList = json['excludedSkills'] as List<dynamic>? ?? [];
    return AllSkills99Goal(
      excludedSkills: excludedList
          .map((s) => Skill.fromName(s as String))
          .toSet(),
      targetLevel: json['targetLevel'] as int? ?? 99,
    );
  }

  /// Skills to exclude from the goal.
  final Set<Skill> excludedSkills;

  /// Target level for all skills (default 99).
  final int targetLevel;

  /// Default set of skills to exclude (non-trainable or special).
  static const Set<Skill> defaultExcludedSkills = {
    Skill.combat, // Meta skill, not directly trainable
    Skill.hitpoints, // Trained via combat
    Skill.town, // Township, different system
    Skill.farming, // Time-gated, different planning
  };

  /// Get all skills that are part of this goal (not excluded).
  Set<Skill> get includedSkills {
    return Skill.values.toSet().difference(excludedSkills);
  }

  /// Get trainable skills (included and actually trainable).
  Set<Skill> get trainableSkills {
    return includedSkills.where(_isTrainableSkill).toSet();
  }

  @override
  String describe() {
    if (targetLevel == 99 && excludedSkills.isEmpty) {
      return 'All Skills 99';
    }
    if (targetLevel != 99) {
      return 'All Skills $targetLevel';
    }
    final excluded = excludedSkills.map((s) => s.name).join(', ');
    return 'All Skills 99 (excluding $excluded)';
  }

  @override
  bool isSatisfied(GlobalState state) {
    for (final skill in trainableSkills) {
      if (state.skillState(skill).skillLevel < targetLevel) {
        return false;
      }
    }
    return true;
  }

  /// Get the minimum skill level across all trainable skills.
  int minSkillLevel(GlobalState state) {
    var minLevel = targetLevel;
    for (final skill in trainableSkills) {
      final level = state.skillState(skill).skillLevel;
      if (level < minLevel) {
        minLevel = level;
      }
    }
    return minLevel;
  }

  /// Get skills that haven't reached the target level.
  Set<Skill> unfinishedSkills(GlobalState state) {
    return trainableSkills
        .where((s) => state.skillState(s).skillLevel < targetLevel)
        .toSet();
  }

  /// Get progress as a tuple of (completed skills, total skills).
  ({int completed, int total}) progress(GlobalState state) {
    final skills = trainableSkills;
    final completed = skills.where(
      (s) => state.skillState(s).skillLevel >= targetLevel,
    );
    return (completed: completed.length, total: skills.length);
  }

  bool _isTrainableSkill(Skill skill) {
    // Skills that can be directly trained via non-combat skill actions.
    // Combat skills require different handling (monster selection, gear, etc.)
    return !const {
      Skill.combat, // Meta skill
      Skill.hitpoints, // Gained via combat
      Skill.attack, // Combat skill
      Skill.strength, // Combat skill
      Skill.defence, // Combat skill
      Skill.ranged, // Combat skill
      Skill.magic, // Combat skill (also has Alt. Magic)
      Skill.prayer, // Combat-related
      Skill.slayer, // Combat-related
      Skill.town, // Township - different system
      Skill.farming, // Time-gated
    }.contains(skill);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'AllSkills99Goal',
    'excludedSkills': excludedSkills.map((s) => s.name).toList(),
    'targetLevel': targetLevel,
  };

  @override
  List<Object?> get props => [excludedSkills, targetLevel];
}
