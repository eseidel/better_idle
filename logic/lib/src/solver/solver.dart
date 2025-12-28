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
library;

// We should use a logger instead of print statements.
// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/solver/apply_interaction.dart';
import 'package:logic/src/solver/available_interactions.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/estimate_rates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/solver/next_decision_delta.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/unlock_boundaries.dart';
import 'package:logic/src/solver/value_model.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:logic/src/types/time_away.dart';

/// Profiling stats collected during a solve.
class SolverProfile {
  int expandedNodes = 0;
  int totalNeighborsGenerated = 0;
  final List<int> decisionDeltas = [];

  // Timing in microseconds
  int advanceTimeUs = 0;
  int enumerateCandidatesTimeUs = 0;
  int hashingTimeUs = 0;
  int totalTimeUs = 0;

  // Dominance pruning stats
  int dominatedSkipped = 0;
  int frontierInserted = 0;
  int frontierRemoved = 0;

  double get nodesPerSecond =>
      totalTimeUs > 0 ? expandedNodes / (totalTimeUs / 1e6) : 0;

  double get avgBranchingFactor =>
      expandedNodes > 0 ? totalNeighborsGenerated / expandedNodes : 0;

  int get minDelta => decisionDeltas.isEmpty ? 0 : decisionDeltas.reduce(min);

  int get medianDelta {
    if (decisionDeltas.isEmpty) return 0;
    final sorted = List<int>.from(decisionDeltas)..sort();
    return sorted[sorted.length ~/ 2];
  }

  int get p95Delta {
    if (decisionDeltas.isEmpty) return 0;
    final sorted = List<int>.from(decisionDeltas)..sort();
    final idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  double get advancePercent =>
      totalTimeUs > 0 ? 100.0 * advanceTimeUs / totalTimeUs : 0;

  double get enumeratePercent =>
      totalTimeUs > 0 ? 100.0 * enumerateCandidatesTimeUs / totalTimeUs : 0;

  double get hashingPercent =>
      totalTimeUs > 0 ? 100.0 * hashingTimeUs / totalTimeUs : 0;
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
  });

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
  ];
}

/// Creates a goal-scoped bucket key from a game state.
/// Only tracks skills, HP, mastery, and inventory relevant to the goal.
_BucketKey _bucketKeyFromState(GlobalState state, Goal goal) {
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
  final inventoryBucket = goal.shouldTrackInventory
      ? () {
          final totalItems = state.inventory.items.fold<int>(
            0,
            (sum, stack) => sum + stack.count,
          );
          // For small inventories (< 100 items), use exact count
          // For larger inventories, use buckets
          return totalItems < 100
              ? totalItems
              : 100 + (totalItems - 100) ~/ _inventoryBucketSize;
        }()
      : 0;

  return _BucketKey(
    activityName: activityName,
    skillLevels: skillLevels,
    axeLevel: state.shop.axeLevel,
    rodLevel: state.shop.fishingRodLevel,
    pickLevel: state.shop.pickaxeLevel,
    hpBucket: hpBucket,
    masteryLevel: masteryLevel,
    inventoryBucket: inventoryBucket,
  );
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
  int inserted = 0;
  int removed = 0;

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
    removed += originalLength - frontier.length;

    // Insert new point
    frontier.add(_FrontierPoint(ticks, progress));
    inserted++;

    return false; // Not dominated
  }
}

/// Default limits for the solver to prevent runaway searches.
const int defaultMaxExpandedNodes = 200000;
const int defaultMaxQueueSize = 500000;

/// Calculates the total value of a state (GP + sellable inventory value).
int _effectiveCredits(GlobalState state) {
  var total = state.gp;
  for (final stack in state.inventory.items) {
    total += stack.sellsFor;
  }
  return total;
}

/// Cache for best unlocked rate by state key (skill levels + tool tiers).
/// Supports both GP goals (gold/tick) and skill goals (XP/tick).
class _RateCache {
  _RateCache(this.goal);

  final Goal goal;
  final Map<String, double> _cache = {};
  final Map<String, double> _skillCache = {};

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

