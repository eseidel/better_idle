/// Scheduling policies for Level 3 meta planning.
///
/// Policies define how to allocate time across skills and projects.
/// They constrain interleaving to reduce branching in Level 2.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/meta/milestone.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Base class for scheduling policies.
@immutable
sealed class SchedulingPolicy extends Equatable {
  const SchedulingPolicy();

  /// Policy name for display.
  String get name;

  /// Human-readable description.
  String describe();

  /// Serialization support.
  Map<String, dynamic> toJson();

  /// Deserialize a policy from JSON.
  static SchedulingPolicy fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'BatchSkillPolicy' => BatchSkillPolicy.fromJson(json),
      'RoundRobinByDeficitPolicy' => RoundRobinByDeficitPolicy.fromJson(json),
      'EconomyModePolicy' => EconomyModePolicy.fromJson(json),
      _ => throw ArgumentError('Unknown SchedulingPolicy type: $type'),
    };
  }
}

/// Focus one skill until milestone reached.
///
/// Good for deep unlock ladders (e.g., Mining enabling Smithing).
@immutable
class BatchSkillPolicy extends SchedulingPolicy {
  const BatchSkillPolicy({required this.skill, required this.targetLevel});

  factory BatchSkillPolicy.fromJson(Map<String, dynamic> json) {
    return BatchSkillPolicy(
      skill: Skill.fromName(json['skill'] as String),
      targetLevel: json['targetLevel'] as int,
    );
  }

  final Skill skill;
  final int targetLevel;

  @override
  String get name => 'BatchSkill';

  @override
  String describe() => 'Focus ${skill.name} until L$targetLevel';

  /// Create a milestone for this policy's target.
  SkillLevelMilestone get targetMilestone =>
      SkillLevelMilestone(skill: skill, level: targetLevel);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'BatchSkillPolicy',
    'skill': skill.name,
    'targetLevel': targetLevel,
  };

  @override
  List<Object?> get props => [skill, targetLevel];
}

/// Balance multiple skills by remaining progress (deficit).
///
/// Allocates time to the skill that's furthest behind.
/// Good for AllSkills=99 without thrashing.
@immutable
class RoundRobinByDeficitPolicy extends SchedulingPolicy {
  const RoundRobinByDeficitPolicy({
    required this.skills,
    required this.targetLevel,
  });

  factory RoundRobinByDeficitPolicy.fromJson(Map<String, dynamic> json) {
    final skillsList = json['skills'] as List<dynamic>;
    return RoundRobinByDeficitPolicy(
      skills: skillsList.map((s) => Skill.fromName(s as String)).toList(),
      targetLevel: json['targetLevel'] as int,
    );
  }

  final List<Skill> skills;
  final int targetLevel;

  @override
  String get name => 'RoundRobinByDeficit';

  @override
  String describe() {
    final skillNames = skills.map((s) => s.name).join(', ');
    return 'Balance $skillNames to L$targetLevel';
  }

  /// Get the skill with the lowest current level (most behind).
  Skill? getMostBehindSkill(GlobalState state) {
    Skill? mostBehind;
    var lowestLevel = targetLevel + 1;

    for (final skill in skills) {
      final level = state.skillState(skill).skillLevel;
      if (level < targetLevel && level < lowestLevel) {
        lowestLevel = level;
        mostBehind = skill;
      }
    }

    return mostBehind;
  }

  /// Get skills that haven't reached the target.
  List<Skill> getUnfinishedSkills(GlobalState state) {
    return skills
        .where((s) => state.skillState(s).skillLevel < targetLevel)
        .toList();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'RoundRobinByDeficitPolicy',
    'skills': skills.map((s) => s.name).toList(),
    'targetLevel': targetLevel,
  };

  @override
  List<Object?> get props => [skills, targetLevel];
}

/// Prioritize GP accumulation until target reached.
///
/// Used when shop purchases are gating progress.
@immutable
class EconomyModePolicy extends SchedulingPolicy {
  const EconomyModePolicy({required this.targetGp, this.reason});

  factory EconomyModePolicy.fromJson(Map<String, dynamic> json) {
    return EconomyModePolicy(
      targetGp: json['targetGp'] as int,
      reason: json['reason'] as String?,
    );
  }

  final int targetGp;
  final String? reason;

  @override
  String get name => 'EconomyMode';

  @override
  String describe() {
    final reasonSuffix = reason != null ? ' for $reason' : '';
    return 'Earn $targetGp GP$reasonSuffix';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'EconomyModePolicy',
    'targetGp': targetGp,
    if (reason != null) 'reason': reason,
  };

  @override
  List<Object?> get props => [targetGp, reason];
}
