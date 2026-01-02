/// Solver: A* search to find minimum-ticks plan to reach a goal.
///
/// ## Pipeline Overview
///
/// 1. [estimateRates] returns *flows* (direct GP + items/tick + XP/tick).
/// 2. [ValueModel] converts flows → scalar objective value (policy-dependent).
/// 3. [enumerateCandidates] proposes a *small* branch set and a *watch* set.
/// 4. [availableInteractions] returns immediately actionable interactions only.
/// 5. [nextDecisionDelta] returns the soonest time a watched event could
///    change what we'd do.
/// 6. Search expands 0-tick action edges + 1 wait edge.
///
/// ## Key Invariant
///
/// **Watch lists affect only waiting, never imply we should take an action.**
/// An upgrade being "watched" (for affordability timing) does NOT mean we
/// should buy it. Only upgrades in [Candidates.buyUpgrades] are actionable.
///
/// ## Module Structure
///
/// The solver is split into focused modules:
/// - rate_cache.dart - Rate caching for the A* heuristic
/// - state_pruning.dart - Bucket keys and Pareto frontier for pruning
/// - state_advance.dart - State advancement (expected-value and full sim)
/// - consume_until.dart - Goal-aware execution with death handling
/// - execute_plan.dart - Plan execution with step-by-step tracking
/// - prerequisites.dart - Action prerequisite resolution
library;

import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/next_decision_delta.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/analysis/watch_set.dart';
import 'package:logic/src/solver/candidates/enumerate_candidates.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/candidates/macro_expansion_context.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver_profile.dart';
import 'package:logic/src/solver/core/value_model.dart';
import 'package:logic/src/solver/execution/execute_plan.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/execution/state_advance.dart';
import 'package:logic/src/solver/interactions/apply_interaction.dart';
import 'package:logic/src/solver/interactions/available_interactions.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:logic/src/types/time_away.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Debug invariant assertions
// ---------------------------------------------------------------------------

/// Asserts that the game state is valid (debug only).
///
/// Checks:
/// - GP is non-negative
/// - All inventory item counts are non-negative
/// - Player HP is non-negative
///
/// These assertions catch bugs early: if the solver or simulator produces
/// invalid states, this will fail fast with a clear error message.
void _assertValidState(GlobalState state) {
  assert(state.gp >= 0, 'Negative GP: ${state.gp}');
  assert(state.playerHp >= 0, 'Negative HP: ${state.playerHp}');
  for (final stack in state.inventory.items) {
    assert(stack.count >= 0, 'Negative inventory count for ${stack.item.name}');
  }
  for (final entry in state.skillStates.entries) {
    assert(
      entry.value.xp >= 0,
      'Negative XP for ${entry.key}: ${entry.value.xp}',
    );
  }
}

/// Asserts that delta ticks are non-negative (debug only).
void _assertNonNegativeDelta(int deltaTicks, String context) {
  assert(deltaTicks >= 0, 'Negative deltaTicks ($deltaTicks) in $context');
}

/// Asserts that progress is monotonic between two states (debug only).
///
/// XP should never decrease, GP can decrease (via purchases).
void _assertMonotonicProgress(
  GlobalState before,
  GlobalState after,
  String context,
) {
  for (final skill in before.skillStates.keys) {
    final beforeXp = before.skillState(skill).xp;
    final afterXp = after.skillState(skill).xp;
    assert(
      afterXp >= beforeXp,
      'XP decreased for $skill ($beforeXp -> $afterXp) in $context',
    );
  }
}

/// Gold bucket size for coarse state grouping.
/// Larger values = fewer unique states = more pruning but less precision.
const int _goldBucketSize = 50;

/// HP bucket size for coarse state grouping during thieving.
/// Groups HP into buckets to reduce state explosion while still
/// distinguishing "safe" vs "near death" states.
const int _hpBucketSize = 10;

/// Size of inventory bucket for dominance pruning.
/// Groups inventory counts to reduce state explosion.
const int _inventoryBucketSize = 10;

/// Bucket key for dominance pruning - groups states with same structural
/// situation. Goal-scoped: only tracks skills/upgrades relevant to the goal.
///
/// For WC=99/Fish=99 goal, tracks: {WC level, Fish level, axe tier, rod tier,
/// active action}.
/// For Thieving goal, tracks: {Thieving level, HP, mastery, active action}.
/// For GP goals, tracks all skills (current behavior).
class _BucketKey extends Equatable {
  const _BucketKey({
    required this.activityName,
    required this.skillLevels,
    // TODO(eseidel): Track axeLevel/rodLevel/pickLevel as purchases instead?
    required this.axeLevel,
    required this.rodLevel,
    required this.pickLevel,
    required this.hpBucket,
    required this.masteryLevel,
    required this.inventoryBucket,
    required this.inputItemMix,
  });

  /// Creates a goal-scoped bucket key from a game state.
  /// Only tracks skills, HP, mastery, and inventory relevant to the goal.
  factory _BucketKey.fromState(GlobalState state, Goal goal) {
    // Track active action - needed to distinguish states
    final actionId = state.activeAction?.id;
    final activityName = actionId != null ? actionId.localId.name : 'none';

    // Build skill levels map for only goal-relevant skills
    final skillLevels = <Skill, int>{};
    for (final skill in goal.relevantSkillsForBucketing) {
      skillLevels[skill] = state.skillState(skill).skillLevel;
    }

    // Track HP only if goal requires it (thieving goals)
    final hpBucket = goal.shouldTrackHp ? state.playerHp ~/ _hpBucketSize : 0;

    // Track mastery only if goal requires it (thieving goals)
    final masteryLevel = goal.shouldTrackMastery && actionId != null
        ? state.actionState(actionId).masteryLevel
        : 0;

    // Track inventory only if goal requires it (consuming skill goals)
    final inventoryBucket = _computeInventoryBucket(state, goal);

    // Track which input item types for multi-input consuming skills.
    // This prevents incorrect dominance pruning where states with different ore
    // mixes (e.g., 10 copper vs 5 copper + 5 tin) are treated as equivalent.
    final inputItemMix = _computeInputItemMix(state, goal);

    return _BucketKey(
      activityName: activityName,
      skillLevels: skillLevels,
      axeLevel: state.shop.axeLevel,
      rodLevel: state.shop.fishingRodLevel,
      pickLevel: state.shop.pickaxeLevel,
      hpBucket: hpBucket,
      masteryLevel: masteryLevel,
      inventoryBucket: inventoryBucket,
      inputItemMix: inputItemMix,
    );
  }

  static int _computeInventoryBucket(GlobalState state, Goal goal) {
    if (!goal.shouldTrackInventory) return 0;
    final totalItems = state.inventory.items.fold<int>(
      0,
      (sum, stack) => sum + stack.count,
    );
    // For small inventories (< 100 items), use exact count
    // For larger inventories, use buckets
    return totalItems < 100
        ? totalItems
        : 100 + (totalItems - 100) ~/ _inventoryBucketSize;
  }

  /// Computes a hash representing which input item types are present.
  ///
  /// For consuming skills like smithing that require multiple input types
  /// (e.g., copper ore AND tin ore), states with different mixes should not
  /// dominate each other even if they have the same total item count.
  ///
  /// This function identifies all items that could be inputs to consuming
  /// actions for the goal's consuming skills, then creates a bitmask of
  /// which of those input types are present (non-zero count) in inventory.
  static int _computeInputItemMix(GlobalState state, Goal goal) {
    if (!goal.shouldTrackInventory) return 0;
    final consumingSkills = goal.consumingSkills;
    if (consumingSkills.isEmpty) return 0;

    // Collect all possible input item IDs for consuming skills
    final inputItemIds = <MelvorId>{};
    for (final skill in consumingSkills) {
      for (final action in state.registries.actions.forSkill(skill)) {
        inputItemIds.addAll(action.inputs.keys);
      }
    }

    if (inputItemIds.isEmpty) return 0;

    // Sort for deterministic ordering, then create a bitmask
    final sortedIds = inputItemIds.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    var mix = 0;
    for (var i = 0; i < sortedIds.length && i < 30; i++) {
      // Limit to 30 bits to avoid overflow
      final itemId = sortedIds[i];
      final item = state.registries.items.byId(itemId);
      if (state.inventory.countOfItem(item) > 0) {
        mix |= 1 << i;
      }
    }

    return mix;
  }

  /// Active action name - needed to distinguish woodcutting vs fishing states
  final String activityName;

  /// Map of goal-relevant skills to their levels.
  /// For WC=99/Fish=99: {Skill.woodcutting: 50, Skill.fishing: 40}
  /// For GP goals: all 7 skills
  final Map<Skill, int> skillLevels;

  /// Tool tier upgrades (always tracked for their respective skills)
  final int axeLevel;
  final int rodLevel;
  final int pickLevel;

  /// HP bucket for thieving - only tracked if goal.shouldTrackHp
  final int hpBucket;

  /// Mastery level for the current action - only tracked if
  /// goal.shouldTrackMastery
  final int masteryLevel;

  /// Inventory bucket - only tracked if goal.shouldTrackInventory
  final int inventoryBucket;

  /// Hash of which input item types are present (for multi-input consuming
  /// skills like smithing). This prevents incorrect dominance pruning when
  /// different ore mixes have the same total count but can't substitute.
  ///
  /// For example, 10 copper + 0 tin should not dominate 5 copper + 5 tin,
  /// even though both have total=10, because only the latter can make bars.
  final int inputItemMix;

  @override
  List<Object?> get props => [
    activityName,
    skillLevels,
    axeLevel,
    rodLevel,
    pickLevel,
    hpBucket,
    masteryLevel,
    inventoryBucket,
    inputItemMix,
  ];
}

/// A point on the Pareto frontier for dominance checking.
class _FrontierPoint {
  _FrontierPoint(this.ticks, this.progress);

  final int ticks;

  /// Progress toward goal (gold for GP goals, XP for skill goals).
  final int progress;
}

/// Manages per-bucket Pareto frontiers for dominance pruning.
/// The second dimension (progress) is goal-dependent:
/// - For GP goals: effective credits (GP + inventory value)
/// - For skill goals: current XP in the target skill
class _ParetoFrontier {
  final Map<_BucketKey, List<_FrontierPoint>> _frontiers = {};

  // Stats
  int _inserted = 0;
  int _removed = 0;

  FrontierStats get stats =>
      FrontierStats(inserted: _inserted, removed: _removed);

  /// Checks if (ticks, progress) is dominated by existing frontier.
  /// If not dominated, inserts the point and removes any points it dominates.
  /// Returns true if dominated (caller should skip this node).
  bool isDominatedOrInsert(_BucketKey key, int ticks, int progress) {
    final frontier = _frontiers.putIfAbsent(key, () => []);

    // Check if dominated by any existing point
    // A dominates B if A.ticks <= B.ticks && A.progress >= B.progress
    for (final p in frontier) {
      if (p.ticks <= ticks && p.progress >= progress) {
        return true; // Dominated
      }
    }

    // Not dominated - remove any points that new point dominates
    final originalLength = frontier.length;
    frontier.removeWhere((p) => ticks <= p.ticks && progress >= p.progress);
    _removed += originalLength - frontier.length;

    // Insert new point
    frontier.add(_FrontierPoint(ticks, progress));
    _inserted++;

    return false; // Not dominated
  }
}

/// Default limits for the solver to prevent runaway searches.
const int defaultMaxExpandedNodes = 200000;
const int defaultMaxQueueSize = 500000;

/// Result of rate computation with optional diagnostic info.
class _RateResult {
  _RateResult(this.rate, {this.zeroReason});

  final double rate;
  final RateZeroReason? zeroReason;
}

/// Cache for best unlocked rate by state key (skill levels + tool tiers).
/// Supports both GP goals (gold/tick) and skill goals (XP/tick).
class _RateCache {
  _RateCache(this.goal);

  final Goal goal;
  final Map<String, double> _cache = {};
  final Map<String, double> _skillCache = {};
  final Map<String, RateZeroReason?> _reasonCache = {};

