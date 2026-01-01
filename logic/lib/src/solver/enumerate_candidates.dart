/// Candidate enumeration: builds a "cheap frontier" for the solver.
///
/// ## Two Distinct Outputs
///
/// * **Branch candidates** ([Candidates.switchToActivities],
///   [Candidates.buyUpgrades], [Candidates.sellPolicy]):
///   actions we're willing to consider now.
/// * **Watch candidates** ([WatchList]): events that define "interesting times"
///   for waiting (affordability, unlocks, inventory).
///
/// ## Key Invariant: Watch ≠ Action
///
/// [Candidates.buyUpgrades] must contain only upgrades that are **actionable
/// and competitive** under the current policy:
/// - Apply to current activity or top candidate activities
/// - Positive gain under ValueModel
/// - Pass heuristics / top-K filters
///
/// [WatchList.upgradePurchaseIds] may include a broader set to compute
/// time-to-afford / future replan moments.
///
/// **Never promote watch-only upgrades into buyUpgrades just because they are
/// affordable.** Example: we may watch FishingRod affordability, but we don't
/// branch on buying it while thieving unless it improves value for a candidate
/// activity.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/solver/unlock_boundaries.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:meta/meta.dart';

/// Default constants for candidate selection.
const int defaultActivityCandidateCount = 8; // K
const int defaultUpgradeCandidateCount = 8; // M
const int defaultLockedWatchCount = 3; // L
const double defaultInventoryThreshold = 0.8;

/// Summary of an action's expected rates for the planner.
@immutable
class ActionSummary {
  const ActionSummary({
    required this.actionId,
    required this.skill,
    required this.unlockLevel,
    required this.isUnlocked,
    required this.expectedTicks,
    required this.goldRatePerTick,
    required this.xpRatePerTick,
    this.hasInputs = false,
    this.canStartNow = true,
    this.missingInputs = const {},
  });

  final ActionId actionId;
  final Skill skill;
  final int unlockLevel;
  final bool isUnlocked;

  /// Expected ticks per action completion.
  final double expectedTicks;

  /// Expected gold per tick from selling outputs.
  final double goldRatePerTick;

  /// Expected skill XP per tick.
  final double xpRatePerTick;

  /// Whether this action requires inputs (firemaking, cooking, etc).
  final bool hasInputs;

  /// Whether the action can start now (has required inputs available).
  /// Always true for actions without inputs.
  final bool canStartNow;

  /// Items needed but not available in inventory.
  /// Maps item ID to quantity still needed.
  final Map<MelvorId, int> missingInputs;
}

// ---------------------------------------------------------------------------
// Capability-level rate cache
// ---------------------------------------------------------------------------

/// Summary of an action's rates for ranking (capability-level, cacheable).
///
/// Unlike [ActionSummary], this does NOT include state-dependent fields like
/// [ActionSummary.canStartNow] or [ActionSummary.missingInputs]. Those are
/// evaluated per-state, not cached.
@immutable
class ActionRateSummary {
  const ActionRateSummary({
    required this.actionId,
    required this.skill,
    required this.unlockLevel,
    required this.isUnlocked,
    required this.expectedTicks,
    required this.goldRatePerTick,
    required this.xpRatePerTick,
    required this.hasInputs,
  });

  final ActionId actionId;
  final Skill skill;
  final int unlockLevel;
  final bool isUnlocked;

  /// Expected ticks per action completion.
  final double expectedTicks;

  /// Expected gold per tick from selling outputs.
  final double goldRatePerTick;

  /// Expected skill XP per tick.
  final double xpRatePerTick;

  /// Whether this action requires inputs (firemaking, cooking, etc).
  /// This is structural (capability), not inventory-dependent.
  final bool hasInputs;
}

/// Packed capability key for rate cache.
/// Uses two ints to support up to 15+ skills without rework.
@immutable
class _PackedCapabilityKey {
  const _PackedCapabilityKey(this._low, this._high);

  final int _low;
  final int _high;

  @override
  int get hashCode => Object.hash(_low, _high);

  @override
  bool operator ==(Object other) =>
      other is _PackedCapabilityKey &&
      _low == other._low &&
      _high == other._high;
}

/// Module-private rate cache. Cleared between solver runs.
final Map<_PackedCapabilityKey, List<ActionRateSummary>> _rateCache = {};

/// Cache statistics for profiling.
int _rateCacheHits = 0;
int _rateCacheMisses = 0;

/// Clears the rate cache. Call at start of each solve().
void clearRateCache() {
  _rateCache.clear();
  _rateCacheHits = 0;
  _rateCacheMisses = 0;
}

/// Returns rate cache hit count (for profiling).
int get rateCacheHits => _rateCacheHits;

/// Returns rate cache miss count (for profiling).
int get rateCacheMisses => _rateCacheMisses;

/// Packs rate-affecting capability state into a key (goal-independent).
///
/// Rate-affecting state includes:
/// - All skill levels (affect unlocks)
/// - Tool tiers (affect action speed/yield)
///
/// Layout across (low, high):
///   low[0-48]   Skill levels for all 7 skills (7 bits each = 49 bits)
///   low[49-57]  Tool tiers for 3 skills (3 bits each = 9 bits)
///   Total: 58 bits, fits in single int
_PackedCapabilityKey _packCapabilityKey(GlobalState state) {
  var low = 0;
  var shift = 0;

  void pack(int value, int bits) {
    final mask = (1 << bits) - 1;
    low |= (value & mask) << shift;
    shift += bits;
  }

  // Pack all skill levels (7 bits each, max 120)
  // Order matters for consistency - use Skill.values order
  for (final skill in Skill.values) {
    final level = state.skillState(skill).skillLevel;
    pack(level, 7);
  }

  // Pack tool tiers (3 bits each, max 6)
  pack(state.shop.axeLevel, 3); // Woodcutting
  pack(state.shop.fishingRodLevel, 3); // Fishing
  pack(state.shop.pickaxeLevel, 3); // Mining

  return _PackedCapabilityKey(low, 0);
}