    final rate = _computeBestUnlockedRate(state);
    _cache[key] = rate;
    return rate;
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
  double _computeBestUnlockedRate(GlobalState state) {
    var maxRate = 0.0;
    final registries = state.registries;

    for (final skill in Skill.values) {
      // Only consider skills relevant to the goal
      if (!goal.isSkillRelevant(skill)) continue;

      final skillLevel = state.skillState(skill).skillLevel;

      for (final action in registries.actions.forSkill(skill)) {
        // Skip actions that require inputs
        if (action.inputs.isNotEmpty) continue;

        // Only consider unlocked actions
        if (skillLevel < action.unlockLevel) continue;

        // Calculate expected ticks with upgrade modifier
        final baseExpectedTicks = ticksFromDuration(
          action.meanDuration,
        ).toDouble();
        final percentModifier = state.shopDurationModifierForSkill(skill);
        final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);
        if (expectedTicks <= 0) continue;

        // Compute both gold and XP rates, let goal decide which matters
        double goldRate;
        double xpRate;

        if (action is ThievingAction) {
          final thievingLevel = state.skillState(Skill.thieving).skillLevel;
          final mastery = state.actionState(action.id).masteryLevel;
          final stealth = calculateStealth(thievingLevel, mastery);
          final successChance = ((100 + stealth) / (100 + action.perception))
              .clamp(0.0, 1.0);
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
        } else {
          xpRate = action.xp / expectedTicks;

          var expectedGoldPerAction = 0.0;
          for (final output in action.outputs.entries) {
            final item = registries.items.byId(output.key);
            expectedGoldPerAction += item.sellsFor * output.value;
          }
          goldRate = expectedGoldPerAction / expectedTicks;
        }

        // Let the goal decide which rate matters
        final rate = goal.activityRate(skill, goldRate, xpRate);
        if (rate > maxRate) {
          maxRate = rate;
        }
      }
    }

    return maxRate;
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

/// Computes a goal-scoped hash key for a game state for visited tracking.
///
/// Uses bucketed gold for coarser grouping to reduce state explosion.
/// Only includes fields relevant to the goal to avoid unnecessary distinctions.
String _stateKey(GlobalState state, Goal goal) {
  final buffer = StringBuffer();

  // Bucketed gold (coarse grouping for large goals)
  // Using GP directly since advanceExpected converts items to gold
  final goldBucket = state.gp ~/ _goldBucketSize;
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

  return buffer.toString();
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
/// Uses [valueModel] to convert item flows into GP value.
/// Returns the new state and the number of expected deaths.
AdvanceResult _advanceExpected(
  GlobalState state,
  int deltaTicks, {
  ValueModel valueModel = defaultValueModel,
}) {
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

  // Compute expected gold gain using the value model
  // (converts item flows to GP based on the policy)
  final valueRate = valueModel.valuePerTick(state, rates);
  final expectedGold = (valueRate * deltaTicks).floor();
  final newGp = state.gp + expectedGold;

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
  return (
    state: state.copyWith(
      currencies: newCurrencies,
      skillStates: newSkillStates,
      actionStates: newActionStates,
      inventory: newInventory,
    ),
    deaths: expectedDeaths,
  );
}

/// Full simulation advance using consumeTicks.
GlobalState _advanceFullSim(
  GlobalState state,
  int deltaTicks, {
  Random? random,
}) {
  if (deltaTicks <= 0) return state;

  // Use a fixed random for deterministic planning if not provided
  random ??= Random(42);

  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, deltaTicks, random: random);
  return builder.build();
}

/// Advances the game state by a given number of ticks.
/// Uses O(1) expected-value advance for rate-modelable activities,
/// falls back to full simulation for combat/complex activities.
///
/// Only should be used for planning, since it will not perfectly match
/// game state (e.g. won't add inventory items)
///
/// Returns the new state and the number of expected deaths.
AdvanceResult advance(GlobalState state, int deltaTicks) {
  if (deltaTicks <= 0) return (state: state, deaths: 0);

  if (_isRateModelable(state)) {
    return _advanceExpected(state, deltaTicks);
  }
  return (state: _advanceFullSim(state, deltaTicks), deaths: 0);
}

/// Result of consuming ticks until a goal is reached.
class ConsumeUntilResult {
  ConsumeUntilResult({
    required this.state,
    required this.ticksElapsed,
    required this.deathCount,
  });

  final GlobalState state;
  final int ticksElapsed;
  final int deathCount;
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
    // Get the required input item (same for both since they produce it)
    final inputItemId = consumingAction.inputs.keys.first;

