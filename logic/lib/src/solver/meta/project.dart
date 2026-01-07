/// Project abstraction for Level 3 meta planning.
///
/// Projects are long-lived strands of progress used to prevent pointless
/// interleaving. They group related activities that should be batched
/// together.
///
/// ## Design Notes
///
/// Projects use lightweight **labels** instead of a closed set of macro types.
/// Labels like `skill:Woodcutting`, `economy`, `inventory` can be used to
/// gate which macros are allowed in a phase. This is easier to evolve than
/// a closed set of macro types.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/meta/milestone.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// A long-lived strand of progress, used to prevent pointless interleaving.
///
/// Projects group related activities that should be batched together.
@immutable
sealed class Project extends Equatable {
  const Project();

  /// Unique identifier for this project.
  String get id;

  /// Human-readable description.
  String describe();

  /// Check if this project is complete.
  bool isComplete(GlobalState state);

  /// Lightweight labels for gating macros.
  ///
  /// Examples: `skill:Woodcutting`, `economy`, `inventory`, `producing`
  Set<String> get labels;

  /// Serialization support.
  Map<String, dynamic> toJson();

  /// Deserialize a project from JSON.
  static Project fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'TrainSkillProject' => TrainSkillProject.fromJson(json),
      _ => throw ArgumentError('Unknown Project type: $type'),
    };
  }
}

/// Training a single skill to target milestone(s).
///
/// This is the primary project type for AllSkills=99.
@immutable
class TrainSkillProject extends Project {
  const TrainSkillProject({
    required this.skill,
    required this.targetMilestones,
  });

  factory TrainSkillProject.fromJson(Map<String, dynamic> json) {
    final skill = Skill.fromName(json['skill'] as String);
    final milestonesJson = json['targetMilestones'] as List<dynamic>;
    final milestones = milestonesJson
        .map((m) => Milestone.fromJson(m as Map<String, dynamic>))
        .cast<SkillLevelMilestone>()
        .toList();
    return TrainSkillProject(skill: skill, targetMilestones: milestones);
  }

  /// The skill to train.
  final Skill skill;

  /// Target milestones for this project.
  final List<SkillLevelMilestone> targetMilestones;

  @override
  String get id => 'train:${skill.name}';

  @override
  String describe() {
    if (targetMilestones.isEmpty) {
      return 'Train ${skill.name}';
    }
    final targets = targetMilestones.map((m) => 'L${m.level}').join(', ');
    return 'Train ${skill.name} to $targets';
  }

  @override
  bool isComplete(GlobalState state) {
    return targetMilestones.every((m) => m.isSatisfied(state));
  }

  @override
  Set<String> get labels => {
    'skill:${skill.name}',
    if (skill.isConsuming) 'consuming',
    if (!skill.isConsuming) 'gathering',
  };

  /// Get the next unsatisfied milestone for this project.
  SkillLevelMilestone? nextMilestone(GlobalState state) {
    for (final m in targetMilestones) {
      if (!m.isSatisfied(state)) return m;
    }
    return null;
  }

  /// Get current level in this skill.
  int currentLevel(GlobalState state) {
    return state.skillState(skill).skillLevel;
  }

  /// Get remaining XP to complete all milestones.
  ///
  /// Note: This is a rough estimate. Actual XP calculation would use xp.dart.
  int remainingXp(GlobalState state) {
    final lastMilestone = targetMilestones.lastOrNull;
    if (lastMilestone == null) return 0;

    final targetLevel = lastMilestone.level;
    final current = currentLevel(state);
    if (current >= targetLevel) return 0;

    // Rough estimate - actual XP calculation would use xp.dart
    return (targetLevel - current) * 10000; // Placeholder
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'TrainSkillProject',
    'skill': skill.name,
    'targetMilestones': targetMilestones.map((m) => m.toJson()).toList(),
  };

  @override
  List<Object?> get props => [skill, targetMilestones];
}

// Future project types to add:
//
// class SupplyChainProject extends Project {
//   // Producer->consumer chain (e.g., Mining->Smithing)
// }
//
// class EconomyProject extends Project {
//   // GP accumulation target
// }
//
// class InventoryProject extends Project {
//   // Free slots target
// }