  String _rateKey(GlobalState state) {
    // Key by skill levels and tool tiers (things that affect unlocks/rates)
    return '${state.skillState(Skill.woodcutting).skillLevel}|'
        '${state.skillState(Skill.fishing).skillLevel}|'
        '${state.skillState(Skill.mining).skillLevel}|'
        '${state.skillState(Skill.thieving).skillLevel}|'
        '${state.skillState(Skill.firemaking).skillLevel}|'
        '${state.skillState(Skill.cooking).skillLevel}|'
        '${state.skillState(Skill.smithing).skillLevel}|'
        '${state.shop.axeLevel}|'
        '${state.shop.fishingRodLevel}|'
        '${state.shop.pickaxeLevel}';
  }

  double getBestUnlockedRate(GlobalState state) {
    final key = _rateKey(state);
    final cached = _cache[key];
    if (cached != null) return cached;

    final result = _computeBestUnlockedRate(state);
    _cache[key] = result.rate;
    _reasonCache[key] = result.zeroReason;
    return result.rate;
  }

  /// Gets the reason why the rate was zero for this state.
  /// Returns null if the rate was non-zero or not yet computed.
  RateZeroReason? getZeroReason(GlobalState state) {
    final key = _rateKey(state);
    return _reasonCache[key];
  }

  /// Gets the best XP rate for a specific skill.
  /// Used by multi-skill goal heuristic to compute per-skill estimates.
  double getBestRateForSkill(GlobalState state, Skill targetSkill) {
    final key = '${_rateKey(state)}|${targetSkill.name}';
    final cached = _skillCache[key];
    if (cached != null) return cached;

    final rate = _computeBestRateForSkill(state, targetSkill);
    _skillCache[key] = rate;
    return rate;
  }

  double _computeBestRateForSkill(GlobalState state, Skill targetSkill) {
    var maxRate = 0.0;
    final registries = state.registries;
    final skillLevel = state.skillState(targetSkill).skillLevel;

    for (final action in registries.actions.forSkill(targetSkill)) {
      // Only consider unlocked actions
      if (skillLevel < action.unlockLevel) continue;

      // Calculate expected ticks with upgrade modifier
      final baseExpectedTicks = ticksFromDuration(
        action.meanDuration,
      ).toDouble();
      final percentModifier = state.shopDurationModifierForSkill(targetSkill);
      final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);
      if (expectedTicks <= 0) continue;

      var xpRate = action.xp / expectedTicks;

      // For consuming actions, cap effective rate by producer throughput.
      // This keeps the heuristic admissible but less wildly optimistic.
      if (action.inputs.isNotEmpty) {
        final producerCap = _computeProducerCapForAction(state, action);
        if (producerCap != null && producerCap < xpRate) {
          xpRate = producerCap;
        }
      }

      if (xpRate > maxRate) {
        maxRate = xpRate;
      }
    }

    return maxRate;
  }

  /// Computes the maximum XP rate a consuming action can sustain based on
  /// producer throughput. Returns null if producers aren't available.
  ///
  /// For each input, finds the best unlocked producer and calculates how fast
  /// inputs can be supplied. The effective XP rate is capped by the slowest
  /// input supply chain.
  double? _computeProducerCapForAction(GlobalState state, SkillAction action) {
    final registries = state.registries;
    double? minCap;

    for (final inputEntry in action.inputs.entries) {
      final inputItemId = inputEntry.key;
      final inputsPerAction = inputEntry.value;

      // Find best producer for this input item
      double bestProducerRate = 0;
      for (final skill in Skill.values) {
        final producerSkillLevel = state.skillState(skill).skillLevel;

        for (final producer in registries.actions.forSkill(skill)) {
          // Only non-consuming, unlocked producers
          if (producer.inputs.isNotEmpty) continue;
          if (producerSkillLevel < producer.unlockLevel) continue;

          // Check if this action produces the needed item
          final outputCount = producer.outputs[inputItemId];
          if (outputCount == null || outputCount <= 0) continue;

          // Calculate producer rate
          final producerTicks = ticksFromDuration(
            producer.meanDuration,
          ).toDouble();
          final modifier = state.shopDurationModifierForSkill(skill);
          final effectiveTicks = producerTicks * (1.0 + modifier);
          if (effectiveTicks <= 0) continue;

          final itemsPerTick = outputCount / effectiveTicks;
          if (itemsPerTick > bestProducerRate) {
            bestProducerRate = itemsPerTick;
          }
        }
      }

      if (bestProducerRate <= 0) {
        // No producer available - can't sustain this action
        return 0;
      }

      // How many consuming actions can we do per tick given producer rate?
      // items/tick from producer / items needed per action = actions/tick
      // actions/tick * XP/action = XP/tick cap
      final actionsPerTick = bestProducerRate / inputsPerAction;
      final xpCap = actionsPerTick * action.xp;

      if (minCap == null || xpCap < minCap) {
        minCap = xpCap;
      }
    }

    return minCap;
  }

  /// Computes the best rate among currently UNLOCKED actions.
  /// Uses the goal to determine which rate type and skills are relevant.
  ///
  /// For consuming skills (Firemaking, Cooking), calculates the sustainable
  /// XP rate based on best consumer+producer pairs, not just raw consume rate.
  /// This ensures the heuristic doesn't return 0 just because inputs
  /// aren't currently in inventory.
  ///
  /// Returns rate and reason if zero.
  _RateResult _computeBestUnlockedRate(GlobalState state) {
    var maxRate = 0.0;
    final registries = state.registries;

    // Track why rate might be zero
    var sawRelevantSkill = false;
    var sawUnlockedAction = false;
    var sawZeroTicks = false;

    // For consuming skills: track first missing producer for better error msg
    String? missingInputName;
    String? actionNeedingInput;
    String? relevantSkillName;

    for (final skill in Skill.values) {
      // Only consider skills relevant to the goal
      if (!goal.isSkillRelevant(skill)) continue;
      sawRelevantSkill = true;
      relevantSkillName ??= skill.name;

      final skillLevel = state.skillState(skill).skillLevel;

      for (final action in registries.actions.forSkill(skill)) {
        // Only consider unlocked actions
        if (skillLevel < action.unlockLevel) continue;

        // Calculate expected ticks with upgrade modifier
        final baseExpectedTicks = ticksFromDuration(
          action.meanDuration,
        ).toDouble();
        final percentModifier = state.shopDurationModifierForSkill(skill);
        final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);
        if (expectedTicks <= 0) {
          sawZeroTicks = true;
          continue;
        }

        // Compute both gold and XP rates, let goal decide which matters
        double goldRate;
        double xpRate;

        if (action is ThievingAction) {
          final thievingLevel = state.skillState(Skill.thieving).skillLevel;
          final mastery = state.actionState(action.id).masteryLevel;
          final stealth = calculateStealth(thievingLevel, mastery);
          final successChance = thievingSuccessChance(
            stealth,
            action.perception,
          );
          final failureChance = 1.0 - successChance;
          final effectiveTicks =
              expectedTicks + failureChance * stunnedDurationTicks;

          // XP is only gained on success
          final expectedXpPerAction = successChance * action.xp;
          xpRate = expectedXpPerAction / effectiveTicks;

          // Gold from thieving
          var expectedGoldPerAction = 0.0;
          for (final output in action.outputs.entries) {
            final item = registries.items.byId(output.key);
            expectedGoldPerAction += item.sellsFor * output.value;
          }
          final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
          expectedGoldPerAction += expectedThievingGold;
          goldRate = expectedGoldPerAction / effectiveTicks;

          // Apply cycle adjustment for death risk
          final expectedDamagePerAttempt =
              failureChance * (1 + action.maxHit) / 2;
          final hpLossPerTick = expectedDamagePerAttempt / effectiveTicks;
          if (hpLossPerTick > 0) {
            final playerHp = state.playerHp;
            final ticksToDeath = ((playerHp - 1) / hpLossPerTick).floor();
            if (ticksToDeath > 0) {
              // With 0 restart overhead, cycleRatio = 1.0 (no penalty yet)
              // When we add restartOverheadTicks, this becomes meaningful
              const restartOverheadTicks = 0;
              final ticksPerCycle = ticksToDeath + restartOverheadTicks;
              final cycleRatio = ticksToDeath.toDouble() / ticksPerCycle;
              goldRate *= cycleRatio;
              xpRate *= cycleRatio;
            }
          }
        } else if (action.inputs.isNotEmpty) {
          // Consuming action (Firemaking, Cooking): compute sustainable rate
          // based on best producer throughput, not raw consume rate.
          final sustainedRate = _computeSustainedRateForConsumingAction(
            state,
            action,
          );
          if (sustainedRate == null || sustainedRate <= 0) {
            // No producer available for this action - capture info for error
            if (missingInputName == null) {
              final inputId = action.inputs.keys.first;
              missingInputName = registries.items.byId(inputId).name;
              actionNeedingInput = action.name;
            }
            continue;
          }
          xpRate = sustainedRate;
          // Gold rate for consuming actions is typically 0 (logs don't sell)
          goldRate = 0;
          sawUnlockedAction = true;
        } else {
          xpRate = action.xp / expectedTicks;

          var expectedGoldPerAction = 0.0;
          for (final output in action.outputs.entries) {
            final item = registries.items.byId(output.key);
            expectedGoldPerAction += item.sellsFor * output.value;
          }
          goldRate = expectedGoldPerAction / expectedTicks;
        }

        sawUnlockedAction = true;

        // Let the goal decide which rate matters
        final rate = goal.activityRate(skill, goldRate, xpRate);
        if (rate > maxRate) {
          maxRate = rate;
        }
      }
    }

    // Determine reason if rate is zero
    if (maxRate <= 0) {
      final goalDesc = goal.describe();
      RateZeroReason reason;
      if (!sawRelevantSkill) {
        reason = NoRelevantSkillReason(goalDesc);
      } else if (!sawUnlockedAction) {
        reason = NoUnlockedActionsReason(
          goalDescription: goalDesc,
          missingInputName: missingInputName,
          actionNeedingInput: actionNeedingInput,
          skillName: relevantSkillName,
        );
      } else if (sawZeroTicks) {
        reason = const ZeroTicksReason();
      } else {
        // Rare: saw unlocked actions but all rates were zero
        reason = NoUnlockedActionsReason(goalDescription: goalDesc);
      }
      return _RateResult(0, zeroReason: reason);
    }

    return _RateResult(maxRate);
  }

  /// Computes the sustainable XP rate for a consuming action.
  ///
  /// For a consuming action (e.g., burning logs, cooking fish), calculates:
  /// - How fast we can produce inputs with the best unlocked producer
  /// - The effective XP/tick accounting for production overhead
  ///
  /// Returns null if no producer is available for the required inputs.
  double? _computeSustainedRateForConsumingAction(
    GlobalState state,
    SkillAction consumeAction,
  ) {
    final registries = state.registries;

    // Get the first input item (logs for firemaking, fish for cooking)
    if (consumeAction.inputs.isEmpty) return null;
    final inputItemId = consumeAction.inputs.keys.first;
    final inputsPerConsumeAction = consumeAction.inputs[inputItemId] ?? 1;

    // Find the best unlocked producer for this input
    double? bestProducerOutputPerTick;
    double? bestProducerTicksPerAction;

    for (final skill in Skill.values) {
      final producerSkillLevel = state.skillState(skill).skillLevel;

      for (final producer in registries.actions.forSkill(skill)) {
        // Only non-consuming, unlocked producers
        if (producer.inputs.isNotEmpty) continue;
        if (producerSkillLevel < producer.unlockLevel) continue;

        // Check if this action produces the needed item
        final outputCount = producer.outputs[inputItemId];
        if (outputCount == null || outputCount <= 0) continue;

        // Calculate producer rate
        final producerBaseTicks = ticksFromDuration(
          producer.meanDuration,
        ).toDouble();
        final modifier = state.shopDurationModifierForSkill(skill);
        final producerTicks = producerBaseTicks * (1.0 + modifier);
        if (producerTicks <= 0) continue;

        final outputPerTick = outputCount / producerTicks;
        if (bestProducerOutputPerTick == null ||
            outputPerTick > bestProducerOutputPerTick) {
          bestProducerOutputPerTick = outputPerTick;
          bestProducerTicksPerAction = producerTicks;
        }
      }
    }

    if (bestProducerOutputPerTick == null ||
        bestProducerTicksPerAction == null) {
      return null; // No producer available
    }

    // Calculate consume action ticks
    final consumeBaseTicks = ticksFromDuration(
      consumeAction.meanDuration,
    ).toDouble();
    final consumeModifier = state.shopDurationModifierForSkill(
      consumeAction.skill,
    );
    final consumeTicks = consumeBaseTicks * (1.0 + consumeModifier);
    if (consumeTicks <= 0) return null;

    // Calculate sustainable XP rate:
    // To do one consume action, we need inputsPerConsumeAction inputs.
    // Producer makes outputPerTick items/tick.
    // So we need (inputsPerConsumeAction / bestProducerOutputPerTick) ticks
    // to produce enough inputs.
    // Total cycle = produce time + consume time
    // XP per cycle = consumeAction.xp
    // Sustained rate = XP / total cycle time

    // How many producer actions needed per consume action?
    // producer outputs `outputCount` per action taking `producerTicks`
    // We get bestProducerOutputPerTick = outputCount / producerTicks
    // To get inputsPerConsumeAction inputs:
    // ticks needed = inputsPerConsumeAction / bestProducerOutputPerTick
    final produceTicksPerCycle =
        inputsPerConsumeAction / bestProducerOutputPerTick;
    final totalTicksPerCycle = produceTicksPerCycle + consumeTicks;

    final sustainedXpPerTick = consumeAction.xp / totalTicksPerCycle;
    return sustainedXpPerTick;
  }
}

