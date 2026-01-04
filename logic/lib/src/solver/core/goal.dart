/// Goal abstraction: defines what the solver is trying to achieve.
///
/// ## Purpose
///
/// [Goal] is the target for the planner. It defines:
/// - Whether the goal is satisfied for a given state
/// - How much progress remains (in goal-specific units)
/// - How to describe the goal for logging
///
/// ## Implementations
///
/// - [ReachGpGoal]: Reach a target amount of GP (gold pieces)
/// - [ReachSkillLevelGoal]: Reach a target level in a specific skill
///
/// ## Design Notes
///
/// The goal abstraction separates "what we're trying to achieve" from
/// "how we value intermediate progress". The [ValueModel] handles the latter.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/watch_set.dart';
import 'package:logic/src/solver/core/value_model.dart' show ValueModel;
import 'package:logic/src/solver/interactions/interaction.dart'
    show
        ReserveConsumingInputsSpec,
        SellAllPolicy,
        SellPolicy,
        effectiveCredits;
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Abstract base class for solver goals.
@immutable
sealed class Goal extends Equatable {
  const Goal();

  /// Returns true if the goal is satisfied in the given state.
  bool isSatisfied(GlobalState state);

  /// Returns the remaining progress needed to reach the goal.
  /// Units are goal-specific (GP for ReachGpGoal, XP for ReachSkillLevelGoal).
  double remaining(GlobalState state);

  /// Returns a human-readable description of the goal.
  String describe();

  /// Returns the progress rate toward the goal given current rates.
  /// For GP goals, this uses the value model.
  /// For skill goals, this uses the XP rate directly.
  double progressPerTick(GlobalState state, Rates rates);

  /// Returns the current progress value for dominance pruning.
  /// For GP goals: effective credits (GP + inventory value).
  /// For skill goals: current XP in the target skill.
  int progress(GlobalState state);

  /// Whether selling items is relevant for this goal.
  /// For GP goals, selling converts items to GP progress.
  /// For skill goals, selling doesn't contribute to XP.
  bool get isSellRelevant;

  /// Returns true if this skill is relevant to making progress toward the goal.
  /// Used to filter activities, upgrades, and locked activity watches.
  bool isSkillRelevant(Skill skill);

  /// Returns the rate value to use when ranking an activity for this goal.
  /// For GP goals, returns gold rate. For skill goals, returns XP rate
  /// (or 0 if the activity's skill doesn't contribute to the goal).
  double activityRate(Skill skill, double goldRate, double xpRate);

  /// Returns the set of skills that should be tracked in bucket keys for
  /// dominance pruning. For skill goals, only tracks goal-relevant skills.
  /// For GP goals, tracks all skills.
  Set<Skill> get relevantSkillsForBucketing;

  /// Whether to track HP in the bucket key (only for thieving goals).
  bool get shouldTrackHp;

  /// Whether to track mastery in the bucket key (only for thieving goals).
  bool get shouldTrackMastery;

  /// Whether to track inventory bucket in the bucket key
  /// (only for consuming skill goals).
  bool get shouldTrackInventory;

  /// Returns the set of consuming skills that are part of this goal.
  /// Used to unconditionally include producer activities for these skills.
  Set<Skill> get consumingSkills;

  /// Computes the sell policy for this goal.
  ///
  /// This is a POLICY decision, not a heuristic. The sell policy determines
  /// which items to keep vs sell based on what the goal needs:
  /// - GP goals: sell everything (all items contribute to GP)
  /// - Skill goals: keep items that are inputs for consuming skills
  ///
  /// The [state] is used to determine which actions are unlocked and what
  /// inputs they require.
  SellPolicy computeSellPolicy(GlobalState state);

  /// Serializes this [Goal] to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes a [Goal] from a JSON-compatible map.
  ///
  /// Note: [SegmentGoal] cannot be fully deserialized because it requires a
  /// [WatchSet] which contains state-dependent information. If you need to
  /// restore a SegmentGoal, use the innerGoal and recreate the WatchSet.
  static Goal fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'ReachGpGoal' => ReachGpGoal(json['targetGp'] as int),
      'ReachSkillLevelGoal' => ReachSkillLevelGoal(
        Skill.fromName(json['skill'] as String),
        json['targetLevel'] as int,
      ),
      'MultiSkillGoal' => MultiSkillGoal(
        (json['subgoals'] as List<dynamic>)
            .map((e) => Goal.fromJson(e as Map<String, dynamic>))
            .cast<ReachSkillLevelGoal>()
            .toList(),
      ),
      'SegmentGoal' => throw ArgumentError(
        'SegmentGoal cannot be deserialized - use the innerGoal and recreate '
        'the WatchSet from state',
      ),
      _ => throw ArgumentError('Unknown Goal type: $type'),
    };
  }
}

