/// Macro-level planning primitives for solver.
///
/// Macros represent "train until boundary/goal/upgrade" decisions that span
/// many ticks, reducing the solver's branching factor and state explosion.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/interaction.dart'
    show SellAllPolicy, SellPolicySpec;
import 'package:logic/src/solver/unlock_boundaries.dart';
import 'package:logic/src/solver/wait_for.dart';
import 'package:logic/src/state.dart';

// ---------------------------------------------------------------------------
// Provenance - tracks WHY a macro was created
// ---------------------------------------------------------------------------

/// Tracks the origin of a macro for debugging and explanation.
///
/// When macros are generated as prerequisites or batch inputs, provenance
/// tells us why they were created, enabling better debugging and the
/// "explain one expansion" feature.
sealed class MacroProvenance {
  const MacroProvenance();

  /// Human-readable description of why this macro was created.
  String describe();
}

/// Macro generated directly by candidate enumeration (top-level).
class TopLevelProvenance extends MacroProvenance {
  const TopLevelProvenance();

  @override
  String describe() => 'Top-level candidate';
}

/// Macro generated as a skill level prerequisite.
///
/// Example: "Need Mining L15 to unlock Mithril Ore for Smithing"
class SkillPrereqProvenance extends MacroProvenance {
  const SkillPrereqProvenance({
    required this.requiredSkill,
    required this.requiredLevel,
    required this.unlocksAction,
  });

  final Skill requiredSkill;
  final int requiredLevel;
  final ActionId unlocksAction;

  @override
  String describe() =>
      'Prereq: ${requiredSkill.name} L$requiredLevel unlocks $unlocksAction';
}

/// Macro generated to acquire inputs for a consuming action.
///
/// Example: "Need 50 Bronze Bars for Smithing Bronze Daggers"
class InputPrereqProvenance extends MacroProvenance {
  const InputPrereqProvenance({
    required this.forAction,
    required this.inputItem,
    required this.quantityNeeded,
  });

  final ActionId forAction;
  final MelvorId inputItem;
  final int quantityNeeded;

  @override
  String describe() =>
      'Input: ${quantityNeeded}x ${inputItem.localId} for $forAction';
}

/// Macro generated as a batched input for a craft-until-unlock phase.
///
/// Example: "Batch: 120 Copper Ore for 40 Bronze Bars to reach Smithing L10"
class BatchInputProvenance extends MacroProvenance {
  const BatchInputProvenance({
    required this.forItem,
    required this.batchSize,
    required this.targetLevel,
  });

  final MelvorId forItem;
  final int batchSize;
  final int targetLevel;

  @override
  String describe() =>
      'Batch: ${batchSize}x ${forItem.localId} for L$targetLevel unlock';
}

/// Macro generated as part of a multi-tier production chain.
///
/// Example: "Chain: Bronze Bar -> Bronze Dagger, need ores first"
class ChainProvenance extends MacroProvenance {
  const ChainProvenance({required this.parentItem, required this.childItem});

  final MelvorId parentItem;
  final MelvorId childItem;

  @override
  String describe() =>
      'Chain: ${childItem.localId} needed for ${parentItem.localId}';
}

// ---------------------------------------------------------------------------
// Macro Candidates
// ---------------------------------------------------------------------------

/// A macro-level planning action that commits to an activity for an
/// extended period.
///
/// Macros stop when ANY of their stop conditions trigger, allowing the solver
/// to react to unlock boundaries, goal completion, or upgrade affordability.
sealed class MacroCandidate {
  const MacroCandidate({this.provenance});

  /// Why this macro was created (for debugging/explanation).
  final MacroProvenance? provenance;
}

/// Train a skill by doing its best action until ANY stop condition triggers.
///
/// Example: "Train Woodcutting until (next boundary OR Steel Axe affordable)"
class TrainSkillUntil extends MacroCandidate {
  const TrainSkillUntil(
    this.skill,
    this.primaryStop, {
    this.watchedStops = const [],
    this.actionId,
    super.provenance,
  });

  final Skill skill;

  /// The specific action to use for training. If null, the best action will
  /// be computed at execution time (but this may cause inconsistency with
  /// subsequent WaitSteps that expect a specific action's mastery).
  final ActionId? actionId;

  /// Primary stop condition (usually boundary or goal).
  final MacroStopRule primaryStop;

  /// Additional stop conditions to watch (upgrades, inputs, etc.).
  /// Macro stops when ANY condition (primary OR watched) triggers.
  final List<MacroStopRule> watchedStops;

  /// All stop conditions (primary + watched).
  List<MacroStopRule> get allStops => [primaryStop, ...watchedStops];
}

