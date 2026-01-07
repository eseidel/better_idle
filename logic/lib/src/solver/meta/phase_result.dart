/// Phase result contract for Level 3 meta planning.
///
/// [PhaseResult] is the critical interface between Level 2 (A* solver) and
/// Level 3 (meta planner). It provides all the information Level 3 needs to
/// make informed decisions about phase selection and scoring.
///
/// ## Design Notes
///
/// Without this contract, Level 3 would be blind and fall back to hardcoded
/// heuristics based only on ticks. The structured result enables:
/// - Understanding WHY a segment ended (boundary type)
/// - Tracking progress per skill (not just total)
/// - Detecting problematic events (inventory pressure, deaths)
/// - Measuring solver efficiency (nodes, time)
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Result of evaluating a phase via Level 2 oracle.
///
/// Contains everything Level 3 needs to score and compare phase candidates.
@immutable
class PhaseResult extends Equatable {
  const PhaseResult({
    required this.plan,
    required this.initialState,
    required this.terminalState,
    required this.ticksElapsed,
    required this.endBoundary,
    required this.skillDeltas,
    required this.milestonesSatisfied,
    required this.events,
    required this.solverStats,
  });

  /// The Level 2 plan segment produced.
  final Plan plan;

  /// State before executing the plan.
  final GlobalState initialState;

  /// State after executing the plan (from A* projection).
  final GlobalState terminalState;

  /// Total ticks elapsed in the plan.
  final int ticksElapsed;

  /// Why the segment ended (typed boundary).
  final SegmentBoundary? endBoundary;

  /// Progress per skill during this phase.
  final Map<Skill, SkillDelta> skillDeltas;

  /// Milestone IDs that were satisfied by this phase.
  final List<String> milestonesSatisfied;

  /// Events that occurred during the phase.
  final List<PhaseEvent> events;

  /// Solver performance statistics.
  final SolverStats solverStats;

  /// Compute skill deltas from initial and terminal states.
  static Map<Skill, SkillDelta> computeSkillDeltas(
    GlobalState initial,
    GlobalState terminal,
  ) {
    final deltas = <Skill, SkillDelta>{};

    for (final skill in Skill.values) {
      final initialState = initial.skillState(skill);
      final terminalState = terminal.skillState(skill);

      final xpGained = terminalState.xp - initialState.xp;
      final levelsGained = terminalState.skillLevel - initialState.skillLevel;

      if (xpGained > 0 || levelsGained > 0) {
        deltas[skill] = SkillDelta(
          skill: skill,
          initialLevel: initialState.skillLevel,
          terminalLevel: terminalState.skillLevel,
          xpGained: xpGained,
        );
      }
    }

    return deltas;
  }

  /// Get the minimum skill level across a set of skills in terminal state.
  int minLevelIn(Set<Skill> skills) {
    if (skills.isEmpty) return 0;
    return skills
        .map((s) => terminalState.skillState(s).skillLevel)
        .reduce((a, b) => a < b ? a : b);
  }

  /// Check if any skill leveled up during this phase.
  bool get hadLevelUp {
    return skillDeltas.values.any((d) => d.levelsGained > 0);
  }

  /// Total XP gained across all skills.
  int get totalXpGained {
    return skillDeltas.values.fold(0, (sum, d) => sum + d.xpGained);
  }

  /// Count of specific event types.
  int countEvents(PhaseEventType type) {
    return events.where((e) => e.type == type).length;
  }

  @override
  List<Object?> get props => [
    plan,
    ticksElapsed,
    endBoundary,
    skillDeltas,
    milestonesSatisfied,
    events,
    solverStats,
  ];
}

/// Progress in a single skill during a phase.
@immutable
class SkillDelta extends Equatable {
  const SkillDelta({
    required this.skill,
    required this.initialLevel,
    required this.terminalLevel,
    required this.xpGained,
  });

  final Skill skill;
  final int initialLevel;
  final int terminalLevel;
  final int xpGained;

  int get levelsGained => terminalLevel - initialLevel;

  @override
  List<Object?> get props => [skill, initialLevel, terminalLevel, xpGained];
}

/// Events that occurred during phase execution.
///
/// Used for scoring penalties and understanding phase behavior.
@immutable
class PhaseEvent extends Equatable {
  const PhaseEvent({required this.type, this.details});

  final PhaseEventType type;
  final String? details;

  @override
  List<Object?> get props => [type, details];
}

/// Types of events that can occur during a phase.
enum PhaseEventType {
  /// Player died (e.g., during thieving)
  death,

  /// Inventory hit pressure threshold
  inventoryPressure,

  /// Items were sold
  sold,

  /// Inputs were depleted for consuming action
  inputsDepleted,

  /// An upgrade was purchased
  upgradePurchased,

  /// A new action was unlocked
  actionUnlocked,

  /// Project was switched mid-phase
  projectSwitch,
}

/// Solver performance statistics.
@immutable
class SolverStats extends Equatable {
  const SolverStats({
    required this.nodesExpanded,
    required this.wallTimeMs,
    this.nodesEnqueued,
    this.queuePeakSize,
  });

  /// Number of A* nodes expanded.
  final int nodesExpanded;

  /// Wall-clock time spent solving (milliseconds).
  final int wallTimeMs;

  /// Number of nodes added to queue (optional).
  final int? nodesEnqueued;

  /// Peak queue size (optional).
  final int? queuePeakSize;

  /// Nodes expanded per millisecond.
  double get nodesPerMs {
    if (wallTimeMs == 0) return 0;
    return nodesExpanded / wallTimeMs;
  }

  @override
  List<Object?> get props => [
    nodesExpanded,
    wallTimeMs,
    nodesEnqueued,
    queuePeakSize,
  ];
}