/// A* heuristic: optimistic lower bound on ticks to reach goal.
/// Uses best unlocked rate for tighter, state-aware estimates.
/// h(state) = ceil(remaining / R_bestUnlocked)
///
/// For multi-skill goals, returns the SUM of time needed for each skill,
/// since skills must be trained serially (can only do one activity at a time).
/// This is admissible because we can't train two skills simultaneously.
int _heuristic(GlobalState state, Goal goal, _RateCache rateCache) {
  if (goal is MultiSkillGoal) {
    // For multi-skill goals, sum the estimated time for each unfinished skill.
    // This is admissible because skills are trained serially.
    var totalTicks = 0;
    for (final subgoal in goal.subgoals) {
      if (subgoal.isSatisfied(state)) continue;

      final remaining = subgoal.remaining(state);
      if (remaining <= 0) continue;

      // Get best rate for this specific skill
      final bestRate = rateCache.getBestRateForSkill(state, subgoal.skill);
      if (bestRate <= 0) continue;

      final ticks = (remaining / bestRate).ceil();
      totalTicks += ticks;
    }
    return totalTicks;
  }

  // Single goal: use the combined rate
  final bestRate = rateCache.getBestUnlockedRate(state);
  if (bestRate <= 0) return 0; // Fallback to Dijkstra if no rate
  final remaining = goal.remaining(state);
  if (remaining <= 0) return 0;
  return (remaining / bestRate).ceil();
}

/// A node in the search graph.
class _Node {
  _Node({
    required this.state,
    required this.ticks,
    required this.interactions,
    required this.parentId,
    required this.stepFromParent,
    this.expectedDeaths = 0,
  });

  /// The game state at this node.
  final GlobalState state;

  /// Total ticks elapsed to reach this node.
  final int ticks;

  /// Number of interactions taken to reach this node.
  final int interactions;

  /// Index of the parent node in the nodes list, or null for root.
  final int? parentId;

  /// The step taken from parent to reach this node.
  final PlanStep? stepFromParent;

  /// Expected number of deaths to reach this node (from planning model).
  final int expectedDeaths;
}

/// Holds mutable state for the A* solver, avoiding excessive parameter passing.
class _SolverContext {
  _SolverContext({
    required this.initial,
    required this.goal,
    required this.maxExpandedNodes,
    required this.maxQueueSize,
    required this.collectDiagnostics,
    required this.boundaries,
    required this.random,
  }) : rateCache = _RateCache(goal),
       bestCredits = effectiveCredits(initial, const SellAllPolicy());

  final GlobalState initial;
  final Goal goal;
  final int maxExpandedNodes;
  final int maxQueueSize;
  final bool collectDiagnostics;
  final Map<Skill, SkillBoundaries> boundaries;
  final Random random;
  final SolverProfileBuilder profileBuilder = SolverProfileBuilder();
  final _RateCache rateCache;
  final _ParetoFrontier frontier = _ParetoFrontier();
  final List<_Node> nodes = [];
  final HashMap<String, int> bestTicks = HashMap<String, int>();

  late final PriorityQueue<int> pq = PriorityQueue<int>((a, b) {
    final fA = nodes[a].ticks + _heuristic(nodes[a].state, goal, rateCache);
    final fB = nodes[b].ticks + _heuristic(nodes[b].state, goal, rateCache);
    final cmp = fA.compareTo(fB);
    if (cmp != 0) return cmp;
    // Tie-break by lower g (actual ticks)
    return nodes[a].ticks.compareTo(nodes[b].ticks);
  });

  int expandedNodes = 0;
  int enqueuedNodes = 0;
  int bestCredits;

  /// Creates a failure result with the given reason.
  SolverFailed fail(String reason) {
    final profile = profileBuilder.build(
      expandedNodes: expandedNodes,
      frontier: frontier.stats,
    );
    return SolverFailed(
      SolverFailure(
        reason: reason,
        expandedNodes: expandedNodes,
        enqueuedNodes: enqueuedNodes,
        bestCredits: bestCredits,
        reproBundle: ReproBundle(state: initial, goal: goal, reason: reason),
      ),
      profile,
    );
  }

  /// Creates a success result with the given plan and terminal state.
  SolverSuccess succeed(Plan plan, GlobalState terminalState) {
    final profile = profileBuilder.build(
      expandedNodes: expandedNodes,
      frontier: frontier.stats,
      cacheHits: rateCacheHits,
      cacheMisses: rateCacheMisses,
    );
    return SolverSuccess(plan, terminalState, profile);
  }

  /// Tries to enqueue a new node if it's the best path to its state.
  /// Returns true if the node was enqueued.
  bool tryEnqueue({
    required GlobalState state,
    required int ticks,
    required int interactions,
    required int parentId,
    required PlanStep step,
    int expectedDeaths = 0,
  }) {
    final (key: newKey, elapsedUs: elapsed) = _stateKey(state, goal);
    profileBuilder.hashingTimeUs += elapsed;

    final existingBest = bestTicks[newKey];
    if (existingBest != null && ticks >= existingBest) {
      return false;
    }

    bestTicks[newKey] = ticks;
    final newNode = _Node(
      state: state,
      ticks: ticks,
      interactions: interactions,
      parentId: parentId,
      stepFromParent: step,
      expectedDeaths: expectedDeaths,
    );
    final newNodeId = nodes.length;
    nodes.add(newNode);
    pq.add(newNodeId);
    enqueuedNodes++;
    return true;
  }

  /// Records hashing time from a state key computation.
  void recordHashTime(int elapsedUs) {
    profileBuilder.hashingTimeUs += elapsedUs;
  }
}

/// Computes a goal-scoped hash key for a game state for visited tracking.
///
/// Uses bucketed gold for coarser grouping to reduce state explosion.
/// Only includes fields relevant to the goal to avoid unnecessary distinctions.
///
/// ## Design Invariants for Consuming Skills
///
/// When scaling to more consuming skills (Cooking, Smithing, Herblore, etc.),
/// watch for these state explosion risks:
///
/// 1. **Inventory bucket granularity**: The inventory bucket must be coarse
///    enough that small input buffer variations don't create distinct states.
///    Currently uses [_inventoryBucketSize] for large inventories.
///    - BAD: Exact log count creates explosion (10 logs vs 11 logs = 2 states)
///    - GOOD: Bucketed count (0-99 logs vs 100-199 logs = fewer states)
///
/// 2. **Don't encode consumer action choice in key**: The active action is
///    tracked, but the *candidate selection* (which consuming action to do
///    next) should NOT be in the key. The candidate pruning in
///    `_selectConsumingSkillCandidatesWithStats` limits branching instead.
///    - BAD: Key includes "will_burn_willow" vs "will_burn_oak"
///    - GOOD: Key only has current action, candidates are pruned separately
///
/// 3. **Producer skill levels**: For consuming skills, the producer skill
///    level (e.g., Woodcutting for Firemaking) affects sustainable XP rate
///    but is NOT directly in the key. Skill levels are only tracked for
///    goal-relevant skills via [Goal.relevantSkillsForBucketing].
///
/// 4. **Multi-input actions**: Some consuming actions need multiple inputs
///    (e.g., Smithing needs ore + coal). The inventory bucket should aggregate
///    total items, not track each type separately, to avoid combinatorial
///    explosion.
///
/// See also: `_selectConsumingSkillCandidatesWithStats` for candidate pruning.
({String key, int elapsedUs}) _stateKey(GlobalState state, Goal goal) {
  final stopwatch = Stopwatch()..start();
  final buffer = StringBuffer();

  // Bucketed effective credits (GP + sellable inventory value).
  // States with equivalent purchasing power should bucket together.
  final credits = effectiveCredits(state, const SellAllPolicy());
  final goldBucket = credits ~/ _goldBucketSize;
  buffer.write('gb:$goldBucket|');

  // Active action (always tracked for state deduplication)
  final actionId = state.activeAction?.id;
  buffer.write('act:${actionId ?? 'none'}|');

  // HP bucket - only if goal tracks HP (thieving)
  if (goal.shouldTrackHp && actionId != null) {
    final hpBucket = state.playerHp ~/ _hpBucketSize;
    buffer.write('hp:$hpBucket|');
  }

  // Mastery level bucket - only if goal tracks mastery (thieving)
  if (goal.shouldTrackMastery && actionId != null) {
    final masteryLevel = state.actionState(actionId).masteryLevel;
    final masteryBucket = masteryLevel ~/ 10;
    buffer.write('mast:$masteryBucket|');
  }

  // Upgrade levels (always tracked - tool tiers affect rates)
  buffer
    ..write('axe:${state.shop.axeLevel}|')
    ..write('rod:${state.shop.fishingRodLevel}|')
    ..write('pick:${state.shop.pickaxeLevel}|');

  // Skill levels - only goal-relevant skills
  for (final skill in goal.relevantSkillsForBucketing) {
    final level = state.skillState(skill).skillLevel;
    if (level > 1) {
      buffer.write('${skill.name}:$level|');
    }
  }

  // Inventory bucket - only if goal tracks inventory (consuming skills)
  if (goal.shouldTrackInventory) {
    final totalItems = state.inventory.items.fold<int>(
      0,
      (sum, stack) => sum + stack.count,
    );
    if (totalItems > 0) {
      // For small inventories, use exact count; for larger, use buckets
      if (totalItems < 100) {
        buffer.write('inv:$totalItems|');
      } else {
        final invBucket = totalItems ~/ _inventoryBucketSize;
        buffer.write('inv:$invBucket|');
      }
    }
  }

  return (key: buffer.toString(), elapsedUs: stopwatch.elapsedMicroseconds);
}

/// Checks if an activity can be modeled with expected-value rates.
/// Returns true for non-combat skill activities (including consuming actions).
bool _isRateModelable(GlobalState state) {
  final activeAction = state.activeAction;
  if (activeAction == null) return false;

  final action = state.registries.actions.byId(activeAction.id);

  // Only skill actions (non-combat) are rate-modelable
  if (action is! SkillAction) return false;

  return true;
}

