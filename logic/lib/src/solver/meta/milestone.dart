/// Milestone abstraction for Level 3 meta planning.
///
/// Milestones are checkable predicates on game state, derived from game data.
/// They represent meaningful decision points where strategy should be
/// re-evaluated.
///
/// ## Design Notes
///
/// For v1, we only implement [SkillLevelMilestone]. Additional milestone types
/// (shop purchases, GP thresholds, items) can be added as needed.
///
/// The [MilestoneGraph] provides a simple frontier computation without
/// dependency edges initially - Level 2 discovers prerequisites
/// opportunistically.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// A checkable predicate on game state, derived from game data.
@immutable
sealed class Milestone extends Equatable {
  const Milestone();

  /// Unique identifier for this milestone.
  String get id;

  /// Check if this milestone is satisfied in the given state.
  bool isSatisfied(GlobalState state);

  /// Human-readable description.
  String describe();

  /// Serialization support.
  Map<String, dynamic> toJson();

  /// Deserialize a milestone from JSON.
  static Milestone fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'SkillLevelMilestone' => SkillLevelMilestone.fromJson(json),
      _ => throw ArgumentError('Unknown Milestone type: $type'),
    };
  }
}

/// Reach a specific skill level (e.g., Woodcutting 50).
///
/// The most common milestone type, used for tracking skill progression
/// and action unlocks.
@immutable
class SkillLevelMilestone extends Milestone {
  const SkillLevelMilestone({
    required this.skill,
    required this.level,
    this.reason,
  });

  factory SkillLevelMilestone.fromJson(Map<String, dynamic> json) {
    return SkillLevelMilestone(
      skill: Skill.fromName(json['skill'] as String),
      level: json['level'] as int,
      reason: json['reason'] as String?,
    );
  }

  /// The skill this milestone targets.
  final Skill skill;

  /// The level to reach.
  final int level;

  /// Optional reason why this milestone exists (e.g., "Unlocks Oak Trees").
  final String? reason;

  @override
  String get id => 'skill:${skill.name}:$level';

  @override
  bool isSatisfied(GlobalState state) =>
      state.skillState(skill).skillLevel >= level;

  @override
  String describe() {
    final base = '${skill.name} L$level';
    return reason != null ? '$base ($reason)' : base;
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'SkillLevelMilestone',
    'skill': skill.name,
    'level': level,
    if (reason != null) 'reason': reason,
  };

  @override
  List<Object?> get props => [skill, level, reason];
}

/// A node in the milestone graph.
///
/// Wraps a [Milestone] with optional metadata like estimated ticks.
@immutable
class MilestoneNode extends Equatable {
  const MilestoneNode({required this.milestone, this.estimatedTicksFromStart});

  final Milestone milestone;

  /// Optional estimate of ticks from initial state to achieve this milestone.
  final int? estimatedTicksFromStart;

  @override
  List<Object?> get props => [milestone, estimatedTicksFromStart];
}

/// An edge representing dependency between milestones.
///
/// Not used in v1, but the structure is here for future dependency graphs.
@immutable
class MilestoneEdge extends Equatable {
  const MilestoneEdge({required this.from, required this.to, this.reason});

  /// Milestone ID that must be satisfied first.
  final String from;

  /// Milestone ID that depends on [from].
  final String to;

  /// Optional reason for this dependency.
  final String? reason;

  @override
  List<Object?> get props => [from, to, reason];
}

/// The complete milestone graph for a meta goal.
///
/// For v1, this is essentially a flat list of milestones with simple
/// frontier computation (all unsatisfied milestones are in the frontier).
/// Dependency edges can be added later.
@immutable
class MilestoneGraph {
  const MilestoneGraph({required this.nodes, this.edges = const []});

  final List<MilestoneNode> nodes;
  final List<MilestoneEdge> edges;

  /// Get milestone node by ID.
  MilestoneNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.milestone.id == id) return node;
    }
    return null;
  }

  /// Get all milestones that depend on this one.
  List<MilestoneNode> dependents(String milestoneId) {
    final result = <MilestoneNode>[];
    for (final edge in edges) {
      if (edge.from == milestoneId) {
        final node = nodeById(edge.to);
        if (node != null) result.add(node);
      }
    }
    return result;
  }

  /// Get all milestones this one depends on.
  List<MilestoneNode> dependencies(String milestoneId) {
    final result = <MilestoneNode>[];
    for (final edge in edges) {
      if (edge.to == milestoneId) {
        final node = nodeById(edge.from);
        if (node != null) result.add(node);
      }
    }
    return result;
  }

  /// Get frontier: milestones whose dependencies are all satisfied.
  ///
  /// In v1 (no dependency edges), this returns all unsatisfied milestones.
  /// With edges, it filters to only those with all dependencies met.
  List<MilestoneNode> frontier(GlobalState state) {
    return nodes.where((node) {
      // Already satisfied - not in frontier
      if (node.milestone.isSatisfied(state)) return false;

      // Check all dependencies are satisfied
      final deps = dependencies(node.milestone.id);
      return deps.every((d) => d.milestone.isSatisfied(state));
    }).toList();
  }

  /// Get all unsatisfied milestones (regardless of dependencies).
  List<MilestoneNode> unsatisfied(GlobalState state) {
    return nodes.where((node) => !node.milestone.isSatisfied(state)).toList();
  }

  /// Get all satisfied milestones.
  List<MilestoneNode> satisfied(GlobalState state) {
    return nodes.where((node) => node.milestone.isSatisfied(state)).toList();
  }

  /// Count of milestones by satisfaction status.
  ({int satisfied, int unsatisfied, int total}) countStatus(GlobalState state) {
    var satisfiedCount = 0;
    var unsatisfiedCount = 0;
    for (final node in nodes) {
      if (node.milestone.isSatisfied(state)) {
        satisfiedCount++;
      } else {
        unsatisfiedCount++;
      }
    }
    return (
      satisfied: satisfiedCount,
      unsatisfied: unsatisfiedCount,
      total: nodes.length,
    );
  }

  /// Get milestones for a specific skill.
  List<MilestoneNode> forSkill(Skill skill) {
    return nodes.where((node) {
      final m = node.milestone;
      return m is SkillLevelMilestone && m.skill == skill;
    }).toList();
  }

  /// Get the next unsatisfied milestone for a skill (by level order).
  MilestoneNode? nextForSkill(Skill skill, GlobalState state) {
    final skillNodes = forSkill(
      skill,
    ).where((n) => !n.milestone.isSatisfied(state)).toList();

    if (skillNodes.isEmpty) return null;

    // Sort by level and return the lowest
    skillNodes.sort((a, b) {
      final aLevel = (a.milestone as SkillLevelMilestone).level;
      final bLevel = (b.milestone as SkillLevelMilestone).level;
      return aLevel.compareTo(bLevel);
    });

    return skillNodes.first;
  }
}