/// Goal to reach a target amount of GP (gold pieces).
///
/// "Effective credits" includes both GP and the sell value of inventory items.
/// For GP goals, all items count toward progress (uses [SellAllPolicy]).
@immutable
class ReachGpGoal extends Goal {
  const ReachGpGoal(this.targetGp);

  final int targetGp;

  /// The sell policy for GP goals: sell everything.
  static const _policy = SellAllPolicy();

  @override
  bool isSatisfied(GlobalState state) {
    return effectiveCredits(state, _policy) >= targetGp;
  }

  @override
  double remaining(GlobalState state) {
    final current = effectiveCredits(state, _policy);
    return (targetGp - current).clamp(0, double.infinity).toDouble();
  }

  @override
  String describe() => 'Reach $targetGp GP';

  @override
  double progressPerTick(GlobalState state, Rates rates) {
    // For GP goals, progress = direct GP + value of items produced
    var value = rates.directGpPerTick;
    for (final entry in rates.itemFlowsPerTick.entries) {
      final item = state.registries.items.byId(entry.key);
      value += entry.value * item.sellsFor;
    }
    return value;
  }

  @override
  int progress(GlobalState state) => effectiveCredits(state, _policy);

  @override
  bool get isSellRelevant => true;

  @override
  bool isSkillRelevant(Skill skill) => true; // All skills can generate GP

  @override
  double activityRate(Skill skill, double goldRate, double xpRate) => goldRate;

  @override
  Set<Skill> get relevantSkillsForBucketing => Skill.values.toSet();

  @override
  bool get shouldTrackHp => true; // Track HP for thieving

  @override
  bool get shouldTrackMastery => true; // Track mastery for all skills

  @override
  bool get shouldTrackInventory => true; // Track inventory for all skills

  @override
  Set<Skill> get consumingSkills => Skill.consumingSkills;

  @override
  SellPolicy computeSellPolicy(GlobalState state) {
    // GP goals sell everything - all items contribute to GP
    return const SellAllPolicy();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ReachGpGoal',
    'targetGp': targetGp,
  };

  @override
  List<Object?> get props => [targetGp];
}

/// Goal to reach a target level in a specific skill.
@immutable
class ReachSkillLevelGoal extends Goal {
  const ReachSkillLevelGoal(this.skill, this.targetLevel);

  final Skill skill;
  final int targetLevel;

  /// Returns the XP required to reach the target level.
  int get targetXp => startXpForLevel(targetLevel);

  @override
  bool isSatisfied(GlobalState state) {
    return state.skillState(skill).skillLevel >= targetLevel;
  }

  @override
  double remaining(GlobalState state) {
    final currentXp = state.skillState(skill).xp;
    return (targetXp - currentXp).clamp(0, double.infinity).toDouble();
  }

  @override
  String describe() => 'Reach ${skill.name} level $targetLevel';

  @override
  double progressPerTick(GlobalState state, Rates rates) {
    // For skill goals, progress = XP per tick for the target skill
    return rates.xpPerTickBySkill[skill] ?? 0.0;
  }

  @override
  int progress(GlobalState state) => state.skillState(skill).xp;

  @override
  bool get isSellRelevant => false;

  @override
  bool isSkillRelevant(Skill s) => s == skill;

  @override
  double activityRate(Skill s, double goldRate, double xpRate) =>
      s == skill ? xpRate : 0.0;

  @override
  Set<Skill> get relevantSkillsForBucketing => {skill};

  @override
  bool get shouldTrackHp => skill == Skill.thieving;

  @override
  bool get shouldTrackMastery => skill == Skill.thieving;

  @override
  bool get shouldTrackInventory => skill.isConsuming;

  @override
  Set<Skill> get consumingSkills => skill.isConsuming ? {skill} : {};

  @override
  SellPolicy computeSellPolicy(GlobalState state) {
    // Delegate to the spec for consistent policy computation.
    // ReserveConsumingInputsSpec handles the keepItems logic.
    return const ReserveConsumingInputsSpec().instantiate(
      state,
      consumingSkills,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ReachSkillLevelGoal',
    'skill': skill.name,
    'targetLevel': targetLevel,
  };

  @override
  List<Object?> get props => [skill, targetLevel];
}

/// Goal to reach target levels in multiple skills (AND semantics).
///
/// All subgoals must be satisfied for the goal to be complete.
/// Progress is measured as the sum of remaining XP across all unfinished
/// skills.
@immutable
class MultiSkillGoal extends Goal {
  const MultiSkillGoal(this.subgoals);

  /// Convenience constructor from a map of skill -> target level.
  factory MultiSkillGoal.fromMap(Map<Skill, int> skillLevels) {
    final subgoals = skillLevels.entries
        .map((e) => ReachSkillLevelGoal(e.key, e.value))
        .toList();
    return MultiSkillGoal(subgoals);
  }

  /// Individual skill-level targets.
  final List<ReachSkillLevelGoal> subgoals;