/// Result of advancing expected state.
typedef AdvanceResult = ({GlobalState state, int deaths});

/// O(1) expected-value fast-forward for rate-modelable activities.
/// Updates gold and skill XP based on expected rates without full simulation.
///
/// For thieving (activities with death risk), uses a continuous model that
/// incorporates death cycles into the effective rates. This avoids discrete
/// death events that would require activity restarts and cause solver churn.
///
/// Returns the new state and the number of expected deaths.
AdvanceResult _advanceExpected(GlobalState state, int deltaTicks) {
  _assertNonNegativeDelta(deltaTicks, '_advanceExpected');
  _assertValidState(state);

  if (deltaTicks <= 0) return (state: state, deaths: 0);

  final rawRates = estimateRates(state);

  // For activities with death risk, use cycle-adjusted rates.
  // This models the long-run average including death/restart cycles,
  // avoiding discrete death events that would stop the activity.
  final ticksToDeath = ticksUntilDeath(state, rawRates);
  final hasDeathRisk = ticksToDeath != null && ticksToDeath > 0;

  // Use cycle-adjusted rates if there's death risk, otherwise raw rates
  final rates = hasDeathRisk
      ? deathCycleAdjustedRates(state, rawRates)
      : rawRates;

  // GP is NOT updated from item production. Items stay as items in inventory
  // until explicitly sold via SellItems interaction.
  //
  // For affordability checks during planning, use effectiveCredits(state,
  // policy) which computes: state.gp + sellableValue(inventory).
  //
  // This ensures GlobalState.gp always represents actual GP, matching
  // execution.
  final newGp = state.gp;

  // Compute expected skill XP gains
  final newSkillStates = Map<Skill, SkillState>.from(state.skillStates);
  for (final entry in rates.xpPerTickBySkill.entries) {
    final skill = entry.key;
    final xpPerTick = entry.value;
    final xpGain = (xpPerTick * deltaTicks).floor();
    if (xpGain > 0) {
      final current = state.skillState(skill);
      final newXp = current.xp + xpGain;
      newSkillStates[skill] = current.copyWith(xp: newXp);
    }
  }

  // Compute expected mastery XP gains
  var newActionStates = state.actionStates;
  if (rates.masteryXpPerTick > 0 && rates.actionId != null) {
    final masteryXpGain = (rates.masteryXpPerTick * deltaTicks).floor();
    if (masteryXpGain > 0) {
      final actionId = rates.actionId!;
      final currentActionState = state.actionState(actionId);
      final newMasteryXp = currentActionState.masteryXp + masteryXpGain;
      newActionStates = Map.from(state.actionStates);
      newActionStates[actionId] = currentActionState.copyWith(
        masteryXp: newMasteryXp,
      );
    }
  }

  // Estimate expected deaths during this period (for tracking/display)
  final expectedDeaths = hasDeathRisk ? deltaTicks ~/ ticksToDeath : 0;

  // Build currencies map with updated GP
  final newCurrencies = Map<Currency, int>.from(state.currencies);
  newCurrencies[Currency.gp] = newGp;

  // Update inventory with expected item gains
  // This is important for consuming skills where items need to be tracked
  // Skip items not in the registry (e.g., skill drops like Ash)
  var newInventory = state.inventory;
  for (final entry in rates.itemFlowsPerTick.entries) {
    final itemId = entry.key;
    final flowRate = entry.value;
    final expectedCount = (flowRate * deltaTicks).floor();
    if (expectedCount > 0) {
      final item = state.registries.items.byId(itemId);
      newInventory = newInventory.adding(ItemStack(item, count: expectedCount));
    }
  }

  // Subtract consumed items
  for (final entry in rates.itemsConsumedPerTick.entries) {
    final itemId = entry.key;
    final consumeRate = entry.value;
    final consumedCount = (consumeRate * deltaTicks).floor();
    if (consumedCount > 0) {
      final item = state.registries.items.byId(itemId);
      newInventory = newInventory.removing(
        ItemStack(item, count: consumedCount),
      );
    }
  }

  // Note: HP is not tracked in the continuous model - death cycles are
  // absorbed into the rate adjustment. Activity continues without stopping.
  final newState = state.copyWith(
    currencies: newCurrencies,
    skillStates: newSkillStates,
    actionStates: newActionStates,
    inventory: newInventory,
  );

  _assertValidState(newState);
  _assertMonotonicProgress(state, newState, '_advanceExpected');

  return (state: newState, deaths: expectedDeaths);
}

/// Advances the game state by a given number of ticks.
/// Uses O(1) expected-value advance for rate-modelable activities,
/// falls back to full simulation for combat/complex activities.
///
/// Only should be used for planning, since it will not perfectly match
/// game state (e.g. won't add inventory items)
///
/// Returns the new state and the number of expected deaths.
AdvanceResult advance(
  GlobalState state,
  int deltaTicks, {
  required Random random,
}) {
  _assertNonNegativeDelta(deltaTicks, 'advance');
  _assertValidState(state);

  if (deltaTicks <= 0) return (state: state, deaths: 0);

  final AdvanceResult result;
  if (_isRateModelable(state)) {
    result = _advanceExpected(state, deltaTicks);
  } else {
    result = (
      state: advanceFullSim(state, deltaTicks, random: random),
      deaths: 0,
    );
  }

  _assertValidState(result.state);
  _assertMonotonicProgress(state, result.state, 'advance');
  return result;
}

/// Result of consuming ticks until a goal is reached.
class ConsumeUntilResult {
  ConsumeUntilResult({
    required this.state,
    required this.ticksElapsed,
    required this.deathCount,
    this.boundary,
  }) {
    _assertValidState(state);
  }

  final GlobalState state;
  final int ticksElapsed;
  final int deathCount;

  /// The boundary that caused execution to pause, or null if the wait
  /// condition was satisfied normally.
  ///
  /// Expected boundaries (like [InputsDepleted]) are part of normal online
  /// execution. Unexpected boundaries may indicate bugs.
  final ReplanBoundary? boundary;
}

/// Finds actions that produce the input items for a consuming action.
///
/// Returns a list of producer actions that:
/// - Output at least one of the consuming action's required inputs
/// - Can be started with current resources
/// - Are unlocked (player meets level requirements for the producer skill)
/// - Sorted by production rate (prefer faster producers)
///
/// Returns empty list if no suitable producers exist.
List<SkillAction> _findProducersFor(
  GlobalState state,
  SkillAction consumingAction,
  ActionRegistry actionRegistry,
) {
  final producers = <SkillAction>[];

  // For each input item the consumer needs
  for (final inputItemId in consumingAction.inputs.keys) {
    // Find all actions that output this item
    for (final action in actionRegistry.all) {
      if (action is! SkillAction) continue;
      if (!action.outputs.containsKey(inputItemId)) continue;

      // Check if producer is unlocked for its skill
      final producerSkillLevel = state.skillState(action.skill).skillLevel;
      if (action.unlockLevel > producerSkillLevel) continue;

      // Check if we can start this producer (has no missing inputs)
      if (!state.canStartAction(action)) continue;

      producers.add(action);
    }
  }

  // Sort by production rate (items per tick) for the required input
  producers.sort((a, b) {
    final inputItemId = consumingAction.inputs.keys.first;
    final aRate = a.expectedOutputPerTick(inputItemId);
    final bRate = b.expectedOutputPerTick(inputItemId);
    // Higher is better.
    return bRate.compareTo(aRate);
  });

  return producers;
}