/// Gets or computes rate summaries for current capability state.
/// Caches results keyed by packed capability key (goal-independent).
List<ActionRateSummary> _getRateSummaries(GlobalState state) {
  final capKey = _packCapabilityKey(state);

  final cached = _rateCache[capKey];
  if (cached != null) {
    _rateCacheHits++;
    return cached;
  }

  _rateCacheMisses++;
  final summaries = _computeRateSummaries(state);
  _rateCache[capKey] = summaries;
  return summaries;
}

/// Computes rate summaries for all skill actions (capability-level).
/// Does NOT include canStartNow/missingInputs - those are per-state.
List<ActionRateSummary> _computeRateSummaries(GlobalState state) {
  final summaries = <ActionRateSummary>[];
  final registries = state.registries;

  for (final skill in Skill.values) {
    final skillLevel = state.skillState(skill).skillLevel;

    for (final action in registries.actions.forSkill(skill)) {
      final isUnlocked = skillLevel >= action.unlockLevel;

      // Check if action has inputs (structural, not availability)
      final actionStateVal = state.actionState(action.id);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);
      final hasInputs = inputs.isNotEmpty;

      // Calculate expected ticks per action (mean duration)
      final expectedTicks = ticksFromDuration(action.meanDuration).toDouble();

      // Calculate expected gold per action from selling outputs
      var expectedGoldPerAction = 0.0;
      for (final output in action.outputs.entries) {
        final item = registries.items.byId(output.key);
        expectedGoldPerAction += item.sellsFor * output.value;
      }

      // For thieving, account for success rate and stun time on failure
      if (action is ThievingAction) {
        final thievingLevel = state.skillState(Skill.thieving).skillLevel;
        final mastery = state.actionState(action.id).masteryLevel;
        final stealth = calculateStealth(thievingLevel, mastery);
        final successChance = ((100 + stealth) / (100 + action.perception))
            .clamp(0.0, 1.0);
        final failureChance = 1.0 - successChance;

        // Expected gold = successChance * (1 + maxGold) / 2
        final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
        expectedGoldPerAction += expectedThievingGold;

        // Effective ticks = action duration + (failure chance * stun)
        final effectiveTicks =
            expectedTicks + failureChance * stunnedDurationTicks;

        final goldRatePerTick = effectiveTicks > 0
            ? expectedGoldPerAction / effectiveTicks
            : 0.0;
        final expectedXpPerAction = successChance * action.xp;
        final xpRatePerTick = effectiveTicks > 0
            ? expectedXpPerAction / effectiveTicks
            : 0.0;

        summaries.add(
          ActionRateSummary(
            actionId: action.id,
            skill: action.skill,
            unlockLevel: action.unlockLevel,
            isUnlocked: isUnlocked,
            expectedTicks: effectiveTicks,
            goldRatePerTick: goldRatePerTick,
            xpRatePerTick: xpRatePerTick,
            hasInputs: hasInputs,
          ),
        );
        continue;
      }

      final goldRatePerTick = expectedTicks > 0
          ? expectedGoldPerAction / expectedTicks
          : 0.0;
      final xpRatePerTick = expectedTicks > 0 ? action.xp / expectedTicks : 0.0;

      summaries.add(
        ActionRateSummary(
          actionId: action.id,
          skill: action.skill,
          unlockLevel: action.unlockLevel,
          isUnlocked: isUnlocked,
          expectedTicks: expectedTicks,
          goldRatePerTick: goldRatePerTick,
          xpRatePerTick: xpRatePerTick,
          hasInputs: hasInputs,
        ),
      );
    }
  }

  return summaries;
}

// ---------------------------------------------------------------------------
// Per-state filtering helpers (NOT cached)
// ---------------------------------------------------------------------------

/// Checks if an action can start now (has required inputs).
/// Called per-state, NOT cached.
bool _canStartNow(GlobalState state, ActionId actionId) {
  final action = state.registries.actions.byId(actionId);
  if (action is! SkillAction) return true;

  final selection = state.actionState(actionId).recipeSelection(action);
  final inputs = action.inputsForRecipe(selection);
  if (inputs.isEmpty) return true;

  for (final entry in inputs.entries) {
    final item = state.registries.items.byId(entry.key);
    if (state.inventory.countOfItem(item) < entry.value) {
      return false;
    }
  }
  return true;
}

/// Producer skill mapping (explicit, game-specific).
/// Returns null for skills without a clear single producer.
Skill? _producerSkillFor(Skill consumingSkill) {
  return switch (consumingSkill) {
    Skill.firemaking => Skill.woodcutting,
    Skill.cooking => Skill.fishing,
    Skill.smithing => Skill.mining,
    Skill.fletching => Skill.woodcutting,
    Skill.crafting => Skill.mining, // Gems come from mining
    // Skills with complex/multiple input sources - no single producer
    Skill.herblore => null,
    Skill.runecrafting => null,
    Skill.agility => null,
    Skill.summoning => null,
    Skill.altMagic => null,
    _ => null, // Non-consuming skills
  };
}

/// Select top N producers for a skill by throughput (gp/tick as proxy).
List<ActionRateSummary> _selectTopProducers(
  List<ActionRateSummary> summaries,
  Skill producerSkill,
  int n,
) {
  final candidates = <ActionRateSummary>[];
  for (final s in summaries) {
    if (s.skill != producerSkill) continue;
    if (!s.isUnlocked) continue;
    if (s.hasInputs) continue; // Only non-consuming producers

    // Insert into top-N by gpRatePerTick (proxy for throughput)
    if (candidates.length < n) {
      candidates
        ..add(s)
        ..sort((a, b) => b.goldRatePerTick.compareTo(a.goldRatePerTick));
    } else if (s.goldRatePerTick > candidates.last.goldRatePerTick) {
      candidates
        ..removeLast()
        ..add(s)
        ..sort((a, b) => b.goldRatePerTick.compareTo(a.goldRatePerTick));
    }
  }
  return candidates;
}