    // Calculate production rate for action a
    final aOutputCount = a.outputs[inputItemId] ?? 0;
    final aTicksPerAction =
        (a.minDuration.inMilliseconds / Duration.millisecondsPerSecond * 10)
            .round();
    final aRate = aOutputCount / aTicksPerAction;

    // Calculate production rate for action b
    final bOutputCount = b.outputs[inputItemId] ?? 0;
    final bTicksPerAction =
        (b.minDuration.inMilliseconds / Duration.millisecondsPerSecond * 10)
            .round();
    final bRate = bOutputCount / bTicksPerAction;

    // Higher rate is better
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
/// Returns the final state, actual ticks elapsed, and death count.
ConsumeUntilResult consumeUntil(
  GlobalState originalState,
  WaitFor waitFor, {
  required Random random,
}) {
  var state = originalState;
  if (waitFor.isSatisfied(state)) {
    return ConsumeUntilResult(state: state, ticksElapsed: 0, deathCount: 0);
  }

  final originalActivityId = state.activeAction?.id;
  var totalTicksElapsed = 0;
  var deathCount = 0;

  // Keep running until the condition is satisfied, restarting after deaths
  while (true) {
    final builder = StateUpdateBuilder(state);

    // Use consumeTicksUntil which checks the condition after each action
    consumeTicksUntil(
      builder,
      random: random,
      stopCondition: (s) => waitFor.isSatisfied(s),
    );

    state = builder.build();
    totalTicksElapsed += builder.ticksElapsed;

    // Check if we're done
    if (waitFor.isSatisfied(state)) {
      return ConsumeUntilResult(
        state: state,
        ticksElapsed: totalTicksElapsed,
        deathCount: deathCount,
      );
    }

    // Check if activity stopped
    if (builder.stopReason != ActionStopReason.stillRunning) {
      if (builder.stopReason == ActionStopReason.playerDied) {
        deathCount++;

        // Auto-restart the activity after death and continue
        if (originalActivityId != null) {
          final action = state.registries.actions.byId(originalActivityId);
          state = state.startAction(action, random: random);
          continue; // Continue with restarted activity
        }
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

            // Calculate buffer: enough to burn for ~5 minutes
            final consumptionRate = currentAction.inputs.values.first;
            final ticksPerBurn =
                (currentAction.minDuration.inMilliseconds /
                        Duration.millisecondsPerSecond *
                        10)
                    .round();
            const bufferTicks = 3000; // 5 minutes at 100ms/tick
            final bufferCount = ((bufferTicks / ticksPerBurn) * consumptionRate)
                .ceil();

            print(
              'Switching to ${producer.name} to gather '
              '$bufferCount+ ${inputItemId.localId}...',
            );

            // Switch to producer
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

            // Switch back to consumer
            print('Switching back to ${currentAction.name}...');
            state = state.startAction(currentAction, random: random);
            continue; // Continue consuming
          }
        }
      }

      // No producer found - return with partial progress
      print(
        'WARNING: Activity stopped (${builder.stopReason}) before wait '
        'condition satisfied: ${waitFor.describe()}',
      );
      break;
    }

    // No progress possible
    if (builder.ticksElapsed == 0 && state.activeAction == null) {
      break;
    }
  }

  // Return whatever state we ended up with
  return ConsumeUntilResult(
    state: state,
    ticksElapsed: totalTicksElapsed,
    deathCount: deathCount,
  );
}

/// Result of applying a single step.
typedef _StepResult = ({GlobalState state, int ticksElapsed, int deaths});

_StepResult _applyStep(
  GlobalState state,
  PlanStep step, {
  required Random random,
}) {
  switch (step) {
    case InteractionStep(:final interaction):
      return (
        state: applyInteraction(state, interaction),
        ticksElapsed: 0,
        deaths: 0,
      );
    case WaitStep(:final waitFor):
      // Run until the wait condition is satisfied
      final result = consumeUntil(state, waitFor, random: random);
      return (
        state: result.state,
        ticksElapsed: result.ticksElapsed,
        deaths: result.deathCount,
      );
    case MacroStep(:final macro, :final waitFor):
      // Execute the macro by running until the composite wait condition
      // Macros need to set up the action before executing
      var executionState = state;
      if (macro is TrainSkillUntil) {
        // Find and switch to the best action for this skill
        final bestAction = _findBestActionForSkill(
          state,
          macro.skill,
          // We don't have the goal here, so create a dummy one
          ReachSkillLevelGoal(macro.skill, 99),
        );
        if (bestAction != null && state.activeAction?.id != bestAction) {
          executionState = applyInteraction(state, SwitchActivity(bestAction));
        }
      }

      final result = consumeUntil(executionState, waitFor, random: random);
      return (
        state: result.state,
        ticksElapsed: result.ticksElapsed,
        deaths: result.deathCount,
      );
  }
}