/// Advances state until a condition is satisfied.
///
/// Uses [consumeTicksUntil] to efficiently process ticks, checking the
/// condition after each action iteration. Automatically restarts the activity
/// after death and tracks how many deaths occurred.
///
/// Returns the final state, actual ticks elapsed, death count, and any
/// [ReplanBoundary] that caused execution to pause.
///
/// ## Boundary Handling
///
/// - [Death]: Auto-restarts the activity and continues (expected)
/// - [InputsDepleted]: For consuming actions, switches to producer to gather
///   more inputs, then continues (expected)
/// - [InventoryFull]: Returns with boundary set (caller decides what to do)
/// - [WaitConditionSatisfied]: Normal completion, boundary is null
///
/// Unexpected boundaries indicate potential bugs in the planner.
ConsumeUntilResult consumeUntil(
  GlobalState originalState,
  WaitFor waitFor, {
  required Random random,
}) {
  _assertValidState(originalState);

  var state = originalState;
  if (waitFor.isSatisfied(state)) {
    // Already satisfied - return immediately with 0 ticks elapsed.
    // This can happen when a previous step in the plan already satisfied
    // the condition (e.g., multiple macros targeting the same boundary).
    return ConsumeUntilResult(
      state: state,
      ticksElapsed: 0,
      deathCount: 0,
      boundary: const WaitConditionSatisfied(),
    );
  }

  final originalActivityId = state.activeAction?.id;
  var totalTicksElapsed = 0;
  var deathCount = 0;

  // Keep running until the condition is satisfied, restarting after deaths
  while (true) {
    final builder = StateUpdateBuilder(state);
    final progressBefore = waitFor.progress(state);

    // Use consumeTicksUntil which checks the condition after each action
    final stopReason = consumeTicksUntil(
      builder,
      random: random,
      stopCondition: (s) => waitFor.isSatisfied(s),
    );

    state = builder.build();
    totalTicksElapsed += builder.ticksElapsed;

    // If we hit maxTicks without progress, we're stuck
    if (stopReason == ConsumeTicksStopReason.maxTicksReached) {
      final progressAfter = waitFor.progress(state);
      if (progressAfter <= progressBefore) {
        return ConsumeUntilResult(
          state: state,
          ticksElapsed: totalTicksElapsed,
          deathCount: deathCount,
          boundary: NoProgressPossible(
            reason:
                'Hit maxTicks (10h) with no progress on '
                '${waitFor.describe()}',
          ),
        );
      }
      // Made some progress but not enough - continue
    }

    // Check if we're done
    if (waitFor.isSatisfied(state)) {
      return ConsumeUntilResult(
        state: state,
        ticksElapsed: totalTicksElapsed,
        deathCount: deathCount,
        boundary: const WaitConditionSatisfied(),
      );
    }

    // Check if activity stopped
    if (builder.stopReason != ActionStopReason.stillRunning) {
      if (builder.stopReason == ActionStopReason.playerDied) {
        deathCount++;

        // Auto-restart the activity after death and continue (expected)
        if (originalActivityId != null) {
          final action = state.registries.actions.byId(originalActivityId);
          state = state.startAction(action, random: random);
          continue; // Continue with restarted activity
        }
        // No activity to restart - return with death boundary
        return ConsumeUntilResult(
          state: state,
          ticksElapsed: totalTicksElapsed,
          deathCount: deathCount,
          boundary: const Death(),
        );
      }

      // For other stop reasons (outOfInputs, inventoryFull), try to adapt.
      // For skill goals with consuming actions, switch to producer to gather
      // inputs.
      if (waitFor is WaitForSkillXp && originalActivityId != null) {
        final currentAction = state.registries.actions.byId(originalActivityId);

        // Check if this is a consuming action (has inputs)
        if (currentAction is SkillAction && currentAction.inputs.isNotEmpty) {
          // Find producers for the inputs this action needs
          final producers = _findProducersFor(
            state,
            currentAction,
            state.registries.actions,
          );

          if (producers.isNotEmpty) {
            final producer = producers.first;
            final inputItemId = currentAction.inputs.keys.first;

            // Calculate buffer: enough to consume for ~5 minutes
            final consumptionRate = currentAction.inputs.values.first;
            final ticksPerConsume =
                (currentAction.minDuration.inMilliseconds /
                        Duration.millisecondsPerSecond *
                        10)
                    .round();
            const bufferTicks = 3000; // 5 minutes at 100ms/tick
            final bufferCount =
                ((bufferTicks / ticksPerConsume) * consumptionRate).ceil();

            // Switch to producer (this is an expected InputsDepleted boundary)
            state = state.startAction(producer, random: random);

            // Gather inputs
            final gatherResult = consumeUntil(
              state,
              WaitForInventoryAtLeast(inputItemId, bufferCount),
              random: random,
            );
            state = gatherResult.state;
            totalTicksElapsed += gatherResult.ticksElapsed;
            deathCount += gatherResult.deathCount;

            // Try to switch back to consumer
            try {
              state = state.startAction(currentAction, random: random);
              continue; // Continue consuming
            } on Exception {
              // Can't restart consumer (still missing inputs) - fall through
              // to return the boundary
            }
          }
        }
      }

      // Cannot adapt - return with the boundary that caused the stop
      final inputItemId = originalActivityId != null
          ? () {
              final action = state.registries.actions.byId(originalActivityId);
              if (action is SkillAction && action.inputs.isNotEmpty) {
                return action.inputs.keys.first;
              }
              return null;
            }()
          : null;

      final boundary = boundaryFromStopReason(
        builder.stopReason,
        actionId: originalActivityId,
        missingItemId: inputItemId,
      );

      return ConsumeUntilResult(
        state: state,
        ticksElapsed: totalTicksElapsed,
        deathCount: deathCount,
        boundary: boundary,
      );
    }

    // No progress possible
    if (builder.ticksElapsed == 0 && state.activeAction == null) {
      return ConsumeUntilResult(
        state: state,
        ticksElapsed: totalTicksElapsed,
        deathCount: deathCount,
        boundary: const NoProgressPossible(reason: 'No active action'),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Macro Expansion
// ---------------------------------------------------------------------------

// BatchSizeResult is now defined in solver_context.dart

// MacroExpansionResult, MacroExpansionOutcome, MacroExpanded,
// MacroAlreadySatisfied, MacroCannotExpand are now in macro_candidate.dart
// BatchSizeResult, _computeFeasibleBatchSize, _quantizeStockTarget,
// _computeBatchToNextUnlock, _estimateNewSlotsForProduction are now methods
// on SolverContext in solver_context.dart

// ---------------------------------------------------------------------------
// Explain One Expansion - debugging tool for understanding macro decisions
// ---------------------------------------------------------------------------

/// Detailed explanation of a macro expansion for debugging.
class MacroExpansionExplanation {
  MacroExpansionExplanation({
    required this.macro,
    required this.outcome,
    required this.steps,
  });

  /// The macro being explained.
  final MacroCandidate macro;

  /// The outcome of the expansion.
  final MacroExpansionOutcome outcome;

  /// Step-by-step explanation of what happened.
  final List<String> steps;

  /// Formats the explanation as a multi-line string.
  String format() {
    final buffer = StringBuffer()
      ..writeln('=== Macro Expansion Explanation ===')
      ..writeln('Macro: ${_describeMacro(macro)}');
    if (macro.provenance != null) {
      buffer.writeln('Provenance: ${macro.provenance!.describe()}');
    }
    buffer
      ..writeln()
      ..writeln('Steps:');
    for (var i = 0; i < steps.length; i++) {
      buffer.writeln('  ${i + 1}. ${steps[i]}');
    }
    buffer
      ..writeln()
      ..writeln('Outcome: ${_describeOutcome(outcome)}');
    return buffer.toString();
  }

  static String _describeMacro(MacroCandidate macro) {
    return switch (macro) {
      TrainSkillUntil(:final skill, :final primaryStop) =>
        'TrainSkillUntil(${skill.name}, ${primaryStop.runtimeType})',
      TrainConsumingSkillUntil(:final consumingSkill, :final primaryStop) =>
        'TrainConsumingSkillUntil(${consumingSkill.name}, '
            '${primaryStop.runtimeType})',
      AcquireItem(:final itemId, :final quantity) =>
        'AcquireItem(${itemId.localId}, $quantity)',
      EnsureStock(:final itemId, :final minTotal) =>
        'EnsureStock(${itemId.localId}, $minTotal)',
    };
  }

  static String _describeOutcome(MacroExpansionOutcome outcome) {
    return switch (outcome) {
      MacroExpanded(:final result) =>
        'SUCCESS: ${result.ticksElapsed} ticks, '
            'trigger=${result.triggeringCondition}',
      MacroAlreadySatisfied(:final reason) => 'ALREADY_SATISFIED: $reason',
      MacroCannotExpand(:final reason) => 'CANNOT_EXPAND: $reason',
    };
  }
}

/// Explains the expansion of a macro with detailed step-by-step output.
///
/// This is a debugging tool that traces through the expansion logic and
/// records what decisions were made and why. Useful for understanding
/// why a macro expanded in a particular way.
MacroExpansionExplanation explainMacroExpansion(
  GlobalState state,
  MacroCandidate macro,
  Goal goal, {
  required Random random,
}) {
  final steps = <String>[];
  final boundaries = computeUnlockBoundaries(state.registries);

  // Trace through the expansion based on macro type
  switch (macro) {
    case TrainSkillUntil(:final skill):
      steps.add('Looking for best action for ${skill.name}');
      final bestAction = _findBestActionForSkill(state, skill, goal);
      if (bestAction == null) {
        steps.add('No unlocked action found for ${skill.name}');
      } else {
        steps.add('Best action: $bestAction');
        final rates = estimateRates(state);
        steps.add(
          'XP rate: ${rates.xpPerTickBySkill[skill]?.toStringAsFixed(3)} '
          'XP/tick',
        );
      }

    case TrainConsumingSkillUntil(:final consumingSkill):
      steps.add('Looking for best consuming action for ${consumingSkill.name}');
      final bestAction = _findBestActionForSkill(state, consumingSkill, goal);
      if (bestAction == null) {
        steps.add('No unlocked action found');
      } else {
        steps.add('Best consuming action: $bestAction');
        final action = state.registries.actions.byId(bestAction);
        if (action is SkillAction && action.inputs.isNotEmpty) {
          steps.add('Inputs required: ${action.inputs}');
          for (final input in action.inputs.entries) {
            final item = state.registries.items.byId(input.key);
            final count = state.inventory.countOfItem(item);
            steps.add(
              '  ${input.key.localId}: have $count, need ${input.value}',
            );
          }
        }
      }

    case AcquireItem(:final itemId, quantity: _):
      steps.add('Looking for producer of ${itemId.localId}');
      final producer = _findProducerActionForItem(state, itemId, goal);
      if (producer == null) {
        final locked = _findAnyProducerForItem(state, itemId);
        if (locked != null) {
          steps.add(
            'Found locked producer: $locked (needs ${locked.skill.name} '
            'L${locked.unlockLevel})',
          );
        } else {
          steps.add('No producer found for ${itemId.localId}');
        }
      } else {
        steps.add('Found producer: $producer');
        final prereqResult = _ensureExecutable(state, producer, goal);
        steps.add('Prerequisites: ${prereqResult.runtimeType}');
      }

    case EnsureStock(:final itemId, :final minTotal):
      final item = state.registries.items.byId(itemId);
      final currentCount = state.inventory.countOfItem(item);
      steps.add(
        'Checking stock of ${itemId.localId}: have $currentCount, '
        'need $minTotal',
      );
      if (currentCount >= minTotal) {
        steps.add('Already have enough - no action needed');
      } else {
        final delta = minTotal - currentCount;
        steps.add('Need to produce $delta more');
        final producer = _findProducerActionForItem(state, itemId, goal);
        if (producer != null) {
          steps.add('Found producer: $producer');
        }
      }
  }

  // Actually perform the expansion
  final outcome = _expandMacro(state, macro, goal, boundaries, random: random);
  steps.add('Expansion complete');

  return MacroExpansionExplanation(
    macro: macro,
    outcome: outcome,
    steps: steps,
  );
}

/// Expands a macro candidate into a future state by estimating progress.
///
/// Uses expected-value modeling (same as `advance`) to project forward
/// until ANY of the macro's stop conditions would trigger.
///
/// Returns [MacroExpanded] on success, [MacroAlreadySatisfied] if no work
/// needed, or [MacroCannotExpand] with a reason if expansion is impossible.
MacroExpansionOutcome _expandMacro(
  GlobalState state,
  MacroCandidate macro,
  Goal goal,
  Map<Skill, SkillBoundaries> boundaries, {
  required Random random,
}) {
  final context = MacroExpansionContext(
    state: state,
    goal: goal,
    boundaries: boundaries,
    random: random,
  );
  return macro.expand(context);
}

/// Finds an action that produces the given item.
ActionId? _findProducerActionForItem(
  GlobalState state,
  MelvorId item,
  Goal goal,
) {
  int skillLevel(Skill skill) => state.skillState(skill).skillLevel;

  // Find all actions that produce this item
  final producers = state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.outputs.containsKey(item))
      .where((action) => action.unlockLevel <= skillLevel(action.skill));

  if (producers.isEmpty) return null;

  // Rank by production rate (outputs per tick)
  // Producer actions (woodcutting, fishing, mining) don't require inputs,
  // so we can directly calculate rates without testing applyInteraction.
  ActionId? best;
  double bestRate = 0;

  for (final action in producers) {
    final ticksPerAction = ticksFromDuration(action.meanDuration).toDouble();
    final outputsPerAction = action.outputs[item] ?? 1;
    final outputsPerTick = outputsPerAction / ticksPerAction;

    if (outputsPerTick > bestRate) {
      bestRate = outputsPerTick;
      best = action.id;
    }
  }

  return best;
}

/// Finds an action that produces the given item, even if locked.
///
/// Returns null if no action produces this item at all.
/// Unlike [_findProducerActionForItem], this finds producers regardless
/// of skill level requirements.
SkillAction? _findAnyProducerForItem(GlobalState state, MelvorId item) {
  return state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.outputs.containsKey(item))
      .firstOrNull;
}

// EnsureExecResult, ExecReady, ExecNeedsMacros, ExecUnknown are now in
// solver_context.dart

/// Deduplicates macros, keeping first occurrence of each unique macro.
List<MacroCandidate> _dedupeMacros(List<MacroCandidate> macros) {
  final seen = <String>{};
  final result = <MacroCandidate>[];
  for (final macro in macros) {
    if (seen.add(macro.dedupeKey)) result.add(macro);
  }
  return result;
}

/// Returns prerequisite check result for an action.
///
/// Checks:
/// 1. Skill level requirements - generates TrainSkillUntil if action is locked
/// 2. Input requirements - recursively checks producers for each input
///
/// Returns [ExecReady] if action can execute now, [ExecNeedsMacros] if
/// prerequisites are needed, or [ExecUnknown] if we can't determine how
/// to make the action feasible (e.g., no producer exists, cycle detected).
EnsureExecResult _ensureExecutable(
  GlobalState state,
  ActionId actionId,
  Goal goal, {
  int depth = 0,
  int maxDepth = 8,
  Set<ActionId>? visited,
}) {
  visited ??= <ActionId>{};
  if (!visited.add(actionId)) {
    return ExecUnknown('cycle: $actionId');
  }
  if (depth >= maxDepth) {
    return ExecUnknown('depth limit: $actionId');
  }

  final action = state.registries.actions.byId(actionId);
  if (action is! SkillAction) return const ExecReady();

  final macros = <MacroCandidate>[];

  // 1. Check skill level requirement
  final currentLevel = state.skillState(action.skill).skillLevel;
  if (action.unlockLevel > currentLevel) {
    macros.add(
      TrainSkillUntil(
        action.skill,
        StopAtLevel(action.skill, action.unlockLevel),
      ),
    );
  }

  // 2. Check inputs - recursively ensure each can be produced
  // NOTE: We only check feasibility (skill unlocks), NOT stocking.
  // Stocking amounts should be determined by the caller with proper batch
  // sizing, not here with minimal amounts that cause plan thrash.
  for (final inputId in action.inputs.keys) {
    final inputCount = action.inputs[inputId]!;
    final inputItem = state.registries.items.byId(inputId);
    final currentCount = state.inventory.countOfItem(inputItem);

    // If we already have enough of this input, no prereq needed
    if (currentCount >= inputCount) continue;

    // First check if there's an unlocked producer
    final producer = _findProducerActionForItem(state, inputId, goal);
    if (producer != null) {
      // Producer exists and is unlocked, check its prerequisites
      final result = _ensureExecutable(
        state,
        producer,
        goal,
        depth: depth + 1,
        maxDepth: maxDepth,
        visited: visited,
      );
      switch (result) {
        case ExecReady():
          break; // Producer is ready
        case ExecNeedsMacros(macros: final producerMacros):
          macros.addAll(producerMacros);
        case ExecUnknown(:final reason):
          return ExecUnknown('input $inputId blocked: $reason');
      }
      // NOTE: We do NOT add EnsureStock here. The caller (e.g.,
      // _expandEnsureStock) handles stocking with proper batch sizing.
      // Adding small EnsureStock prereqs here causes plan thrash.
    } else {
      // No unlocked producer - check if one exists but is locked
      final lockedProducer = _findAnyProducerForItem(state, inputId);
      if (lockedProducer == null) {
        return ExecUnknown('no producer for $inputId');
      }
      // Producer exists but is locked - need to train that skill
      final neededLevel = lockedProducer.unlockLevel;
      macros.add(
        TrainSkillUntil(
          lockedProducer.skill,
          StopAtLevel(lockedProducer.skill, neededLevel),
        ),
      );
      // NOTE: We do NOT add EnsureStock here. After training, the caller
      // will handle stocking with proper batch sizing.
    }
  }

  return macros.isEmpty
      ? const ExecReady()
      : ExecNeedsMacros(_dedupeMacros(macros));
}

/// Finds the best action for a skill based on the goal's criteria.
///
/// For skill goals, picks the action with highest XP rate.
/// For GP goals, picks the action with highest gold rate.
///
/// Unlike `estimateRates`, this function doesn't require the action to be
/// startable. This is important for consuming skills where we want to find
/// the best action even when inputs aren't currently available (because we'll
/// produce them next).
///
/// For consuming actions, this also checks that we can produce the inputs.
ActionId? _findBestActionForSkill(GlobalState state, Skill skill, Goal goal) {
  final skillLevel = state.skillState(skill).skillLevel;
  final actions = state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.skill == skill)
      .where((action) => action.unlockLevel <= skillLevel);

  if (actions.isEmpty) return null;

  // Rank by goal-specific rate
  ActionId? best;
  double bestRate = 0;

  // Check if this skill is relevant to the goal. If not (e.g., training Mining
  // as a prerequisite for Smithing), use raw XP rate instead of goal rate.
  final skillIsGoalRelevant = goal.isSkillRelevant(skill);

  actionLoop:
  for (final action in actions) {
    // For consuming actions, check that ALL inputs can be produced
    // (either directly or via prerequisite training).
    // This handles multi-input actions like Mithril Bar (Mithril Ore + Coal).
    if (action.inputs.isNotEmpty) {
      for (final inputItem in action.inputs.keys) {
        // Check if any producer exists (locked or unlocked)
        final anyProducer = _findAnyProducerForItem(state, inputItem);
        if (anyProducer == null) {
          // No way to produce this input at all, skip this action
          continue actionLoop;
        }
      }
    }

    // Use estimateRatesForAction which doesn't require the action to be active
    // or have inputs available. This allows planning for consuming actions
    // before inputs are produced.
    final rates = estimateRatesForAction(state, action.id);

    final goldRate = defaultValueModel.valuePerTick(state, rates);
    final xpRate = rates.xpPerTickBySkill[skill] ?? 0.0;

    // For prerequisite training (skill not in goal), use raw XP rate
    // to pick the fastest training action.
    final rate = skillIsGoalRelevant
        ? goal.activityRate(skill, goldRate, xpRate)
        : xpRate;

    if (rate > bestRate) {
      bestRate = rate;
      best = action.id;
    }
  }

  return best;
}

// ---------------------------------------------------------------------------
// Solver edge expansion helpers
// ---------------------------------------------------------------------------

/// Expands interaction edges (0 time cost) from the given node.
/// Returns the number of neighbors generated.
int _expandInteractionEdges(
  _SolverContext ctx,
  _Node node,
  int nodeId,
  Candidates candidates,
  List<Interaction> interactions,
) {
  var neighborsGenerated = 0;

  for (final interaction in interactions) {
    if (!candidates.isRelevantInteraction(interaction)) continue;

    try {
      final newState = applyInteraction(node.state, interaction);
      final newProgress = ctx.goal.progress(newState);
      final newBucketKey = _BucketKey.fromState(newState, ctx.goal);

      // Dominance pruning: skip if dominated by existing frontier point
      if (ctx.frontier.isDominatedOrInsert(
        newBucketKey,
        node.ticks,
        newProgress,
      )) {
        ctx.profileBuilder.dominatedSkipped++;
        continue;
      }

      if (ctx.tryEnqueue(
        state: newState,
        ticks: node.ticks, // Interactions cost 0 ticks
        interactions: node.interactions + 1,
        parentId: nodeId,
        step: InteractionStep(interaction),
      )) {
        neighborsGenerated++;
      }
    } on Exception catch (_) {
      // Interaction failed (e.g., can't afford upgrade) - skip
      continue;
    }
  }

  return neighborsGenerated;
}

/// Expands macro edges (train skill until boundary/goal) from the given node.
/// Returns a success result if goal was reached, otherwise returns null
/// and the number of neighbors generated via the out parameter.
SolverSuccess? _expandMacroEdges(
  _SolverContext ctx,
  _Node node,
  int nodeId,
  Candidates candidates, {
  required _NeighborCounter counter,
}) {
  for (final macro in candidates.macros) {
    final expansionOutcome = _expandMacro(
      node.state,
      macro,
      ctx.goal,
      ctx.boundaries,
      random: ctx.random,
    );

    // Skip macros that can't be expanded or are already satisfied
    final MacroExpansionResult expansionResult;
    switch (expansionOutcome) {
      case MacroExpanded(:final result):
        expansionResult = result;
      case MacroAlreadySatisfied():
      case MacroCannotExpand():
        continue;
    }

    // Record which condition triggered the macro stop
    if (expansionResult.triggeringCondition != null) {
      ctx.profileBuilder.recordMacroStopTrigger(
        expansionResult.triggeringCondition!,
      );
    }

    final newState = expansionResult.state;
    final newDeaths = node.expectedDeaths + expansionResult.deaths;
    final newTicks = node.ticks + expansionResult.ticksElapsed;
    final newProgress = ctx.goal.progress(newState);
    final newBucketKey = _BucketKey.fromState(newState, ctx.goal);

    // Check if we've reached the goal
    final reachedGoal = ctx.goal.isSatisfied(newState);

    // Dominance pruning: skip if dominated unless we reached the goal
    if (!reachedGoal &&
        ctx.frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress)) {
      ctx.profileBuilder.dominatedSkipped++;
      continue;
    }

    // Add to frontier if reached goal
    if (reachedGoal) {
      ctx.frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress);
    }

    final (key: newKey, elapsedUs: macroElapsedUs) = _stateKey(
      newState,
      ctx.goal,
    );
    ctx.recordHashTime(macroElapsedUs);

    // Only enqueue if this is the best path to this state
    final existingBest = ctx.bestTicks[newKey];
    if (existingBest == null || newTicks < existingBest) {
      ctx.bestTicks[newKey] = newTicks;

      final newNode = _Node(
        state: newState,
        ticks: newTicks,
        interactions: node.interactions,
        expectedDeaths: newDeaths,
        parentId: nodeId,
        stepFromParent: MacroStep(
          expansionResult.macro,
          expansionResult.ticksElapsed,
          expansionResult.waitFor,
        ),
      );

      final newNodeId = ctx.nodes.length;
      ctx.nodes.add(newNode);

      if (reachedGoal) {
        // Found goal via macro - return immediately
        return ctx.succeed(
          _reconstructPlan(
            ctx.nodes,
            newNodeId,
            ctx.expandedNodes,
            ctx.enqueuedNodes,
            goal: ctx.goal,
          ),
          newState,
        );
      }

      ctx.pq.add(newNodeId);
      ctx.enqueuedNodes++;
      counter.value++;
    }
  }

  return null;
}