/// What events the planner should watch for to define "wait until interesting".
@immutable
class WatchList {
  const WatchList({
    this.upgradePurchaseIds = const [],
    this.lockedActivityIds = const [],
    this.consumingActivityIds = const [],
    this.inventory = false,
  });

  /// Shop purchase IDs for upgrades whose affordability defines wait points.
  final List<MelvorId> upgradePurchaseIds;

  /// Locked activities whose unlock defines wait points.
  final List<ActionId> lockedActivityIds;

  /// Consuming activities (with inputs) that we're gathering inputs for.
  /// Used to compute "inputs available" wait points.
  final List<ActionId> consumingActivityIds;

  /// Whether inventory-full should define a wait point.
  final bool inventory;
}

/// Output of enumerateCandidates - defines what interactions to consider
/// and what future events define "wait until interesting time".
@immutable
class Candidates {
  const Candidates({
    required this.switchToActivities,
    required this.buyUpgrades,
    required this.sellPolicy,
    required this.shouldEmitSellCandidate,
    required this.watch,
    required this.macros,
    this.consumingSkillStats,
  });

  /// Top-K unlocked activities to consider switching to.
  final List<ActionId> switchToActivities;

  /// Top-K upgrade purchase IDs worth considering (may be unaffordable).
  final List<MelvorId> buyUpgrades;

  /// Sell policy defining what items to keep vs sell.
  ///
  /// This is a POLICY decision from the goal, always available for:
  /// - WatchSet boundary detection (effectiveCredits calculation)
  /// - Actual sell interactions when emitted
  ///
  /// For GP goals: [SellAllPolicy] - sell everything.
  /// For skill goals: [SellExceptPolicy] - keep inputs for consuming skills.
  final SellPolicy sellPolicy;

  /// Whether to emit a sell candidate from this state.
  ///
  /// This is a HEURISTIC (pruning) decision, separate from policy:
  /// - For GP goals: true when inventory is getting full
  /// - For skill goals: false (selling doesn't contribute to XP)
  ///
  /// The solver uses this to decide whether to branch on selling,
  /// but sellPolicy is always available for boundary calculations.
  final bool shouldEmitSellCandidate;

  /// Events to watch for "wait until interesting time".
  final WatchList watch;

  /// Macro-level candidates (train skill until boundary).
  final List<MacroCandidate> macros;

  /// Stats from consuming skill candidate selection (if collected).
  final ConsumingSkillCandidateStats? consumingSkillStats;
}

/// Builds action summaries for all skill actions.
///
/// For each action, computes:
/// - isUnlocked: whether the player has the required skill level
/// - expectedTicks: mean duration in ticks
/// - goldRatePerTick: expected sell value per tick
/// - xpRatePerTick: skill XP per tick
/// - hasInputs: whether the action requires input items
/// - canStartNow: whether required inputs are available
/// - missingInputs: items needed but not available
List<ActionSummary> buildActionSummaries(GlobalState state) {
  final summaries = <ActionSummary>[];
  final registries = state.registries;

  for (final skill in Skill.values) {
    final skillLevel = state.skillState(skill).skillLevel;

    for (final action in registries.actions.forSkill(skill)) {
      final isUnlocked = skillLevel >= action.unlockLevel;

      // Check if action has inputs and whether they are available
      final actionStateVal = state.actionState(action.id);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);
      final hasInputs = inputs.isNotEmpty;

      // Compute missing inputs (skip items not in registry)
      final missingInputs = <MelvorId, int>{};
      if (hasInputs) {
        for (final entry in inputs.entries) {
          final item = registries.items.byId(entry.key);
          final available = state.inventory.countOfItem(item);
          if (available < entry.value) {
            missingInputs[entry.key] = entry.value - available;
          }
        }
      }
      final canStartNow = missingInputs.isEmpty;

      // Calculate expected ticks per action (mean duration)
      final expectedTicks = ticksFromDuration(action.meanDuration).toDouble();

      // Calculate expected gold per action from selling outputs
      var expectedGoldPerAction = 0.0;
      for (final output in action.outputs.entries) {
        final item = registries.items.byId(output.key);
        expectedGoldPerAction += item.sellsFor * output.value;
      }

      // For thieving, account for success rate and stun time on failure
      if (action is ThievingAction) {
        // Success rate depends on stealth vs perception
        // stealth = 40 + thievingLevel + masteryLevel
        final thievingLevel = state.skillState(Skill.thieving).skillLevel;
        final mastery = state.actionState(action.id).masteryLevel;
        final stealth = calculateStealth(thievingLevel, mastery);
        final successChance = ((100 + stealth) / (100 + action.perception))
            .clamp(0.0, 1.0);
        final failureChance = 1.0 - successChance;

        // Expected gold = successChance * (1 + maxGold) / 2
        final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
        expectedGoldPerAction += expectedThievingGold;

        // Effective ticks per attempt =
        // action duration + (failure chance * stun)
        final effectiveTicks =
            expectedTicks + failureChance * stunnedDurationTicks;

        final goldRatePerTick = effectiveTicks > 0
            ? expectedGoldPerAction / effectiveTicks
            : 0.0;
        // XP is only gained on success
        final expectedXpPerAction = successChance * action.xp;
        final xpRatePerTick = effectiveTicks > 0
            ? expectedXpPerAction / effectiveTicks
            : 0.0;

        summaries.add(
          ActionSummary(
            actionId: action.id,
            skill: action.skill,
            unlockLevel: action.unlockLevel,
            isUnlocked: isUnlocked,
            expectedTicks: effectiveTicks,
            goldRatePerTick: goldRatePerTick,
            xpRatePerTick: xpRatePerTick,
            hasInputs: hasInputs,
            canStartNow: canStartNow,
            missingInputs: missingInputs,
          ),
        );
        continue;
      }

      final goldRatePerTick = expectedTicks > 0
          ? expectedGoldPerAction / expectedTicks
          : 0.0;
      final xpRatePerTick = expectedTicks > 0 ? action.xp / expectedTicks : 0.0;

      summaries.add(
        ActionSummary(
          actionId: action.id,
          skill: action.skill,
          unlockLevel: action.unlockLevel,
          isUnlocked: isUnlocked,
          expectedTicks: expectedTicks,
          goldRatePerTick: goldRatePerTick,
          xpRatePerTick: xpRatePerTick,
          hasInputs: hasInputs,
          canStartNow: canStartNow,
          missingInputs: missingInputs,
        ),
      );
    }
  }

  return summaries;
}