/// Execute a plan and return the result including death count and actual ticks.
///
/// Uses goal-aware waiting: [WaitStep.waitFor] determines when to stop waiting,
/// which handles variance between expected-value planning and full simulation.
/// Deaths are automatically handled by restarting the activity and are counted.
PlanExecutionResult executePlan(
  GlobalState originalState,
  Plan plan, {
  required Random random,
}) {
  var state = originalState;
  var totalDeaths = 0;
  var actualTicks = 0;

  for (var i = 0; i < plan.steps.length; i++) {
    final step = plan.steps[i];
    try {
      final result = _applyStep(state, step, random: random);
      state = result.state;
      totalDeaths += result.deaths;
      actualTicks += result.ticksElapsed;
    } catch (e) {
      print('Error applying step $i: $e');
      rethrow;
    }
  }
  return PlanExecutionResult(
    finalState: state,
    totalDeaths: totalDeaths,
    actualTicks: actualTicks,
    plannedTicks: plan.totalTicks,
  );
}

/// Solves for an optimal plan to reach the target credits.
///
/// Uses A* algorithm to find the minimum-ticks path from the initial
/// state to a state with at least [goalCredits] GP.
///
/// Returns a [SolverResult] which is either [SolverSuccess] with the plan,
/// or [SolverFailed] with failure information.
SolverResult solveToCredits(
  GlobalState initial,
  int goalCredits, {
  int maxExpandedNodes = defaultMaxExpandedNodes,
  int maxQueueSize = defaultMaxQueueSize,
}) {
  return solve(
    initial,
    ReachGpGoal(goalCredits),
    maxExpandedNodes: maxExpandedNodes,
    maxQueueSize: maxQueueSize,
  );
}

// ---------------------------------------------------------------------------
// Macro Expansion
// ---------------------------------------------------------------------------

/// Result of expanding a macro candidate.
typedef MacroExpansionResult = ({
  GlobalState state,
  int ticksElapsed,
  WaitFor waitFor, // Composite WaitFor for plan execution
  int deaths,
});

/// Expands a macro candidate into a future state by estimating progress.
///
/// Uses expected-value modeling (same as `advance`) to project forward
/// until ANY of the macro's stop conditions would trigger.
///
/// Returns null if the macro cannot be executed (e.g., no unlocked actions).
MacroExpansionResult? _expandMacro(
  GlobalState state,
  MacroCandidate macro,
  Goal goal,
  Map<Skill, SkillBoundaries> boundaries,
) {
  if (macro is! TrainSkillUntil) return null;
  return _expandTrainSkillUntil(state, macro, goal, boundaries);
}

/// Expands a TrainSkillUntil macro.
///
/// 1. Finds the best unlocked action for the skill
/// 2. Switches to that action (if not already on it)
/// 3. Builds composite WaitFor from all stop rules (primary + watched)
/// 4. Estimates ticks until soonest condition triggers
/// 5. Uses expected-value advance to project state
MacroExpansionResult? _expandTrainSkillUntil(
  GlobalState state,
  TrainSkillUntil macro,
  Goal goal,
  Map<Skill, SkillBoundaries> boundaries,
) {
  // Find best unlocked action for this skill
  final bestAction = _findBestActionForSkill(state, macro.skill, goal);
  if (bestAction == null) return null;

  // Switch to that action (if not already on it)
  var currentState = state;
  if (state.activeAction?.id != bestAction) {
    currentState = applyInteraction(state, SwitchActivity(bestAction));
  }

  // Build composite WaitFor from all stop rules (primary + watched)
  final waitConditions = macro.allStops
      .map((MacroStopRule rule) => rule.toWaitFor(currentState, boundaries))
      .toList();

  // Create composite WaitFor (stops when ANY condition triggers)
  final compositeWaitFor = waitConditions.length == 1
      ? waitConditions.first
      : WaitForAnyOf(waitConditions);

  // Estimate ticks until ANY stop condition triggers (use minimum)
  final ticksUntilStop = _estimateTicksForCompositeWaitFor(
    currentState,
    waitConditions,
    goal,
  );

  if (ticksUntilStop <= 0 || ticksUntilStop >= infTicks) {
    return null; // No progress possible or already satisfied
  }

  // Use expected-value advance (already exists!)
  final advanceResult = advance(currentState, ticksUntilStop);

  return (
    state: advanceResult.state,
    ticksElapsed: ticksUntilStop,
    waitFor: compositeWaitFor, // Execution will respect all conditions
    deaths: advanceResult.deaths,
  );
}