/// Expands the wait edge from the given node.
/// Returns a success result if goal was reached, otherwise null.
SolverSuccess? _expandWaitEdge(
  _SolverContext ctx,
  _Node node,
  int nodeId,
  String nodeKey,
  Candidates candidates,
  List<Interaction> interactions, {
  required _NeighborCounter counter,
}) {
  // For segment goals, use the WatchSet's sellPolicy for consistent
  // effectiveCredits calculation. Otherwise use candidates.sellPolicy.
  final deltaSellPolicy = ctx.goal is SegmentGoal
      ? (ctx.goal as SegmentGoal).watchSet.sellPolicy
      : candidates.sellPolicy;
  final deltaResult = nextDecisionDelta(
    node.state,
    ctx.goal,
    candidates,
    sellPolicy: deltaSellPolicy,
  );

  // Invariant: dt=0 only when actions exist, dt>0 when no immediate actions.
  final relevantInteractions = interactions
      .where(candidates.isRelevantInteraction)
      .toList();
  assert(
    deltaResult.deltaTicks != 0 || relevantInteractions.isNotEmpty,
    'dt=0 but no actions; watch ≠ action regression',
  );

  if (deltaResult.isDeadEnd || deltaResult.deltaTicks <= 0) {
    return null;
  }

  ctx.profileBuilder.decisionDeltas.add(deltaResult.deltaTicks);

  final advanceStopwatch = Stopwatch()..start();
  final advanceResult = advance(
    node.state,
    deltaResult.deltaTicks,
    random: ctx.random,
  );
  ctx.profileBuilder.advanceTimeUs += advanceStopwatch.elapsedMicroseconds;

  final newState = advanceResult.state;
  final newDeaths = node.expectedDeaths + advanceResult.deaths;
  final newTicks = node.ticks + deltaResult.deltaTicks;
  final newProgress = ctx.goal.progress(newState);
  final newBucketKey = _BucketKey.fromState(newState, ctx.goal);

  // Check if we've reached the goal BEFORE dominance pruning
  final reachedGoal = ctx.goal.isSatisfied(newState);

  // Dominance pruning: skip if dominated by existing frontier point
  // BUT: never skip if we've reached the goal
  if (!reachedGoal &&
      ctx.frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress)) {
    ctx.profileBuilder.dominatedSkipped++;
    return null;
  }

  // If we reached goal, still add to frontier for tracking
  if (reachedGoal) {
    ctx.frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress);
  }

  final (key: newKey, elapsedUs: waitElapsedUs) = _stateKey(newState, ctx.goal);
  ctx.recordHashTime(waitElapsedUs);

  // Safety: check for zero-progress waits (same state key after advance)
  // BUT: allow if we've reached the goal (even if state key unchanged)
  if (newKey == nodeKey && !reachedGoal) {
    return null;
  }

  final existingBest = ctx.bestTicks[newKey];
  // Add if we've reached the goal (this is the terminal state we want)
  // Otherwise, only add if this is a better path to this state key
  if (!reachedGoal && existingBest != null && newTicks >= existingBest) {
    return null;
  }

  if (!reachedGoal) {
    ctx.bestTicks[newKey] = newTicks;
  }

  final newNode = _Node(
    state: newState,
    ticks: newTicks,
    interactions: node.interactions,
    parentId: nodeId,
    stepFromParent: WaitStep(
      deltaResult.deltaTicks,
      deltaResult.waitFor,
      expectedAction: deltaResult.intendedAction,
    ),
    expectedDeaths: newDeaths,
  );

  final newNodeId = ctx.nodes.length;
  ctx.nodes.add(newNode);

  if (reachedGoal) {
    return ctx.succeed(
      _reconstructPlan(
        ctx.nodes,
        newNodeId,
        ctx.expandedNodes,
        ctx.enqueuedNodes,
        goal: ctx.goal,
      ),
      newState,
    );
  }

  ctx.pq.add(newNodeId);
  ctx.enqueuedNodes++;
  counter.value++;

  return null;
}