/// Enumerates candidate interactions for the planner.
///
/// Generates macro candidates for goal-relevant skills.
///
/// For each skill relevant to the goal:
/// - Creates TrainSkillUntil macros with primaryStop = StopAtNextBoundary
/// - If skill has a goal target, also creates macro with
///   primaryStop = StopAtGoal
/// - Adds watchedStops for competitive upgrades (future extension)
List<MacroCandidate> _generateMacros(GlobalState state, Goal goal) {
  final macros = <MacroCandidate>[];

  // For MultiSkillGoal, generate macros for each subgoal
  if (goal is MultiSkillGoal) {
    for (final subgoal in goal.subgoals) {
      if (subgoal.isSatisfied(state)) continue;

      // Primary macro: train until next boundary
      // For consuming skills, use coupled produce/consume macro
      if (subgoal.skill.isConsuming) {
        macros.add(
          TrainConsumingSkillUntil(
            subgoal.skill,
            StopAtNextBoundary(subgoal.skill),
            watchedStops: [StopAtGoal(subgoal.skill, subgoal.targetXp)],
          ),
        );
      } else {
        macros.add(
          TrainSkillUntil(
            subgoal.skill,
            StopAtNextBoundary(subgoal.skill),
            watchedStops: [StopAtGoal(subgoal.skill, subgoal.targetXp)],
          ),
        );
      }
    }
  }

  // For ReachSkillLevelGoal, generate macros for the target skill
  if (goal is ReachSkillLevelGoal) {
    if (!goal.isSatisfied(state)) {
      // Determine primary stop: use goal if closer than next boundary,
      // otherwise use boundary
      final currentLevel = state.skillState(goal.skill).skillLevel;
      final boundaries = computeUnlockBoundaries(state.registries);
      final nextBoundary = boundaries[goal.skill]?.nextBoundary(currentLevel);

      // Use goal as primary if no boundary or goal is at/before boundary
      final primaryStop =
          nextBoundary == null || goal.targetLevel <= nextBoundary
          ? StopAtGoal(goal.skill, goal.targetXp)
          : StopAtNextBoundary(goal.skill);

      // For consuming skills, use coupled produce/consume macro
      if (goal.skill.isConsuming) {
        macros.add(TrainConsumingSkillUntil(goal.skill, primaryStop));
      } else {
        // For non-consuming skills, use simple train macro
        macros.add(TrainSkillUntil(goal.skill, primaryStop));
      }
    }
  }

  // For ReachGpGoal, we don't generate macros (use micro-steps instead)
  // GP goals benefit from frequent re-evaluation for upgrade purchases

  // For SegmentGoal, delegate to inner goal's macro generation
  if (goal is SegmentGoal) {
    return _generateMacros(state, goal.innerGoal);
  }

  return macros;
}

/// Augments macros with upgrade stop conditions.
///
/// For each macro, adds [StopWhenUpgradeAffordable] stops for relevant
/// upgrades from the watch list. This allows macros to break early when
/// a valuable upgrade becomes affordable.
List<MacroCandidate> _augmentMacrosWithUpgradeStops(
  List<MacroCandidate> macros,
  List<MelvorId> upgradeWatchList,
  GlobalState state,
  Goal goal,
) {
  if (upgradeWatchList.isEmpty) return macros;

  final shopRegistry = state.registries.shop;
  final augmented = <MacroCandidate>[];

  for (final macro in macros) {
    // Determine which skill this macro is training
    final Skill targetSkill;
    switch (macro) {
      case TrainSkillUntil(:final skill):
        targetSkill = skill;
      case TrainConsumingSkillUntil(:final consumingSkill):
        targetSkill = consumingSkill;
      case AcquireItem():
      case EnsureStock():
        // AcquireItem and EnsureStock macros don't need upgrade watching
        augmented.add(macro);
        continue;
    }

    // Find upgrades relevant to this skill
    final upgradeStops = <StopWhenUpgradeAffordable>[];
    for (final purchaseId in upgradeWatchList) {
      final purchase = shopRegistry.byId(purchaseId);
      if (purchase == null) continue;

      // Check if this upgrade affects the target skill
      final skillIds = purchase.contains.modifiers.skillIntervalSkillIds;
      final affectsTargetSkill = skillIds.any(
        (id) => Skill.tryFromId(id) == targetSkill,
      );
      if (!affectsTargetSkill) continue;

      // Compute cost
      final currencyCosts = purchase.cost.currencyCosts(
        bankSlotsPurchased: state.shop.bankSlotsPurchased,
      );
      final gpCost = currencyCosts.isEmpty ? 0 : currencyCosts.first.$2;
      if (gpCost <= 0) continue;

      upgradeStops.add(
        StopWhenUpgradeAffordable(purchaseId, gpCost, purchase.name),
      );
    }

    if (upgradeStops.isEmpty) {
      augmented.add(macro);
      continue;
    }

    // Create new macro with upgrade stops added to watchedStops
    switch (macro) {
      case TrainSkillUntil(
        :final skill,
        :final primaryStop,
        :final watchedStops,
      ):
        augmented.add(
          TrainSkillUntil(
            skill,
            primaryStop,
            watchedStops: [...watchedStops, ...upgradeStops],
          ),
        );
      case TrainConsumingSkillUntil(
        :final consumingSkill,
        :final primaryStop,
        :final watchedStops,
      ):
        augmented.add(
          TrainConsumingSkillUntil(
            consumingSkill,
            primaryStop,
            watchedStops: [...watchedStops, ...upgradeStops],
          ),
        );
      case AcquireItem():
      case EnsureStock():
        // Already handled above with continue
        break;
    }
  }

  return augmented;
}

