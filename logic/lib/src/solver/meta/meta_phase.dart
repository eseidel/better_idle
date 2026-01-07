/// Meta phase definition for Level 3 planning.
///
/// A phase is a commitment to a strategy for a bounded horizon.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/solver/meta/milestone.dart';
import 'package:logic/src/solver/meta/project.dart';
import 'package:logic/src/solver/meta/scheduling_policy.dart';
import 'package:meta/meta.dart';

/// Targets for a meta phase - what milestones to pursue.
@immutable
class PhaseTargets extends Equatable {
  const PhaseTargets({required this.hardTargets, this.softTargets = const []});

  /// Milestones that MUST be achieved in this phase.
  final List<Milestone> hardTargets;

  /// Milestones that would be nice to achieve (opportunistic).
  final List<Milestone> softTargets;

  /// All targets combined.
  List<Milestone> get allTargets => [...hardTargets, ...softTargets];

  @override
  List<Object?> get props => [hardTargets, softTargets];
}

/// Budget limits for a phase.
@immutable
class PhaseBudget extends Equatable {
  const PhaseBudget({this.maxTicks, this.maxWallTimeMs, this.maxOracleNodes});

  final int? maxTicks;
  final int? maxWallTimeMs;
  final int? maxOracleNodes;

  @override
  List<Object?> get props => [maxTicks, maxWallTimeMs, maxOracleNodes];
}

/// A commitment to a strategy for a bounded horizon.
@immutable
class MetaPhase extends Equatable {
  const MetaPhase({
    required this.id,
    required this.targets,
    required this.activeProjects,
    required this.policy,
    this.budget,
    this.explain,
  });

  factory MetaPhase.fromJson(Map<String, dynamic> json) {
    final targetsJson = json['targets'] as Map<String, dynamic>;
    final hardTargetsJson = targetsJson['hardTargets'] as List<dynamic>;
    final softTargetsJson = targetsJson['softTargets'] as List<dynamic>? ?? [];

    final projectsJson = json['activeProjects'] as List<dynamic>;

    return MetaPhase(
      id: json['id'] as String,
      targets: PhaseTargets(
        hardTargets: hardTargetsJson
            .map((m) => Milestone.fromJson(m as Map<String, dynamic>))
            .toList(),
        softTargets: softTargetsJson
            .map((m) => Milestone.fromJson(m as Map<String, dynamic>))
            .toList(),
      ),
      activeProjects: projectsJson
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList(),
      policy: SchedulingPolicy.fromJson(json['policy'] as Map<String, dynamic>),
      explain: json['explain'] as String?,
    );
  }

  /// Unique identifier for this phase.
  final String id;

  /// Target milestones for this phase.
  final PhaseTargets targets;

  /// Projects allowed to make progress in this phase.
  final List<Project> activeProjects;

  /// Scheduling policy for this phase.
  final SchedulingPolicy policy;

  /// Optional budget limits.
  final PhaseBudget? budget;

  /// Explanation of why this phase was chosen (for debugging).
  final String? explain;

  Map<String, dynamic> toJson() => {
    'id': id,
    'targets': {
      'hardTargets': targets.hardTargets.map((m) => m.toJson()).toList(),
      'softTargets': targets.softTargets.map((m) => m.toJson()).toList(),
    },
    'activeProjects': activeProjects.map((p) => p.toJson()).toList(),
    'policy': policy.toJson(),
    if (explain != null) 'explain': explain,
  };

  @override
  List<Object?> get props => [id, targets, activeProjects, policy, explain];
}