/// Simple mutable counter for tracking neighbors across helper calls.
class _NeighborCounter {
  int value = 0;
}

/// Validates initial state and sets up the root node.
/// Returns early success/failure result if applicable, otherwise null.
SolverResult? _initializeSolver(_SolverContext ctx) {
  // Clear the internal rate cache at start of each solve
  clearRateCache();

  // Check if goal is already satisfied
  if (ctx.goal.isSatisfied(ctx.initial)) {
    final profile = ctx.profileBuilder.build(
      expandedNodes: 0,
      frontier: FrontierStats.zero,
    );
    return SolverSuccess(const Plan.empty(), ctx.initial, profile);
  }

  // Create and enqueue root node
  final rootNode = _Node(
    state: ctx.initial,
    ticks: 0,
    interactions: 0,
    parentId: null,
    stepFromParent: null,
  );
  ctx.nodes.add(rootNode);
  ctx.pq.add(0);
  ctx.enqueuedNodes++;

  final (key: rootKey, elapsedUs: rootElapsedUs) = _stateKey(
    ctx.initial,
    ctx.goal,
  );
  ctx.recordHashTime(rootElapsedUs);
  ctx.bestTicks[rootKey] = 0;

  // Record root best rate for diagnostics
  if (ctx.collectDiagnostics) {
    final rootBestRate = ctx.rateCache.getBestUnlockedRate(ctx.initial);
    ctx.profileBuilder.recordBestRate(rootBestRate, isRoot: true);
    final zeroReason = ctx.rateCache.getZeroReason(ctx.initial);
    if (zeroReason != null) {
      ctx.profileBuilder.recordRateZeroReason(zeroReason);
    }
  }

  // Diagnostic tripwire: fail fast if heuristic has zero best rate.
  final rootBestRate = ctx.rateCache.getBestUnlockedRate(ctx.initial);
  if (rootBestRate <= 0) {
    final zeroReason = ctx.rateCache.getZeroReason(ctx.initial);
    final reasonStr =
        zeroReason?.describe() ?? 'unknown reason (rate computed as zero)';
    final profile = ctx.profileBuilder.build(
      expandedNodes: 0,
      frontier: ctx.frontier.stats,
    );
    final reason = 'Heuristic bestRate=0: $reasonStr';
    return SolverFailed(
      SolverFailure(
        reason: reason,
        enqueuedNodes: ctx.enqueuedNodes,
        reproBundle: ReproBundle(
          state: ctx.initial,
          goal: ctx.goal,
          reason: reason,
        ),
      ),
      profile,
    );
  }

  return null;
}

/// Collects diagnostic metrics for the current node.
void _collectNodeDiagnostics(_SolverContext ctx, _Node node) {
  if (!ctx.collectDiagnostics) return;

  final bestRate = ctx.rateCache.getBestUnlockedRate(node.state);
  final h = _heuristic(node.state, ctx.goal, ctx.rateCache);
  final nodeKey = _BucketKey.fromState(node.state, ctx.goal).toString();

  ctx.profileBuilder
    ..recordHeuristic(h, hasZeroRate: bestRate <= 0)
    ..recordBucketKey(nodeKey)
    ..recordBestRate(bestRate, isRoot: false);

  if (bestRate <= 0) {
    final zeroReason = ctx.rateCache.getZeroReason(node.state);
    if (zeroReason != null) {
      ctx.profileBuilder.recordRateZeroReason(zeroReason);
    }
  }
}

/// Solves for an optimal plan to satisfy the given [goal].
///
/// Uses A* algorithm to find the minimum-ticks path from the initial
/// state to a state where [Goal.isSatisfied] returns true.
///
/// Supports both [ReachGpGoal] (reach target GP) and [ReachSkillLevelGoal]
/// (reach target skill level).
///
/// If [collectDiagnostics] is true, collects extended diagnostic stats
/// including heuristic health, bucket key uniqueness, and candidate stats.
///
/// Returns a [SolverResult] which is either [SolverSuccess] with the plan,
/// or [SolverFailed] with failure information.
SolverResult solve(
  GlobalState initial,
  Goal goal, {
  required Random random,
  int maxExpandedNodes = defaultMaxExpandedNodes,
  int maxQueueSize = defaultMaxQueueSize,
  bool collectDiagnostics = false,
}) {
  final ctx = _SolverContext(
    initial: initial,
    goal: goal,
    maxExpandedNodes: maxExpandedNodes,
    maxQueueSize: maxQueueSize,
    collectDiagnostics: collectDiagnostics,
    boundaries: computeUnlockBoundaries(initial.registries),
    random: random,
  );

  // Initialize and check for early exit
  final initResult = _initializeSolver(ctx);
  if (initResult != null) return initResult;

  while (ctx.pq.isNotEmpty) {
    // Check limits
    if (ctx.expandedNodes >= maxExpandedNodes) {
      return ctx.fail('Exceeded max expanded nodes ($maxExpandedNodes)');
    }
    if (ctx.nodes.length >= maxQueueSize) {
      return ctx.fail('Exceeded max queue size ($maxQueueSize)');
    }

    // Pop node with smallest f-score
    final nodeId = ctx.pq.removeFirst();
    final node = ctx.nodes[nodeId];

    // Skip if we've already found a better path to this state
    final (key: nodeKey, elapsedUs: nodeElapsedUs) = _stateKey(
      node.state,
      goal,
    );
    ctx.recordHashTime(nodeElapsedUs);

    final nodeReachedGoal = goal.isSatisfied(node.state);
    final bestForKey = ctx.bestTicks[nodeKey];
    if (!nodeReachedGoal && bestForKey != null && bestForKey < node.ticks) {
      continue;
    }

    ctx.expandedNodes++;
    final neighborCounter = _NeighborCounter();

    // Track peak queue size for diagnostics
    if (ctx.pq.length > ctx.profileBuilder.peakQueueSize) {
      ctx.profileBuilder.peakQueueSize = ctx.pq.length;
    }

    // Collect diagnostics
    _collectNodeDiagnostics(ctx, node);

    // Track best credits seen
    final nodeEffectiveCredits = effectiveCredits(
      node.state,
      const SellAllPolicy(),
    );
    if (nodeEffectiveCredits > ctx.bestCredits) {
      ctx.bestCredits = nodeEffectiveCredits;
    }

    // Check if goal is reached
    if (nodeReachedGoal) {
      final plan = _reconstructPlan(
        ctx.nodes,
        nodeId,
        ctx.expandedNodes,
        ctx.enqueuedNodes,
        goal: goal,
      );
      return ctx.succeed(plan, node.state);
    }

    // Compute candidates for this state
    final segmentSellPolicy = goal is SegmentGoal
        ? goal.watchSet.sellPolicy
        : null;
    final enumStopwatch = Stopwatch()..start();
    final candidates = enumerateCandidates(
      node.state,
      goal,
      sellPolicy: segmentSellPolicy,
      collectStats: collectDiagnostics,
    );
    ctx.profileBuilder.enumerateCandidatesTimeUs +=
        enumStopwatch.elapsedMicroseconds;

    // Record candidate stats when diagnostics enabled
    if (collectDiagnostics && candidates.consumingSkillStats != null) {
      final stats = candidates.consumingSkillStats!;
      ctx.profileBuilder.candidateStatsHistory.add(
        CandidateStats(
          consumerActionsConsidered: stats.consumerActionsConsidered,
          producerActionsConsidered: stats.producerActionsConsidered,
          pairsConsidered: stats.pairsConsidered,
          pairsKept: stats.pairsKept,
          topPairs: stats.topPairs,
        ),
      );
    }

    // Get available interactions
    final sellPolicy = candidates.shouldEmitSellCandidate
        ? candidates.sellPolicy
        : null;
    final interactions = availableInteractions(
      node.state,
      sellPolicy: sellPolicy,
    );

    // Expand interaction edges (0 time cost)
    neighborCounter.value += _expandInteractionEdges(
      ctx,
      node,
      nodeId,
      candidates,
      interactions,
    );

    // Expand macro edges (train skill until boundary/goal)
    final macroResult = _expandMacroEdges(
      ctx,
      node,
      nodeId,
      candidates,
      counter: neighborCounter,
    );
    if (macroResult != null) return macroResult;

    // Expand wait edge
    final waitResult = _expandWaitEdge(
      ctx,
      node,
      nodeId,
      nodeKey,
      candidates,
      interactions,
      counter: neighborCounter,
    );
    if (waitResult != null) return waitResult;

    ctx.profileBuilder.totalNeighborsGenerated += neighborCounter.value;
  }

  // Priority queue exhausted without finding goal
  return ctx.fail('No path to goal found');
}

/// Reconstructs a plan from the goal node by walking parent pointers.
///
/// If [goal] is a [ReachGpGoal] and the terminal state's actual GP is less
/// than the target, a sell step is appended to convert inventory to GP.
Plan _reconstructPlan(
  List<_Node> nodes,
  int goalNodeId,
  int expandedNodes,
  int enqueuedNodes, {
  Goal? goal,
}) {
  final steps = <PlanStep>[];
  var currentId = goalNodeId;

  while (true) {
    final node = nodes[currentId];
    final step = node.stepFromParent;

    if (step == null) {
      // Reached root node
      break;
    }

    steps.add(step);

    final parentId = node.parentId;
    if (parentId == null) {
      break;
    }
    currentId = parentId;
  }

  // Reverse to get steps in order from start to goal
  final reversedSteps = steps.reversed.toList();

  // NOTE: We intentionally do NOT merge consecutive wait steps.
  // Each wait step may cross skill/mastery level boundaries or deaths,
  // and the rates change at those boundaries. Merging would cause
  // the plan execution to miss those state changes.

  // Insert synthetic "Sell all" steps before each "Buy upgrade".
  // The solver uses expected-value modeling which converts items to GP
  // automatically, but in practice the player must sell items first.
  final processedSteps = <PlanStep>[];
  for (final step in reversedSteps) {
    if (step is InteractionStep && step.interaction is BuyShopItem) {
      processedSteps.add(const InteractionStep(SellItems(SellAllPolicy())));
    }
    processedSteps.add(step);
  }

  // For GP goals, add a final sell step if actual GP < target.
  // The solver uses effectiveCredits (GP + inventory value) to determine
  // goal satisfaction, but execution needs actual GP. This sell step
  // converts inventory to GP at the end of the plan.
  final goalNode = nodes[goalNodeId];
  if (goal is ReachGpGoal && goalNode.state.gp < goal.targetGp) {
    processedSteps.add(const InteractionStep(SellItems(SellAllPolicy())));
  }

  return Plan(
    steps: processedSteps,
    totalTicks: goalNode.ticks,
    interactionCount: goalNode.interactions,
    expandedNodes: expandedNodes,
    enqueuedNodes: enqueuedNodes,
    expectedDeaths: goalNode.expectedDeaths,
  );
}

// ---------------------------------------------------------------------------
// Segment-Based Solving
// ---------------------------------------------------------------------------

/// Result of solving to the next segment boundary.
sealed class SegmentResult {
  const SegmentResult();
}

/// Successful segment solve.
class SegmentSuccess extends SegmentResult {
  const SegmentSuccess({
    required this.segment,
    required this.finalState,
    required this.context,
    this.profile,
  });

  /// The segment (plan portion to boundary).
  final Segment segment;

  /// Terminal state from solve() - no replay needed.
  final GlobalState finalState;

  /// The segment context (includes WatchSet and SellPolicy).
  final SegmentContext context;

  /// Solver profile for this segment (if collectDiagnostics was true).
  final SolverProfile? profile;

  /// The WatchSet used for this segment (pass to executeSegment).
  WatchSet get watchSet => context.watchSet;

  /// The SellPolicy for this segment (use for boundary handling).
  SellPolicy get sellPolicy => context.sellPolicy;
}