/// Returns a small, cheap, deterministic set of candidate interactions
/// and future "interesting times". Does NOT simulate.
///
/// Activities are ranked by progress rate toward the [goal].
/// For [ReachGpGoal], this is gold/tick. For [ReachSkillLevelGoal],
/// this is XP/tick for the target skill.
///
/// Uses internal rate cache for expensive capability-level computations.
/// Per-state filtering (canStartNow, active action exclusion) is done fresh.
///
/// If [collectStats] is true, populates diagnostic stats for consuming skills.
///
/// If [sellPolicy] is provided, uses that policy for sell candidate emission.
/// Otherwise, computes the policy from the goal (backward compatibility).
/// For segment-based solving, pass the segment context's sellPolicy to ensure
/// consistency with WatchSet boundary detection.
Candidates enumerateCandidates(
  GlobalState state,
  Goal goal, {
  SellPolicy? sellPolicy,
  int activityCount = defaultActivityCandidateCount,
  int upgradeCount = defaultUpgradeCandidateCount,
  int lockedWatchCount = defaultLockedWatchCount,
  double inventoryThreshold = defaultInventoryThreshold,
  bool collectStats = false,
}) {
  // 1. Get cached rate summaries (capability-level, goal-independent)
  final rateSummaries = _getRateSummaries(state);

  // Also build legacy ActionSummary list for functions not yet migrated
  final summaries = buildActionSummaries(state);

  // Generate macro candidates for skill goals
  final macros = _generateMacros(state, goal);

  // Ranking function uses goal's activityRate to determine value
  double rankingFn(ActionSummary s) =>
      goal.activityRate(s.skill, s.goldRatePerTick, s.xpRatePerTick);
  double rateRankingFn(ActionRateSummary s) =>
      goal.activityRate(s.skill, s.goldRatePerTick, s.xpRatePerTick);

  // Build candidate set
  final candidateSet = <ActionId>{};
  ConsumingSkillCandidateStats? consumingStats;

  // Select unlocked activity candidates
  // For consuming skills, use strict pruning to avoid near-tie explosion
  if (goal is ReachSkillLevelGoal && goal.skill.isConsuming) {
    final result = _selectConsumingSkillCandidatesWithStats(
      summaries,
      state,
      goal.skill,
      collectStats: collectStats,
    );
    candidateSet.addAll(result.candidates);
    consumingStats = result.stats;
  } else {
    final selected = _selectUnlockedActivitiesByRanking(
      summaries,
      state,
      activityCount,
      rankingFn,
    );
    candidateSet.addAll(selected);
  }

  // Per-state filter: exclude current action
  final currentActionId = state.activeAction?.id;
  if (currentActionId != null) {
    candidateSet.remove(currentActionId);
  }

  // ALWAYS include producers for consuming goal skills (UNCONDITIONAL)
  // This is the escape hatch - don't gate on topK or feasibility
  final consumingGoalSkills = goal.consumingSkills;
  for (final consumingSkill in consumingGoalSkills) {
    final producerSkill = _producerSkillFor(consumingSkill);
    if (producerSkill == null) continue; // No clear producer for this skill
    // N=2 per consuming skill is plenty - just escape hatches
    final producers = _selectTopProducers(rateSummaries, producerSkill, 2);
    for (final p in producers) {
      if (p.actionId != currentActionId) {
        candidateSet.add(p.actionId);
      }
    }
  }

  // For consuming actions in candidates, add their specific producers
  // if they can't start now
  for (final actionId in candidateSet.toList()) {
    final rateSummary = rateSummaries.firstWhere(
      (s) => s.actionId == actionId,
      orElse: () => rateSummaries.first,
    );
    if (rateSummary.actionId == actionId &&
        rateSummary.hasInputs &&
        !_canStartNow(state, actionId)) {
      // Find producers for missing inputs
      final producers = _findProducersForActionByRate(
        rateSummaries,
        state,
        actionId,
      );
      for (final p in producers) {
        if (p != currentActionId) {
          candidateSet.add(p);
        }
      }
    }
  }

  final switchToActivities = candidateSet.toList();

  // Select locked activities to watch (top L by smallest unlockDeltaTicks)
  // Only watch activities for skills relevant to the goal
  final lockedActivitiesToWatch = _selectLockedActivitiesToWatch(
    summaries,
    state,
    lockedWatchCount,
    goal: goal,
  );

  // Build list of candidate activity IDs (current + switchTo)
  final candidateActivityIds = <ActionId>[
    ...switchToActivities,
    if (state.activeAction != null) state.activeAction!.id,
  ];

  // Find the best current rate among all unlocked activities using ranking fn
  final unlockedSummaries = rateSummaries.where((s) => s.isUnlocked);
  final bestCurrentRate = unlockedSummaries.isEmpty
      ? 0.0
      : unlockedSummaries.map(rateRankingFn).reduce((a, b) => a > b ? a : b);

  // Select upgrade candidates
  // Only include upgrades for skills relevant to the goal
  final upgradeResult = _selectUpgradeCandidates(
    summaries,
    state,
    upgradeCount,
    candidateActivityIds: candidateActivityIds,
    bestCurrentRate: bestCurrentRate,
    goal: goal,
  );

  // Augment macros with upgrade stops from the watch list
  final augmentedMacros = _augmentMacrosWithUpgradeStops(
    macros,
    upgradeResult.toWatch,
    state,
    goal,
  );

  // Find consuming activities relevant to the goal.
  // Include even activities that can start now, because we may need to
  // gather MORE inputs to complete the goal, not just enough to start.
  final consumingActivitiesToWatch = <ActionId>[];
  for (final summary in rateSummaries) {
    if (!summary.isUnlocked) continue;
    if (!summary.hasInputs) continue;
    if (!goal.isSkillRelevant(summary.skill)) continue;
    consumingActivitiesToWatch.add(summary.actionId);
  }

  // Use provided sell policy (from SegmentContext) if available.
  // Fallback to goal.computeSellPolicy only for backward compatibility
  // with non-segment solves. This fallback should be removed once all
  // callers pass the policy explicitly.
  final effectiveSellPolicy = sellPolicy ?? goal.computeSellPolicy(state);

  // Whether to emit a sell candidate is a HEURISTIC (pruning) decision.
  // For skill goals, selling doesn't contribute to XP, so we skip it.
  // For GP goals, we only consider selling when inventory is getting full.
  final inventoryUsedFraction = state.inventoryCapacity > 0
      ? state.inventoryUsed / state.inventoryCapacity
      : 0.0;
  final shouldEmitSellCandidate =
      goal.isSellRelevant && inventoryUsedFraction > inventoryThreshold;

  return Candidates(
    switchToActivities: switchToActivities,
    buyUpgrades: upgradeResult.candidates,
    sellPolicy: effectiveSellPolicy,
    shouldEmitSellCandidate: shouldEmitSellCandidate,
    watch: WatchList(
      upgradePurchaseIds: upgradeResult.toWatch,
      lockedActivityIds: lockedActivitiesToWatch,
      consumingActivityIds: consumingActivitiesToWatch,
      inventory: shouldEmitSellCandidate,
    ),
    macros: augmentedMacros,
    consumingSkillStats: consumingStats,
  );
}