/// Acquire items by producing them (and their prerequisites).
///
/// This macro:
/// 1. Finds the action that produces itemId
/// 2. Ensures prerequisites are met (skill levels, input items)
/// 3. Executes the producing action until quantity reached
///
/// Used for:
/// - Gathering inputs for consuming skills (ores for smithing)
/// - Multi-tier chains (bars need ores, which need mining skill)
class AcquireItem extends MacroCandidate {
  const AcquireItem(this.itemId, this.quantity, {super.provenance});

  /// The item to acquire.
  final MelvorId itemId;

  /// How many to acquire.
  final int quantity;
}

/// Ensure inventory has at least [minTotal] of an item (absolute semantics).
///
/// Unlike [AcquireItem] which adds a delta quantity, EnsureStock targets an
/// absolute inventory count. This is useful for batch planning where we know
/// the exact total inputs needed for a craft phase.
///
/// If inventory already has >= minTotal, this is a no-op (returns
/// `MacroAlreadySatisfied` from expansion).
///
/// Used for:
/// - Batch acquisition of inputs for consuming skills
/// - Ensuring all raw materials before a craft-until-unlock phase
class EnsureStock extends MacroCandidate {
  const EnsureStock(this.itemId, this.minTotal, {super.provenance});

  /// The item to ensure stock of.
  final MelvorId itemId;

  /// The minimum total count required in inventory.
  final int minTotal;
}

/// Train a consuming skill via coupled produce/consume loops.
///
/// For consuming skills (Firemaking, Cooking, Smithing), this macro alternates:
/// 1. Produce inputs (e.g., cut logs, catch fish) until buffer threshold
/// 2. Consume inputs (e.g., burn logs, cook fish) until depleted
/// 3. Repeat until stop condition
///
/// This models the sustainable rate:
///   consumingXP/tick = (consumeRate * produceTime) / (produceTime + consumeTime)
///
/// ## New contract (plan-authorized execution)
///
/// The planner sets these fields to fully specify execution behavior:
/// - [consumeActionId]: the fixed consuming action (no runtime search)
/// - [producerByInputItem]: immediate producers for each consume input
/// - [bufferTarget]: quantized batch size chosen by solver
/// - [sellPolicySpec]: how to handle inventory pressure during execution
/// - [maxRecoveryAttempts]: guardrail for recovery loops
///
/// The executor adapts to randomness only by:
/// - Running until WaitFor triggers
/// - Performing explicitly authorized recovery actions (sell/bank/heal)
/// - Triggering a bounded replan using the same solver
class TrainConsumingSkillUntil extends MacroCandidate {
  const TrainConsumingSkillUntil(
    this.consumingSkill,
    this.primaryStop, {
    this.watchedStops = const [],
    this.actionId,
    this.consumeActionId,
    this.producerByInputItem,
    this.bufferTarget,
    this.sellPolicySpec,
    this.maxRecoveryAttempts = 3,
    super.provenance,
  });

  final Skill consumingSkill;

  /// The specific consuming action to use. If null, the best action will be
  /// computed at execution time (but this may cause inconsistency if
  /// different actions become optimal mid-execution due to level-ups).
  ///
  /// @deprecated Use [consumeActionId] instead. This field exists for backward
  /// compatibility during the transition period.
  final ActionId? actionId;

  /// The fixed consuming action ID chosen during planning.
  ///
  /// When set, the executor uses this action without any runtime best-action
  /// search. This ensures deterministic execution and prevents strategy drift.
  ///
  /// If null, falls back to legacy behavior using [actionId] or runtime search.
  final ActionId? consumeActionId;

  /// Maps each input item to its immediate producer action.
  ///
  /// Example for Bronze Bar:
  /// ```dart
  /// {
  ///   MelvorId('melvorD:Copper_Ore'): ActionId(Skill.mining, 'Copper_Rocks'),
  ///   MelvorId('melvorD:Tin_Ore'): ActionId(Skill.mining, 'Tin_Rocks'),
  /// }
  /// ```
  ///
  /// The executor switches to these producers in order when inputs are needed.
  /// If null, falls back to legacy behavior (runtime producer lookup).
  final Map<MelvorId, ActionId>? producerByInputItem;

  /// The buffer threshold chosen by the solver during planning.
  ///
  /// During the produce phase, the executor gathers inputs until each reaches
  /// this count before switching to the consume phase.
  ///
  /// If null, falls back to legacy hardcoded value (10).
  final int? bufferTarget;

  /// The sell policy specification for handling inventory pressure.
  ///
  /// When inventory fills during execution, the executor uses this policy
  /// to determine which items to sell. This removes guesswork from the
  /// executor - the planner has already decided the sell strategy.
  ///
  /// If null, executor must get the policy from segment context or fail.
  final SellPolicySpec? sellPolicySpec;