/// Segment solve failed.
class SegmentFailed extends SegmentResult {
  const SegmentFailed(this.failure);

  final SolverFailure failure;
}

/// Solves for a single segment: from current state to the first material
/// boundary.
///
/// A segment ends when [WatchSet.detectBoundary] returns non-null on the
/// terminal state. The boundary is derived from the terminal node's state
/// (returned by solve()), NOT by replaying the plan.
///
/// Returns a [SegmentSuccess] with:
/// - The segment (steps, ticks, boundary)
/// - The terminal state (for continuing to next segment)
/// - The SegmentContext (includes WatchSet and SellPolicy for boundary
///   handling)
SegmentResult solveSegment(
  GlobalState initial,
  Goal goal, {
  required Random random,
  SegmentConfig config = const SegmentConfig(),
  bool collectDiagnostics = false,
  int maxExpandedNodes = defaultMaxExpandedNodes,
  int maxQueueSize = defaultMaxQueueSize,
}) {
  // Build segment context - computes SellPolicy once and passes to WatchSet
  final context = SegmentContext.build(initial, goal, config);

  // Create segment goal that delegates to watchSet.detectBoundary()
  final segmentGoal = SegmentGoal(context.watchSet);

  // solve() now returns terminal state directly
  final result = solve(
    initial,
    segmentGoal,
    random: random,
    collectDiagnostics: collectDiagnostics,
    maxExpandedNodes: maxExpandedNodes,
    maxQueueSize: maxQueueSize,
  );

  return switch (result) {
    SolverSuccess(:final plan, :final terminalState, :final profile) => () {
      // Derive boundary from terminal state (no replay needed!)
      final boundary =
          context.watchSet.detectBoundary(
            terminalState,
            elapsedTicks: plan.totalTicks,
          ) ??
          const GoalReachedBoundary();

      return SegmentSuccess(
        segment: Segment(
          steps: plan.steps,
          totalTicks: plan.totalTicks,
          interactionCount: plan.interactionCount,
          stopBoundary: boundary,
          sellPolicy: context.sellPolicy,
        ),
        finalState: terminalState,
        context: context,
        profile: profile,
      );
    }(),
    SolverFailed(:final failure) => SegmentFailed(failure),
  };
}

/// Result of executing a single segment.
@immutable
class SegmentExecutionResult {
  const SegmentExecutionResult({
    required this.finalState,
    required this.boundaryHit,
    required this.actualTicks,
    required this.plannedTicks,
    required this.deaths,
  });

  /// The state after executing the segment.
  final GlobalState finalState;

  /// What boundary was hit (same type as planning).
  final SegmentBoundary? boundaryHit;

  /// Actual ticks elapsed during execution.
  final int actualTicks;

  /// Planned ticks from the solver (for comparison).
  final int plannedTicks;

  /// Number of deaths during execution.
  final int deaths;

  /// Difference between actual and planned ticks.
  int get ticksDelta => actualTicks - plannedTicks;
}

/// Executes a segment with stochastic simulation.
///
/// Uses the SAME [WatchSet] from planning to determine material boundaries.
/// Stops when [applyStep] returns a boundary that [WatchSet.isMaterial]
/// accepts.
///
/// The [random] parameter controls the stochastic simulation. For
/// deterministic testing, use a seeded Random.
SegmentExecutionResult executeSegment(
  GlobalState state,
  Segment segment,
  WatchSet watchSet, {
  required Random random,
}) {
  var currentState = state;
  var totalTicks = 0;
  var totalDeaths = 0;
  final unlockBoundaries = computeUnlockBoundaries(state.registries);

  for (final step in segment.steps) {
    final result = applyStep(
      currentState,
      step,
      random: random,
      boundaries: unlockBoundaries,
      watchSet: watchSet,
      segmentSellPolicy: segment.sellPolicy,
    );
    currentState = result.state;
    totalTicks += result.ticksElapsed;
    totalDeaths += result.deaths;

    // Check if applyStep's boundary is material using the SAME watchSet
    if (result.boundary != null && watchSet.isMaterial(result.boundary!)) {
      // Convert ReplanBoundary -> SegmentBoundary using watchSet
      final segmentBoundary = watchSet.toSegmentBoundary(result.boundary!);
      return SegmentExecutionResult(
        finalState: currentState,
        boundaryHit: segmentBoundary,
        actualTicks: totalTicks,
        plannedTicks: segment.totalTicks,
        deaths: totalDeaths,
      );
    }
  }

  // No early boundary - use the expected boundary from planning
  return SegmentExecutionResult(
    finalState: currentState,
    boundaryHit: segment.stopBoundary,
    actualTicks: totalTicks,
    plannedTicks: segment.totalTicks,
    deaths: totalDeaths,
  );
}

// ---------------------------------------------------------------------------
// Full Segmented Solving
// ---------------------------------------------------------------------------

/// Result of solving to goal via segments.
sealed class SegmentedSolverResult {
  const SegmentedSolverResult();
}

/// Successfully solved to goal via segments.
class SegmentedSuccess extends SegmentedSolverResult {
  const SegmentedSuccess({
    required this.segments,
    required this.totalTicks,
    required this.totalReplanCount,
    required this.finalState,
    this.segmentProfiles = const [],
  });

  /// Individual segments for debugging/inspection.
  final List<Segment> segments;

  /// Total ticks across all segments.
  final int totalTicks;

  /// Number of times we replanned (= number of segments).
  final int totalReplanCount;

  /// Final state after all segments.
  final GlobalState finalState;

  /// Per-segment solver profiles (if collectDiagnostics was true).
  /// Length matches [segments] - each profile corresponds to a segment.
  final List<SolverProfile> segmentProfiles;
}

/// Failed to solve to goal via segments.
class SegmentedFailed extends SegmentedSolverResult {
  const SegmentedFailed(this.failure, {this.completedSegments = const []});

  final SolverFailure failure;

  /// Segments completed before failure.
  final List<Segment> completedSegments;
}

/// Primary entry point: solves to goal by iteratively solving segments.
///
/// This is the main solver API. Each segment plans to the next material
/// boundary (upgrade affordable, skill unlock, inputs depleted, etc.),
/// then replans from the new state.
///
/// The loop:
/// 1. Solve for next segment (to boundary)
/// 2. Use projected state from solve() (no separate execution needed)
/// 3. Repeat until goal reached
///
/// For stochastic execution, call [executeSegment] on each segment with
/// a Random instance.
///
/// Parameters:
/// - [initial]: Starting state
/// - [goal]: The goal to reach
/// - [config]: Segment stopping configuration
/// - [collectDiagnostics]: If true, collect per-segment solver profiles
/// - [maxSegments]: Safety limit to prevent infinite loops (default 100)
/// - [maxExpandedNodesPerSegment]: Node limit per segment search
SegmentedSolverResult solveToGoal(
  GlobalState initial,
  Goal goal, {
  required Random random,
  SegmentConfig config = const SegmentConfig(),
  bool collectDiagnostics = false,
  int maxSegments = 100,
  int maxExpandedNodesPerSegment = defaultMaxExpandedNodes,
}) {
  final segments = <Segment>[];
  final profiles = <SolverProfile>[];
  var currentState = initial;

  for (var segmentIndex = 0; segmentIndex < maxSegments; segmentIndex++) {
    // Check if goal is already satisfied
    if (goal.isSatisfied(currentState)) {
      break;
    }

    // Solve for next segment
    final segmentResult = solveSegment(
      currentState,
      goal,
      random: random,
      config: config,
      collectDiagnostics: collectDiagnostics,
      maxExpandedNodes: maxExpandedNodesPerSegment,
    );

    switch (segmentResult) {
      case SegmentFailed(:final failure):
        return SegmentedFailed(failure, completedSegments: segments);

      case SegmentSuccess(
        :final segment,
        :final finalState,
        :final sellPolicy,
        :final profile,
      ):
        segments.add(segment);
        if (profile != null) {
          profiles.add(profile);
        }

        // Use projected state from solve() (deterministic)
        currentState = finalState;

        // If goal reached, we're done - but for GP goals, we may need to sell
        // items first to convert inventory value to actual GP.
        if (segment.stopBoundary is GoalReachedBoundary) {
          if (goal is ReachGpGoal && currentState.gp < goal.targetGp) {
            // GP goal: effectiveCredits >= target, but actual GP < target.
            // Sell items to convert inventory value to GP.
            final sellInteraction = SellItems(sellPolicy);
            currentState = applyInteraction(currentState, sellInteraction);

            // Add a synthetic segment for the sell step
            segments.add(
              Segment(
                steps: [InteractionStep(sellInteraction)],
                totalTicks: 0,
                interactionCount: 1,
                stopBoundary: const GoalReachedBoundary(),
                sellPolicy: sellPolicy,
                description: 'Sell items to reach GP goal',
              ),
            );
          }
          break;
        }

        // If we stopped because an upgrade became affordable, sell items
        // (if needed) and buy it, then add a synthetic segment
        if (segment.stopBoundary is UpgradeAffordableBoundary) {
          currentState = _handleUpgradeAffordableBoundary(
            segment,
            currentState,
            segments,
          );
        }
    }
  }

  // Calculate total ticks
  final totalTicks = segments.fold<int>(
    0,
    (sum, segment) => sum + segment.totalTicks,
  );

  return SegmentedSuccess(
    segments: segments,
    totalTicks: totalTicks,
    totalReplanCount: segments.length,
    finalState: currentState,
    segmentProfiles: profiles,
  );
}

GlobalState _handleUpgradeAffordableBoundary(
  Segment segment,
  GlobalState incomingState,
  List<Segment> segments,
) {
  var currentState = incomingState;
  final boundary = segment.stopBoundary as UpgradeAffordableBoundary;
  final sellPolicy = segment.sellPolicy!;

  final purchaseSteps = <PlanStep>[];

  // Check if we need to sell items to afford the upgrade
  final purchase = currentState.registries.shop.byId(boundary.purchaseId);
  final gpCost = purchase?.cost.gpCost ?? 0;

  // WatchSet triggered because effectiveCredits >= gpCost. Verify this.
  final credits = effectiveCredits(currentState, sellPolicy);
  assert(
    credits >= gpCost,
    'WatchSet reported upgrade affordable but effectiveCredits '
    '($credits) < gpCost ($gpCost)',
  );

  // Sell if actual GP is insufficient (items need to be converted).
  final needsToSell = currentState.gp < gpCost;
  if (needsToSell) {
    // Use the segment's sell policy - computed once at segment start.
    // This is the SAME policy used by WatchSet for effectiveCredits,
    // ensuring the boundary detection and handling are consistent.
    final sellInteraction = SellItems(sellPolicy);
    currentState = applyInteraction(currentState, sellInteraction);
    purchaseSteps.add(InteractionStep(sellInteraction));

    // INVARIANT: If WatchSet reported this upgrade as affordable,
    // applying the same sell policy must make it purchasable.
    // If this fails, WatchSet and boundary handling disagree - a bug.
    assert(
      currentState.gp >= gpCost,
      'Invariant violated: WatchSet reported upgrade affordable but '
      'selling with the same policy only yielded ${currentState.gp} GP '
      '(need $gpCost). This indicates a bug in effectiveCredits or '
      'sell policy handling.',
    );
  }

  // Buy the upgrade (should always succeed after selling per invariant)
  if (currentState.gp >= gpCost) {
    final buyInteraction = BuyShopItem(boundary.purchaseId);
    currentState = applyInteraction(currentState, buyInteraction);
    purchaseSteps.add(InteractionStep(buyInteraction));
  }

  // Add a synthetic segment for the sell+purchase (0 ticks, just
  // records the interactions)
  segments.add(
    Segment(
      steps: purchaseSteps,
      totalTicks: 0,
      interactionCount: purchaseSteps.length,
      stopBoundary: boundary,
      sellPolicy: sellPolicy,
      description: 'Buy ${boundary.upgradeName}',
    ),
  );
  return currentState;
}