/// Find producers for a specific action's missing inputs.
/// Uses rate summaries (capability-level).
List<ActionId> _findProducersForActionByRate(
  List<ActionRateSummary> summaries,
  GlobalState state,
  ActionId actionId,
) {
  final action = state.registries.actions.byId(actionId);
  if (action is! SkillAction) return [];

  final selection = state.actionState(actionId).recipeSelection(action);
  final inputs = action.inputsForRecipe(selection);
  if (inputs.isEmpty) return [];

  final producers = <ActionId>[];
  for (final inputItemId in inputs.keys) {
    // Find producers for this input
    for (final s in summaries) {
      if (!s.isUnlocked) continue;
      if (s.hasInputs) continue; // Only non-consuming producers

      final producerAction = state.registries.actions.byId(s.actionId);
      if (producerAction is! SkillAction) continue;

      if (producerAction.outputs.containsKey(inputItemId)) {
        producers.add(s.actionId);
        break; // One producer per input is enough
      }
    }
  }
  return producers;
}

/// Finds producer actions for a given item.
///
/// Returns action summaries for unlocked actions that produce the given item
/// in their outputs. Used to find input-producing actions when a consuming
/// action can't start due to missing inputs.
List<ActionSummary> _findProducersForItem(
  List<ActionSummary> summaries,
  GlobalState state,
  MelvorId itemId,
) {
  final producers = <ActionSummary>[];
  final registries = state.registries;

  for (final summary in summaries) {
    if (!summary.isUnlocked) continue;
    if (summary.hasInputs) continue; // Don't chain consuming actions

    final action = registries.actions.byId(summary.actionId);
    if (action is! SkillAction) continue;

    // Check if this action produces the item we need
    if (action.outputs.containsKey(itemId)) {
      producers.add(summary);
    }
  }

  return producers;
}

/// Stats from consuming skill candidate selection.
@immutable
class ConsumingSkillCandidateStats {
  const ConsumingSkillCandidateStats({
    required this.consumerActionsConsidered,
    required this.producerActionsConsidered,
    required this.pairsConsidered,
    required this.pairsKept,
    required this.topPairs,
  });

  static const empty = ConsumingSkillCandidateStats(
    consumerActionsConsidered: 0,
    producerActionsConsidered: 0,
    pairsConsidered: 0,
    pairsKept: 0,
    topPairs: [],
  );

  final int consumerActionsConsidered;
  final int producerActionsConsidered;
  final int pairsConsidered;
  final int pairsKept;
  final List<({String consumerId, String producerId, double score})> topPairs;
}

/// Result of consuming skill candidate selection.
class _ConsumingSkillResult {
  _ConsumingSkillResult({required this.candidates, this.stats});

  final List<ActionId> candidates;
  final ConsumingSkillCandidateStats? stats;
}