  @override
  bool isSatisfied(GlobalState state) {
    return subgoals.every((g) => g.isSatisfied(state));
  }

  @override
  double remaining(GlobalState state) {
    // Sum of XP remaining across all unfinished skills
    return subgoals
        .where((g) => !g.isSatisfied(state))
        .map((g) => g.remaining(state))
        .fold(0, (a, b) => a + b);
  }

  @override
  String describe() {
    final parts = subgoals.map((g) => '${g.skill.name} ${g.targetLevel}');
    return 'Reach ${parts.join(', ')}';
  }

  @override
  double progressPerTick(GlobalState state, Rates rates) {
    // Sum of XP/tick for all unfinished skills
    var total = 0.0;
    for (final subgoal in subgoals) {
      if (subgoal.isSatisfied(state)) continue;
      final xpRate = rates.xpPerTickBySkill[subgoal.skill] ?? 0.0;
      total += xpRate;
    }
    return total;
  }

  @override
  int progress(GlobalState state) {
    // Sum of XP across all target skills (for dominance comparison)
    return subgoals.fold(0, (sum, g) => sum + state.skillState(g.skill).xp);
  }

  @override
  bool get isSellRelevant => false; // Skill goals don't benefit from selling

  @override
  bool isSkillRelevant(Skill skill) {
    // Any skill in our subgoals is relevant
    return subgoals.any((g) => g.skill == skill);
  }

  @override
  double activityRate(Skill skill, double goldRate, double xpRate) {
    // Return XP rate if this skill is in our goal set
    return isSkillRelevant(skill) ? xpRate : 0.0;
  }

  @override
  Set<Skill> get relevantSkillsForBucketing =>
      subgoals.map((g) => g.skill).toSet();

  @override
  bool get shouldTrackHp => subgoals.any((g) => g.shouldTrackHp);

  @override
  bool get shouldTrackMastery => subgoals.any((g) => g.shouldTrackMastery);

  @override
  bool get shouldTrackInventory => subgoals.any((g) => g.shouldTrackInventory);

  @override
  Set<Skill> get consumingSkills =>
      subgoals.expand((g) => g.consumingSkills).toSet();

  @override
  SellPolicy computeSellPolicy(GlobalState state) {
    // Delegate to the spec for consistent policy computation.
    // ReserveConsumingInputsSpec handles the keepItems logic.
    return const ReserveConsumingInputsSpec().instantiate(
      state,
      consumingSkills,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'MultiSkillGoal',
    'subgoals': subgoals.map((g) => g.toJson()).toList(),
  };

  @override
  List<Object?> get props => [subgoals];
}

/// A goal wrapper that stops at material boundaries.
///
/// This class delegates to a [WatchSet] for boundary detection.
/// When [isSatisfied] returns true, it means a material boundary was crossed
/// (goal reached, upgrade affordable, unlock boundary, etc.).
///
/// All other Goal methods delegate to the inner goal from the WatchSet.
@immutable
class SegmentGoal extends Goal {
  const SegmentGoal(this.watchSet);

  /// The WatchSet that defines what boundaries are material.
  final WatchSet watchSet;

  /// Convenience accessor for the inner goal.
  Goal get innerGoal => watchSet.goal;

  @override
  bool isSatisfied(GlobalState state) {
    // Delegate to watchSet - the SINGLE source of truth
    final boundary = watchSet.detectBoundary(state);
    return boundary != null;
  }

  @override
  double remaining(GlobalState state) => innerGoal.remaining(state);

  @override
  String describe() => 'Segment(${innerGoal.describe()})';

  @override
  double progressPerTick(GlobalState state, Rates rates) =>
      innerGoal.progressPerTick(state, rates);

  @override
  int progress(GlobalState state) => innerGoal.progress(state);

  @override
  bool get isSellRelevant => innerGoal.isSellRelevant;

  @override
  bool isSkillRelevant(Skill skill) => innerGoal.isSkillRelevant(skill);

  @override
  double activityRate(Skill skill, double goldRate, double xpRate) =>
      innerGoal.activityRate(skill, goldRate, xpRate);

  @override
  Set<Skill> get relevantSkillsForBucketing =>
      innerGoal.relevantSkillsForBucketing;

  @override
  bool get shouldTrackHp => innerGoal.shouldTrackHp;

  @override
  bool get shouldTrackMastery => innerGoal.shouldTrackMastery;

  @override
  bool get shouldTrackInventory => innerGoal.shouldTrackInventory;

  @override
  Set<Skill> get consumingSkills => innerGoal.consumingSkills;

  @override
  SellPolicy computeSellPolicy(GlobalState state) =>
      innerGoal.computeSellPolicy(state);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'SegmentGoal',
    'innerGoal': innerGoal.toJson(),
  };

  @override
  List<Object?> get props => [watchSet];
}