/// Finds the best action for a skill based on the goal's criteria.
///
/// For skill goals, picks the action with highest XP rate.
/// For GP goals, picks the action with highest gold rate.
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

  for (final action in actions) {
    // Switch to action to estimate rates
    final testState = applyInteraction(state, SwitchActivity(action.id));
    final rates = estimateRates(testState);

    final goldRate = defaultValueModel.valuePerTick(testState, rates);
    final xpRate = rates.xpPerTickBySkill[skill] ?? 0.0;

    final rate = goal.activityRate(skill, goldRate, xpRate);

    if (rate > bestRate) {
      bestRate = rate;
      best = action.id;
    }
  }

  return best;
}

/// Estimates ticks until ANY condition is satisfied (returns minimum).
int _estimateTicksForCompositeWaitFor(
  GlobalState state,
  List<WaitFor> conditions,
  Goal goal,
) {
  var minTicks = infTicks;

  for (final condition in conditions) {
    final ticks = _estimateTicksForSingleWaitFor(state, condition, goal);
    if (ticks < minTicks) {
      minTicks = ticks;
    }
  }

  return minTicks;
}

/// Estimates ticks for a single WaitFor condition.
int _estimateTicksForSingleWaitFor(
  GlobalState state,
  WaitFor condition,
  Goal goal,
) {
  final rates = estimateRates(state);

  switch (condition) {
    case WaitForSkillXp(:final skill, :final targetXp):
      final currentXp = state.skillState(skill).xp;
      final needed = targetXp - currentXp;
      if (needed <= 0) return 0;

      final xpRate = rates.xpPerTickBySkill[skill] ?? 0.0;
      if (xpRate <= 0) return infTicks;

      return (needed / xpRate).ceil();

    case WaitForInventoryValue(:final targetValue):
      final currentValue = _effectiveCredits(state);
      final needed = targetValue - currentValue;
      if (needed <= 0) return 0;

      final valueRate = defaultValueModel.valuePerTick(state, rates);
      if (valueRate <= 0) return infTicks;

      return (needed / valueRate).ceil();

    case WaitForInputsDepleted(:final actionId):
      // Estimate from current inventory / consumption rate
      final action = state.registries.actions.byId(actionId);
      if (action is! SkillAction) return infTicks;

      final actionStateVal = state.actionState(action.id);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);

      if (inputs.isEmpty) return infTicks; // Non-consuming action

      // Find minimum ticks based on available inputs
      var minInputTicks = infTicks;
      final actionDurationTicks =
          action.minDuration.inMilliseconds ~/ msPerTick;

      for (final entry in inputs.entries) {
        final item = state.registries.items.byId(entry.key);
        final available = state.inventory.countOfItem(item);
        final consumedPerAction = entry.value;
        final consumedPerTick =
            consumedPerAction / actionDurationTicks.toDouble();

        if (consumedPerTick > 0) {
          final ticksUntilDepleted = (available / consumedPerTick).floor();
          if (ticksUntilDepleted < minInputTicks) {
            minInputTicks = ticksUntilDepleted;
          }
        }
      }

      return minInputTicks;

    case WaitForAnyOf(:final conditions):
      // Recursively handle nested AnyOf
      return _estimateTicksForCompositeWaitFor(state, conditions, goal);

    case WaitForGoal(:final goal):
      final remaining = goal.remaining(state);
      if (remaining <= 0) return 0;

      final progressRate = goal.progressPerTick(state, rates);
      if (progressRate <= 0) return infTicks;

      return (remaining / progressRate).ceil();

    default:
      // Conservative fallback for unhandled types
      return infTicks;
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
/// Returns a [SolverResult] which is either [SolverSuccess] with the plan,
/// or [SolverFailed] with failure information.
SolverResult solve(
  GlobalState initial,
  Goal goal, {
  int maxExpandedNodes = defaultMaxExpandedNodes,
  int maxQueueSize = defaultMaxQueueSize,
}) {
  final profile = SolverProfile();
  final totalStopwatch = Stopwatch()..start();

  // Check if goal is already satisfied (considering inventory value)
  if (goal.isSatisfied(initial)) {
    return SolverSuccess(const Plan.empty(), profile);
  }

  // Compute unlock boundaries for macro-step planning
  final boundaries = computeUnlockBoundaries(initial.registries);

  // Rate cache for A* heuristic (caches best unlocked rate by state)
  final rateCache = _RateCache(goal);

  // Dominance pruning frontier
  final frontier = _ParetoFrontier();

  // Node storage - indices are node IDs
  final nodes = <_Node>[];

  // A* priority: f(n) = g(n) + h(n) = ticksSoFar + heuristic
  // Break ties by lower ticksSoFar (prefer actual progress over estimates)
  final pq = PriorityQueue<int>((a, b) {
    final fA = nodes[a].ticks + _heuristic(nodes[a].state, goal, rateCache);
    final fB = nodes[b].ticks + _heuristic(nodes[b].state, goal, rateCache);
    final cmp = fA.compareTo(fB);
    if (cmp != 0) return cmp;
    // Tie-break by lower g (actual ticks)
    return nodes[a].ticks.compareTo(nodes[b].ticks);
  });

  // Best ticks seen for each state key
  final bestTicks = HashMap<String, int>();

  // Stats
  var expandedNodes = 0;
  var enqueuedNodes = 0;
  var bestCredits = initial.gp;

  // Create and enqueue root node
  final rootNode = _Node(
    state: initial,
    ticks: 0,
    interactions: 0,
    parentId: null,
    stepFromParent: null,
  );
  nodes.add(rootNode);
  pq.add(0);
  enqueuedNodes++;

  final hashStopwatch = Stopwatch()..start();
  final rootKey = _stateKey(initial, goal);
  profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;
  bestTicks[rootKey] = 0;

  while (pq.isNotEmpty) {
    // Check limits
    if (expandedNodes >= maxExpandedNodes) {
      totalStopwatch.stop();
      profile
        ..expandedNodes = expandedNodes
        ..totalTimeUs = totalStopwatch.elapsedMicroseconds
        ..frontierInserted = frontier.inserted
        ..frontierRemoved = frontier.removed;
      return SolverFailed(
        SolverFailure(
          reason: 'Exceeded max expanded nodes ($maxExpandedNodes)',
          expandedNodes: expandedNodes,
          enqueuedNodes: enqueuedNodes,
          bestCredits: bestCredits,
        ),
        profile,
      );
    }

    if (nodes.length >= maxQueueSize) {
      totalStopwatch.stop();
      profile
        ..expandedNodes = expandedNodes
        ..totalTimeUs = totalStopwatch.elapsedMicroseconds
        ..frontierInserted = frontier.inserted
        ..frontierRemoved = frontier.removed;
      return SolverFailed(
        SolverFailure(
          reason: 'Exceeded max queue size ($maxQueueSize)',
          expandedNodes: expandedNodes,
          enqueuedNodes: enqueuedNodes,
          bestCredits: bestCredits,
        ),
        profile,
      );
    }

    // Pop node with smallest ticks
    final nodeId = pq.removeFirst();
    final node = nodes[nodeId];

    // Skip if we've already found a better path to this state
    // BUT: never skip if this node has reached the goal!
    hashStopwatch
      ..reset()
      ..start();
    final nodeKey = _stateKey(node.state, goal);
    profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

    final nodeReachedGoal = goal.isSatisfied(node.state);

    final bestForKey = bestTicks[nodeKey];
    if (!nodeReachedGoal && bestForKey != null && bestForKey < node.ticks) {
      continue;
    }

    expandedNodes++;
    var neighborsThisNode = 0;

    // Track best credits seen (effective credits = GP + inventory value)
    // Note: For non-GP goals this tracks GP anyway for diagnostics.
    final nodeEffectiveCredits = _effectiveCredits(node.state);
    if (nodeEffectiveCredits > bestCredits) {
      bestCredits = nodeEffectiveCredits;
    }

    // Check if goal is reached
    if (nodeReachedGoal) {
      // Reconstruct and return the plan
      final plan = _reconstructPlan(
        nodes,
        nodeId,
        expandedNodes,
        enqueuedNodes,
      );
      totalStopwatch.stop();
      profile
        ..expandedNodes = expandedNodes
        ..totalTimeUs = totalStopwatch.elapsedMicroseconds
        ..frontierInserted = frontier.inserted
        ..frontierRemoved = frontier.removed;
      return SolverSuccess(plan, profile);
    }

    // Compute candidates for this state
    final enumStopwatch = Stopwatch()..start();
    final candidates = enumerateCandidates(node.state, goal);
    profile.enumerateCandidatesTimeUs += enumStopwatch.elapsedMicroseconds;

    // Expand interaction edges (0 time cost)
    final interactions = availableInteractions(node.state);
    for (final interaction in interactions) {
      // Only consider interactions that are in our candidate set (for pruning)
      if (!_isRelevantInteraction(interaction, candidates)) continue;

      try {
        final newState = applyInteraction(node.state, interaction);
        final newProgress = goal.progress(newState);
        final newBucketKey = _bucketKeyFromState(newState, goal);

        // Dominance pruning: skip if dominated by existing frontier point
        if (frontier.isDominatedOrInsert(
          newBucketKey,
          node.ticks,
          newProgress,
        )) {
          profile.dominatedSkipped++;
          continue;
        }

        hashStopwatch
          ..reset()
          ..start();
        final newKey = _stateKey(newState, goal);
        profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

        // Only enqueue if this is the best path to this state
        final existingBest = bestTicks[newKey];
        if (existingBest == null || node.ticks < existingBest) {
          bestTicks[newKey] = node.ticks;

          final newNode = _Node(
            state: newState,
            ticks: node.ticks, // Interactions cost 0 ticks
            interactions: node.interactions + 1,
            parentId: nodeId,
            stepFromParent: InteractionStep(interaction),
          );

          final newNodeId = nodes.length;
          nodes.add(newNode);
          pq.add(newNodeId);
          enqueuedNodes++;
          neighborsThisNode++;
        }
      } on Exception catch (_) {
        // Interaction failed (e.g., can't afford upgrade) - skip
        continue;
      }
    }

    // Expand macro edges (train skill until boundary/goal)
    for (final macro in candidates.macros) {
      final expansionResult = _expandMacro(node.state, macro, goal, boundaries);
      if (expansionResult == null) continue;

      final newState = expansionResult.state;
      final newDeaths = node.expectedDeaths + expansionResult.deaths;
      final newTicks = node.ticks + expansionResult.ticksElapsed;
      final newProgress = goal.progress(newState);
      final newBucketKey = _bucketKeyFromState(newState, goal);

      // Check if we've reached the goal
      final reachedGoal = goal.isSatisfied(newState);

      // Dominance pruning: skip if dominated unless we reached the goal
      if (!reachedGoal &&
          frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress)) {
        profile.dominatedSkipped++;
        continue;
      }

      // Add to frontier if reached goal
      if (reachedGoal) {
        frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress);
      }

      hashStopwatch
        ..reset()
        ..start();
      final newKey = _stateKey(newState, goal);
      profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

      // Only enqueue if this is the best path to this state
      final existingBest = bestTicks[newKey];
      if (existingBest == null || newTicks < existingBest) {
        bestTicks[newKey] = newTicks;

        final newNode = _Node(
          state: newState,
          ticks: newTicks,
          interactions: node.interactions,
          expectedDeaths: newDeaths,
          parentId: nodeId,
          stepFromParent: MacroStep(
            macro,
            expansionResult.ticksElapsed,
            expansionResult.waitFor,
          ),
        );

        final newNodeId = nodes.length;
        nodes.add(newNode);

        if (reachedGoal) {
          // Found goal via macro - return immediately
          totalStopwatch.stop();
          profile
            ..expandedNodes = expandedNodes
            ..totalTimeUs = totalStopwatch.elapsedMicroseconds
            ..frontierInserted = frontier.inserted
            ..frontierRemoved = frontier.removed;
          return SolverSuccess(
            _reconstructPlan(nodes, newNodeId, expandedNodes, enqueuedNodes),
            profile,
          );
        }

        pq.add(newNodeId);
        enqueuedNodes++;
        neighborsThisNode++;
      }
    }

    // Expand wait edge
    final deltaResult = nextDecisionDelta(node.state, goal, candidates);

    // Invariant: dt=0 only when actions exist, dt>0 when no immediate actions.
    // Prevents regression where "affordable watched upgrade" triggers dt=0
    // but no action is available (watch ≠ action).
    final relevantInteractions = interactions
        .where((i) => _isRelevantInteraction(i, candidates))
        .toList();
    assert(
      deltaResult.deltaTicks != 0 || relevantInteractions.isNotEmpty,
      'dt=0 but no actions; watch ≠ action regression',
    );

    if (!deltaResult.isDeadEnd && deltaResult.deltaTicks > 0) {
      profile.decisionDeltas.add(deltaResult.deltaTicks);

      final advanceStopwatch = Stopwatch()..start();
      final advanceResult = advance(node.state, deltaResult.deltaTicks);
      profile.advanceTimeUs += advanceStopwatch.elapsedMicroseconds;

      final newState = advanceResult.state;
      final newDeaths = node.expectedDeaths + advanceResult.deaths;
      final newTicks = node.ticks + deltaResult.deltaTicks;
      final newProgress = goal.progress(newState);
      final newBucketKey = _bucketKeyFromState(newState, goal);

      // Check if we've reached the goal BEFORE dominance pruning
      final reachedGoal = goal.isSatisfied(newState);

      // Dominance pruning: skip if dominated by existing frontier point
      // BUT: never skip if we've reached the goal
      if (!reachedGoal &&
          frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress)) {
        profile.dominatedSkipped++;
      } else {
        // If we reached goal, still add to frontier for tracking
        if (reachedGoal) {
          frontier.isDominatedOrInsert(newBucketKey, newTicks, newProgress);
        }
        hashStopwatch
          ..reset()
          ..start();
        final newKey = _stateKey(newState, goal);
        profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

        // Safety: check for zero-progress waits (same state key after advance)
        // BUT: allow if we've reached the goal (even if state key unchanged)
        if (newKey != nodeKey || reachedGoal) {
          final existingBest = bestTicks[newKey];
          // Add if we've reached the goal (this is the terminal state we want)
          // Otherwise, only add if this is a better path to this state key
          if (reachedGoal || existingBest == null || newTicks < existingBest) {
            if (!reachedGoal) {
              bestTicks[newKey] = newTicks;
            }

            final newNode = _Node(
              state: newState,
              ticks: newTicks,
              interactions: node.interactions,
              parentId: nodeId,
              stepFromParent: WaitStep(
                deltaResult.deltaTicks,
                deltaResult.waitFor,
              ),
              expectedDeaths: newDeaths,
            );

            final newNodeId = nodes.length;
            nodes.add(newNode);
            pq.add(newNodeId);
            enqueuedNodes++;
            neighborsThisNode++;
          }
        }
      }
    }

    profile.totalNeighborsGenerated += neighborsThisNode;
  }

  // Priority queue exhausted without finding goal
  totalStopwatch.stop();
  profile
    ..expandedNodes = expandedNodes
    ..totalTimeUs = totalStopwatch.elapsedMicroseconds
    ..frontierInserted = frontier.inserted
    ..frontierRemoved = frontier.removed;
  return SolverFailed(
    SolverFailure(
      reason: 'No path to goal found',
      expandedNodes: expandedNodes,
      enqueuedNodes: enqueuedNodes,
      bestCredits: bestCredits,
    ),
    profile,
  );
}

/// Checks if an interaction is relevant given the current candidates.
bool _isRelevantInteraction(Interaction interaction, Candidates candidates) {
  return switch (interaction) {
    SwitchActivity(:final actionId) => candidates.switchToActivities.contains(
      actionId,
    ),
    BuyShopItem(:final purchaseId) => candidates.buyUpgrades.contains(
      purchaseId,
    ),
    SellAll() => candidates.includeSellAll,
  };
}

/// Reconstructs a plan from the goal node by walking parent pointers.
Plan _reconstructPlan(
  List<_Node> nodes,
  int goalNodeId,
  int expandedNodes,
  int enqueuedNodes,
) {
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
      processedSteps.add(const InteractionStep(SellAll()));
    }
    processedSteps.add(step);
  }

  final goalNode = nodes[goalNodeId];
  return Plan(
    steps: processedSteps,
    totalTicks: goalNode.ticks,
    interactionCount: goalNode.interactions,
    expandedNodes: expandedNodes,
    enqueuedNodes: enqueuedNodes,
    expectedDeaths: goalNode.expectedDeaths,
  );
}