/// Strict pruning for consuming skills.
///
/// For consuming skills (e.g., Firemaking, Cooking), we need to avoid the
/// "near-tie explosion" where multiple consumer actions have similar scores.
/// This function:
/// - Calculates sustainable XP/tick for each consumer action (accounting for
///   production time of inputs)
/// - Selects top N consumer actions (default N=2)
/// - For each selected consumer action, finds the best producer (highest
///   output/tick)
/// - Applies tie-breaking: sustainable XP/tick > fewer switches > has inputs
///
/// Returns a list of activity IDs to consider as switch-to candidates.
/// If [collectStats] is true, also returns diagnostic stats.
_ConsumingSkillResult _selectConsumingSkillCandidatesWithStats(
  List<ActionSummary> summaries,
  GlobalState state,
  Skill consumingSkill, {
  int maxConsumerActions = 2,
  bool collectStats = false,
}) {
  final registries = state.registries;
  final currentActionId = state.activeAction?.id;

  // Find all unlocked consumer actions for this consuming skill
  final consumerActions = summaries
      .where(
        (s) =>
            s.skill == consumingSkill &&
            s.isUnlocked &&
            s.hasInputs &&
            s.actionId != currentActionId,
      )
      .toList();

  if (consumerActions.isEmpty) {
    return _ConsumingSkillResult(
      candidates: [],
      stats: collectStats ? ConsumingSkillCandidateStats.empty : null,
    );
  }

  // Track stats
  var producerActionsConsidered = 0;
  var pairsConsidered = 0;

  // Calculate sustainable XP/tick for each consumer action
  final consumersWithRates =
      <
        ({
          ActionSummary consumer,
          double sustainableXpPerTick,
          ActionSummary? producer,
        })
      >[];

  for (final consumerSummary in consumerActions) {
    final consumerAction =
        registries.actions.byId(consumerSummary.actionId) as SkillAction;
    final inputItem = consumerAction.inputs.keys.first;

    // Find best producer for this input
    final producers = _findProducersForItem(summaries, state, inputItem);
    if (producers.isEmpty) continue;

    producerActionsConsidered += producers.length;
    pairsConsidered += producers.length; // Each producer forms a pair

    // Best producer is the one with highest output/tick
    producers.sort((a, b) {
      final aAction = registries.actions.byId(a.actionId) as SkillAction;
      final bAction = registries.actions.byId(b.actionId) as SkillAction;
      final aOutputPerTick =
          (aAction.outputs[inputItem] ?? 1) / a.expectedTicks;
      final bOutputPerTick =
          (bAction.outputs[inputItem] ?? 1) / b.expectedTicks;
      return bOutputPerTick.compareTo(aOutputPerTick);
    });
    final bestProducer = producers.first;
    final producerAction =
        registries.actions.byId(bestProducer.actionId) as SkillAction;

    // Calculate sustainable XP rate
    final consumeTicksPerAction = consumerSummary.expectedTicks;
    final produceTicksPerAction = bestProducer.expectedTicks;
    final inputsNeededPerAction = consumerAction.inputs[inputItem] ?? 1;
    final outputsPerAction = producerAction.outputs[inputItem] ?? 1;

    final produceActionsPerConsumeAction =
        inputsNeededPerAction / outputsPerAction;
    final totalTicksPerCycle =
        (produceActionsPerConsumeAction * produceTicksPerAction) +
        consumeTicksPerAction;

    final consumeXpPerAction = consumerAction.xp.toDouble();
    final sustainableXpPerTick = consumeXpPerAction / totalTicksPerCycle;

    consumersWithRates.add((
      consumer: consumerSummary,
      sustainableXpPerTick: sustainableXpPerTick,
      producer: bestProducer,
    ));
  }

  // Sort by sustainable XP/tick (descending)
  consumersWithRates.sort((a, b) {
    // Primary: sustainable XP/tick
    final xpCmp = b.sustainableXpPerTick.compareTo(a.sustainableXpPerTick);
    if (xpCmp != 0) return xpCmp;

    // Tie-breaker 1: Prefer already having inputs in inventory
    final aHasInputs = a.consumer.canStartNow ? 1 : 0;
    final bHasInputs = b.consumer.canStartNow ? 1 : 0;
    final inputsCmp = bHasInputs.compareTo(aHasInputs);
    if (inputsCmp != 0) return inputsCmp;

    // Tie-breaker 2: Prefer fewer switches (longer macro segments)
    // Actions with longer duration mean fewer switches
    final durationCmp = b.consumer.expectedTicks.compareTo(
      a.consumer.expectedTicks,
    );
    return durationCmp;
  });

  // Select top N consumer actions
  final selectedConsumers = consumersWithRates
      .take(maxConsumerActions)
      .toList();

  // Build result: for each consumer action, include it and its best producer
  final result = <ActionId>[];
  for (final entry in selectedConsumers) {
    result.add(entry.consumer.actionId);
    if (entry.producer != null) {
      result.add(entry.producer!.actionId);
    }
  }

  // Build stats if requested
  ConsumingSkillCandidateStats? stats;
  if (collectStats) {
    final topPairs = selectedConsumers
        .map(
          (e) => (
            consumerId: e.consumer.actionId.localId.name,
            producerId: e.producer?.actionId.localId.name ?? 'none',
            score: e.sustainableXpPerTick,
          ),
        )
        .toList();

    stats = ConsumingSkillCandidateStats(
      consumerActionsConsidered: consumerActions.length,
      producerActionsConsidered: producerActionsConsidered,
      pairsConsidered: pairsConsidered,
      pairsKept: selectedConsumers.length,
      topPairs: topPairs,
    );
  }

  return _ConsumingSkillResult(candidates: result, stats: stats);
}

/// Selects top K unlocked activities by a custom ranking function.
///
/// Only includes activities with positive ranking (> 0). This filters out
/// activities that don't contribute to the goal (e.g., fishing when the
/// goal is a woodcutting level).
///
/// For consuming actions (those with inputs):
/// - If the action can start now (has inputs), include it
/// - If the action can't start, include producer actions for missing inputs
List<ActionId> _selectUnlockedActivitiesByRanking(
  List<ActionSummary> summaries,
  GlobalState state,
  int count,
  double Function(ActionSummary) rankingFn,
) {
  final currentActionId = state.activeAction?.id;

  // Filter to unlocked actions with non-negative ranking, excluding current
  // action. Include zero-ranked actions to support producer skills for
  // consuming actions (e.g., Woodcutting for Firemaking goals).
  final unlocked =
      summaries
          .where(
            (s) =>
                s.isUnlocked &&
                s.actionId != currentActionId &&
                rankingFn(s) >= 0,
          )
          .toList()
        ..sort((a, b) => rankingFn(b).compareTo(rankingFn(a)));

  // Build result set, handling consuming actions specially
  final result = <ActionId>{};
  final producersAdded = <ActionId>{};

  for (final summary in unlocked) {
    if (result.length >= count) break;

    if (!summary.hasInputs) {
      // Non-consuming action: always include
      result.add(summary.actionId);
    } else if (summary.canStartNow) {
      // Consuming action with inputs available: include
      result.add(summary.actionId);
    } else {
      // Consuming action that can't start: add producers for missing inputs
      // Also add the consuming action itself so the solver can switch to it
      // when inputs become available
      result.add(summary.actionId);

      for (final missingItemId in summary.missingInputs.keys) {
        final producers = _findProducersForItem(
          summaries,
          state,
          missingItemId,
        );
        for (final producer in producers) {
          if (!producersAdded.contains(producer.actionId) &&
              producer.actionId != currentActionId) {
            producersAdded.add(producer.actionId);
            result.add(producer.actionId);
          }
        }
      }
    }
  }

  return result.take(count * 2).toList(); // Allow extra for producers
}