  /// Maximum recovery attempts before triggering a replan.
  ///
  /// Guards against infinite recovery loops. If recovery fails this many
  /// times without meaningful progress, the executor triggers a replan.
  ///
  /// Default: 3
  final int maxRecoveryAttempts;

  /// Primary stop condition (usually boundary or goal).
  final MacroStopRule primaryStop;

  /// Additional stop conditions to watch (upgrades, etc.).
  final List<MacroStopRule> watchedStops;

  /// All stop conditions (primary + watched).
  List<MacroStopRule> get allStops => [primaryStop, ...watchedStops];

  /// Creates a copy with updated fields.
  ///
  /// Used by the solver to fill in execution details after initial creation.
  TrainConsumingSkillUntil copyWith({
    ActionId? consumeActionId,
    Map<MelvorId, ActionId>? producerByInputItem,
    int? bufferTarget,
    SellPolicySpec? sellPolicySpec,
    int? maxRecoveryAttempts,
    List<MacroStopRule>? watchedStops,
  }) {
    return TrainConsumingSkillUntil(
      consumingSkill,
      primaryStop,
      watchedStops: watchedStops ?? this.watchedStops,
      actionId: actionId,
      consumeActionId: consumeActionId ?? this.consumeActionId,
      producerByInputItem: producerByInputItem ?? this.producerByInputItem,
      bufferTarget: bufferTarget ?? this.bufferTarget,
      sellPolicySpec: sellPolicySpec ?? this.sellPolicySpec,
      maxRecoveryAttempts: maxRecoveryAttempts ?? this.maxRecoveryAttempts,
      provenance: provenance,
    );
  }
}

/// Stop conditions for macro training.
///
/// Each rule knows how to convert itself to a WaitFor for plan execution.
sealed class MacroStopRule {
  const MacroStopRule();

  /// Convert this stop rule to a WaitFor for plan execution.
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries);
}

/// Stop at the next unlock boundary for this skill.
///
/// Boundaries are levels where new actions become available.
class StopAtNextBoundary extends MacroStopRule {
  const StopAtNextBoundary(this.skill);

  final Skill skill;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    final currentLevel = state.skillState(skill).skillLevel;
    final nextBoundary = boundaries[skill]?.nextBoundary(currentLevel);
    final targetLevel = nextBoundary ?? 99;
    final targetXp = startXpForLevel(targetLevel);

    return WaitForSkillXp(skill, targetXp, reason: 'Boundary L$targetLevel');
  }
}

/// Stop when skill reaches goal level.
class StopAtGoal extends MacroStopRule {
  const StopAtGoal(this.skill, this.targetXp);

  final Skill skill;
  final int targetXp;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    return WaitForSkillXp(skill, targetXp, reason: 'Goal reached');
  }
}

/// Stop when skill reaches a specific level.
///
/// Used for prerequisite training (e.g., "train Mining to 50" to unlock
/// Mithril Ore before smithing Mithril Bars).
class StopAtLevel extends MacroStopRule {
  const StopAtLevel(this.skill, this.level);

  final Skill skill;
  final int level;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    return WaitForSkillXp(
      skill,
      startXpForLevel(level),
      reason: 'Unlock L$level',
    );
  }
}

/// Stop when upgrade becomes affordable.
///
/// Used to allow early purchase of valuable upgrades before reaching
/// the next boundary.
class StopWhenUpgradeAffordable extends MacroStopRule {
  const StopWhenUpgradeAffordable(this.purchaseId, this.cost, this.upgradeName);

  final MelvorId purchaseId;
  final int cost;
  final String upgradeName;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    // Use SellAllPolicy as a conservative default - upgrade affordability
    // is typically checked with full liquidation potential.
    return WaitForEffectiveCredits(
      cost,
      sellPolicy: const SellAllPolicy(),
      reason: upgradeName,
    );
  }
}

/// Stop when inputs are depleted (for consuming actions like Firemaking).
///
/// This ensures the macro doesn't continue when there are no logs/fish to
/// consume, allowing the solver to switch to a producer action.
///
/// Note: This uses the active action from the state at toWaitFor() time,
/// not a fixed action ID, to handle cases where the best action changes
/// (e.g., Normal Logs -> Oak Logs as Firemaking level increases).
class StopWhenInputsDepleted extends MacroStopRule {
  const StopWhenInputsDepleted();

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    // Use the currently active action, which may have changed since planning
    final activeActionId = state.activeAction?.id;
    if (activeActionId == null) {
      // No active action - this should never happen during macro execution
      // but return a no-op condition as fallback
      throw StateError('StopWhenInputsDepleted called with no active action');
    }
    return WaitForInputsDepleted(activeActionId);
  }
}