/// Selects top L locked activities by smallest unlockDeltaTicks.
///
/// Only activities for skills relevant to the [goal] are considered.
List<ActionId> _selectLockedActivitiesToWatch(
  List<ActionSummary> summaries,
  GlobalState state,
  int count, {
  required Goal goal,
}) {
  // Filter to locked actions for skills relevant to the goal
  final locked = summaries.where((s) {
    if (s.isUnlocked) return false;
    if (!goal.isSkillRelevant(s.skill)) return false;
    return true;
  }).toList();

  // For each locked action, compute ticks until unlock
  final withDelta = <(ActionId, double)>[];
  for (final summary in locked) {
    final skillState = state.skillState(summary.skill);
    final currentXp = skillState.xp;
    final requiredXp = startXpForLevel(summary.unlockLevel);
    final xpNeeded = requiredXp - currentXp;

    if (xpNeeded <= 0) {
      // Already have enough XP (shouldn't happen since !isUnlocked)
      continue;
    }

    // Find current XP rate for this skill from unlocked activities
    final xpRate = _currentXpRateForSkill(summaries, summary.skill);
    if (xpRate <= 0) {
      // No way to gain XP for this skill
      continue;
    }

    final unlockDeltaTicks = xpNeeded / xpRate;
    withDelta.add((summary.actionId, unlockDeltaTicks));
  }

  // Sort by smallest unlockDeltaTicks
  withDelta.sort((a, b) => a.$2.compareTo(b.$2));

  // Take top L
  return withDelta.take(count).map((e) => e.$1).toList();
}

/// Gets the best XP rate per tick for a skill from unlocked activities.
double _currentXpRateForSkill(List<ActionSummary> summaries, Skill skill) {
  final forSkill = summaries.where((s) => s.skill == skill && s.isUnlocked);
  if (forSkill.isEmpty) return 0;
  return forSkill.map((s) => s.xpRatePerTick).reduce((a, b) => a > b ? a : b);
}

/// Result of upgrade candidate selection.
class _UpgradeResult {
  const _UpgradeResult({required this.candidates, required this.toWatch});
  final List<MelvorId> candidates;
  final List<MelvorId> toWatch;
}

/// Selects top M upgrades by smallest paybackTicks.
///
/// Only includes upgrades that improve rate for at least one of the
/// candidate activities AND would make that activity competitive with or
/// better than the best current rate.
///
/// Only upgrades for skills relevant to the [goal] are considered.
///
/// The watch list includes all upgrades that meet skill requirements and have
/// positive gain, regardless of competitiveness (the planner needs to know
/// when they become affordable to reconsider decisions).
_UpgradeResult _selectUpgradeCandidates(
  List<ActionSummary> summaries,
  GlobalState state,
  int count, {
  required Goal goal,
  List<ActionId>? candidateActivityIds,
  double bestCurrentRate = 0.0,
}) {
  final candidates = <(MelvorId, double)>[];
  final toWatch = <MelvorId>[];

  final shopRegistry = state.registries.shop;
  final availableUpgrades = shopRegistry.availableSkillUpgrades(
    state.shop.purchaseCounts,
  );

  for (final (purchase, skill) in availableUpgrades) {
    // Only consider upgrades for skills relevant to the goal
    if (!goal.isSkillRelevant(skill)) continue;

    // Doesn't meet skill requirement
    final requirements = shopRegistry.skillLevelRequirements(purchase);
    final meetsAllRequirements = requirements.every((req) {
      final skillLevel = state.skillState(req.skill).skillLevel;
      return skillLevel >= req.level;
    });
    if (!meetsAllRequirements) continue;

    // Find affected activities that are:
    // 1. Same skill as upgrade
    // 2. Unlocked
    // 3. In the candidate list (if provided)
    final affectedActivities = summaries.where((s) {
      if (s.skill != skill) return false;
      if (!s.isUnlocked) return false;
      if (candidateActivityIds != null &&
          !candidateActivityIds.contains(s.actionId)) {
        return false;
      }
      return true;
    });

    if (affectedActivities.isEmpty) continue;

    // Get best rate among affected activities using goal's rate function
    final baseRate = affectedActivities
        .map(
          (s) => goal.activityRate(s.skill, s.goldRatePerTick, s.xpRatePerTick),
        )
        .reduce((a, b) => a > b ? a : b);

    if (baseRate <= 0) continue;

    // Compute new rate after upgrade
    // Upgrade gives durationMultiplier (e.g., 0.95 = -5% duration)
    // Shorter duration means higher rate: newRate = baseRate / modifier
    final modifier = shopRegistry.durationMultiplier(purchase);
    final newRate = baseRate / modifier;
    final gain = newRate - baseRate;

    if (gain <= 0) continue;

    // Add to watch list - planner needs to know when any valid upgrade
    // becomes affordable, even if not currently competitive.
    // Invariant: toWatch is for timing waits, NOT for deciding to buy.
    toWatch.add(purchase.id);

    // Invariant: only add to candidates if competitive.
    // Skip if upgraded rate wouldn't beat or match best current rate -
    // buying this upgrade won't make this activity worth switching to.
    // This is the key guard that prevents "buy axe while thieving" bugs.
    if (newRate < bestCurrentRate) continue;

    // Payback time = cost / gain per tick
    final cost = shopRegistry.gpCost(purchase);
    if (cost == null) continue; // Skip upgrades with special pricing
    final paybackTicks = cost / gain;
    candidates.add((purchase.id, paybackTicks));
  }

  // Sort by smallest paybackTicks
  candidates.sort((a, b) => a.$2.compareTo(b.$2));

  // Take top M
  final topCandidates = candidates.take(count).map((e) => e.$1).toList();

  return _UpgradeResult(candidates: topCandidates, toWatch: toWatch);
}
