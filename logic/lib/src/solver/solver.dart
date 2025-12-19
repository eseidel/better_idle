import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/items.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/health.dart';
import 'package:logic/src/types/stunned.dart';

import 'apply_interaction.dart';
import 'available_interactions.dart';
import 'enumerate_candidates.dart';
import 'estimate_rates.dart';
import 'interaction.dart';
import 'next_decision_delta.dart';
import 'plan.dart';

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

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Solver Profile ===');
    buffer.writeln('Expanded nodes: $expandedNodes');
    buffer.writeln('Nodes/sec: ${nodesPerSecond.toStringAsFixed(1)}');
    buffer.writeln(
      'Avg branching factor: ${avgBranchingFactor.toStringAsFixed(2)}',
    );
    buffer.writeln(
      'nextDecisionDelta: min=$minDelta, median=$medianDelta, p95=$p95Delta',
    );
    buffer.writeln('Time breakdown:');
    buffer.writeln(
      '  advance/consumeTicks: ${advancePercent.toStringAsFixed(1)}%',
    );
    buffer.writeln(
      '  enumerateCandidates: ${enumeratePercent.toStringAsFixed(1)}%',
    );
    buffer.writeln(
      '  hashing (_stateKey): ${hashingPercent.toStringAsFixed(1)}%',
    );
    buffer.writeln('Dominance pruning:');
    buffer.writeln('  dominated skipped: $dominatedSkipped');
    buffer.writeln('  frontier inserted: $frontierInserted');
    buffer.writeln('  frontier removed: $frontierRemoved');
    return buffer.toString();
  }
}

/// Gold bucket size for coarse state grouping.
/// Larger values = fewer unique states = more pruning but less precision.
const int _goldBucketSize = 50;

/// HP bucket size for coarse state grouping during thieving.
/// Groups HP into buckets to reduce state explosion while still
/// distinguishing "safe" vs "near death" states.
const int _hpBucketSize = 10;

/// Bucket key for dominance pruning - groups states with same structural situation.
/// Includes activity, tool tiers, relevant skill levels, mastery level, and HP bucket.
class _BucketKey {
  _BucketKey({
    required this.activityName,
    required this.axeLevel,
    required this.rodLevel,
    required this.pickLevel,
    required this.woodcuttingLevel,
    required this.fishingLevel,
    required this.miningLevel,
    required this.thievingLevel,
    required this.hpBucket,
    required this.masteryLevel,
  });

  final String activityName;
  final int axeLevel;
  final int rodLevel;
  final int pickLevel;
  final int woodcuttingLevel;
  final int fishingLevel;
  final int miningLevel;
  final int thievingLevel;

  /// HP bucket for thieving - distinguishes "safe" vs "near death" states.
  /// Only meaningful when thieving; set to 0 for other activities.
  final int hpBucket;

  /// Mastery level for the current action - affects rates (especially thieving).
  final int masteryLevel;

  @override
  bool operator ==(Object other) =>
      other is _BucketKey &&
      other.activityName == activityName &&
      other.axeLevel == axeLevel &&
      other.rodLevel == rodLevel &&
      other.pickLevel == pickLevel &&
      other.woodcuttingLevel == woodcuttingLevel &&
      other.fishingLevel == fishingLevel &&
      other.miningLevel == miningLevel &&
      other.thievingLevel == thievingLevel &&
      other.hpBucket == hpBucket &&
      other.masteryLevel == masteryLevel;

  @override
  int get hashCode => Object.hash(
    activityName,
    axeLevel,
    rodLevel,
    pickLevel,
    woodcuttingLevel,
    fishingLevel,
    miningLevel,
    thievingLevel,
    hpBucket,
    masteryLevel,
  );
}

/// Creates a bucket key from a game state.
_BucketKey _bucketKeyFromState(GlobalState state) {
  // Only track HP bucket when thieving (where death is possible)
  final actionName = state.activeAction?.name;
  final isThieving =
      actionName != null && actionRegistry.byName(actionName) is ThievingAction;
  final hpBucket = isThieving ? state.playerHp ~/ _hpBucketSize : 0;

  // Get mastery level for current action (0 if no action)
  final masteryLevel = actionName != null
      ? state.actionState(actionName).masteryLevel
      : 0;

  return _BucketKey(
    activityName: actionName ?? 'none',
    axeLevel: state.shop.axeLevel,
    rodLevel: state.shop.fishingRodLevel,
    pickLevel: state.shop.pickaxeLevel,
    woodcuttingLevel: state.skillState(Skill.woodcutting).skillLevel,
    fishingLevel: state.skillState(Skill.fishing).skillLevel,
    miningLevel: state.skillState(Skill.mining).skillLevel,
    thievingLevel: state.skillState(Skill.thieving).skillLevel,
    hpBucket: hpBucket,
    masteryLevel: masteryLevel,
  );
}

/// A point on the Pareto frontier for dominance checking.
class _FrontierPoint {
  _FrontierPoint(this.ticks, this.gold);

  final int ticks;
  final int gold;
}

/// Manages per-bucket Pareto frontiers for dominance pruning.
class _ParetoFrontier {
  final Map<_BucketKey, List<_FrontierPoint>> _frontiers = {};

  // Stats
  int inserted = 0;
  int removed = 0;

  /// Checks if (ticks, gold) is dominated by existing frontier.
  /// If not dominated, inserts the point and removes any points it dominates.
  /// Returns true if dominated (caller should skip this node).
  bool isDominatedOrInsert(_BucketKey key, int ticks, int gold) {
    final frontier = _frontiers.putIfAbsent(key, () => []);

    // Check if dominated by any existing point
    // A dominates B if A.ticks <= B.ticks && A.gold >= B.gold
    for (final p in frontier) {
      if (p.ticks <= ticks && p.gold >= gold) {
        return true; // Dominated
      }
    }

    // Not dominated - remove any points that new point dominates
    final originalLength = frontier.length;
    frontier.removeWhere((p) => ticks <= p.ticks && gold >= p.gold);
    removed += originalLength - frontier.length;

    // Insert new point
    frontier.add(_FrontierPoint(ticks, gold));
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

/// Cache for best unlocked gold rate by state key (skill levels + tool tiers).
class _RateCache {
  final Map<String, double> _cache = {};

  String _rateKey(GlobalState state) {
    // Key by skill levels and tool tiers (things that affect unlocks/rates)
    return '${state.skillState(Skill.woodcutting).skillLevel}|'
        '${state.skillState(Skill.fishing).skillLevel}|'
        '${state.skillState(Skill.mining).skillLevel}|'
        '${state.skillState(Skill.thieving).skillLevel}|'
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

  /// Computes the best gold rate among currently UNLOCKED actions.
  double _computeBestUnlockedRate(GlobalState state) {
    var maxRate = 0.0;

    for (final skill in Skill.values) {
      final skillLevel = state.skillState(skill).skillLevel;

      for (final action in actionRegistry.forSkill(skill)) {
        // Skip actions that require inputs
        if (action.inputs.isNotEmpty) continue;

        // Only consider unlocked actions
        if (skillLevel < action.unlockLevel) continue;

        // Calculate expected ticks with upgrade modifier
        final baseExpectedTicks = ticksFromDuration(
          action.meanDuration,
        ).toDouble();
        final percentModifier = state.shop.durationModifierForSkill(skill);
        final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);
        if (expectedTicks <= 0) continue;

        // Calculate expected gold per action from selling outputs
        var expectedGoldPerAction = 0.0;
        for (final output in action.outputs.entries) {
          final item = itemRegistry.byName(output.key);
          expectedGoldPerAction += item.sellsFor * output.value;
        }

        // For thieving, compute expected gold with success rate and stun time
        if (action is ThievingAction) {
          final thievingLevel = state.skillState(Skill.thieving).skillLevel;
          final mastery = state.actionState(action.name).masteryLevel;
          final stealth = calculateStealth(thievingLevel, mastery);
          final successChance = ((100 + stealth) / (100 + action.perception))
              .clamp(0.0, 1.0);
          final failureChance = 1.0 - successChance;
          final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
          expectedGoldPerAction += expectedThievingGold;

          // Account for stun time on failure
          final effectiveTicks =
              expectedTicks + failureChance * stunnedDurationTicks;
          final rate = expectedGoldPerAction / effectiveTicks;
          if (rate > maxRate) {
            maxRate = rate;
          }
          continue;
        }

        final rate = expectedGoldPerAction / expectedTicks;
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
/// h(state) = ceil(remainingGold / R_bestUnlocked)
int _heuristic(GlobalState state, int goalCredits, _RateCache rateCache) {
  final bestRate = rateCache.getBestUnlockedRate(state);
  if (bestRate <= 0) return 0; // Fallback to Dijkstra if no gold rate
  final remaining = goalCredits - state.gp;
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
}

/// Computes a coarse hash key for a game state for visited tracking.
///
/// Uses bucketed gold for coarser grouping to reduce state explosion.
/// Key includes:
/// - Bucketed gold (GP / bucket size)
/// - Current activity
/// - Upgrade levels
/// - Skill levels (for level-based gating)
/// - HP bucket (for thieving, where death is possible)
/// - Mastery level for current action (affects rates)
String _stateKey(GlobalState state) {
  final buffer = StringBuffer();

  // Bucketed gold (coarse grouping for large goals)
  // Using GP directly since advanceExpected converts items to gold
  final goldBucket = state.gp ~/ _goldBucketSize;
  buffer.write('gb:$goldBucket|');

  // Active action
  final actionName = state.activeAction?.name;
  buffer.write('act:${actionName ?? 'none'}|');

  // HP bucket for thieving (where death is possible)
  final isThieving =
      actionName != null && actionRegistry.byName(actionName) is ThievingAction;
  if (isThieving) {
    final hpBucket = state.playerHp ~/ _hpBucketSize;
    buffer.write('hp:$hpBucket|');
  }

  // Mastery level for current action (affects rates, especially for thieving)
  if (actionName != null) {
    final masteryLevel = state.actionState(actionName).masteryLevel;
    buffer.write('mast:$masteryLevel|');
  }

  // Upgrade levels
  buffer.write('axe:${state.shop.axeLevel}|');
  buffer.write('rod:${state.shop.fishingRodLevel}|');
  buffer.write('pick:${state.shop.pickaxeLevel}|');

  // Skill levels (just levels, not full XP for coarser grouping)
  for (final skill in Skill.values) {
    final level = state.skillState(skill).skillLevel;
    if (level > 1) {
      buffer.write('${skill.name}:$level|');
    }
  }

  return buffer.toString();
}

/// Checks if an activity can be modeled with expected-value rates.
/// Returns true for non-combat gathering/thieving activities.
bool _isRateModelable(GlobalState state) {
  final activeAction = state.activeAction;
  if (activeAction == null) return false;

  final action = actionRegistry.byName(activeAction.name);

  // Only skill actions (non-combat) are rate-modelable
  // Skip actions that require inputs (firemaking, cooking, smithing)
  if (action is! SkillAction) return false;
  if (action.inputs.isNotEmpty) return false;

  return true;
}

/// O(1) expected-value fast-forward for rate-modelable activities.
/// Updates gold and skill XP based on expected rates without full simulation.
/// For thieving, handles death by stopping the activity when HP would reach 0.
GlobalState _advanceExpected(GlobalState state, int deltaTicks) {
  if (deltaTicks <= 0) return state;

  final rates = estimateRates(state);

  // Check for death during thieving
  final ticksToDeath = ticksUntilDeath(state, rates);
  var effectiveTicks = deltaTicks;
  var playerDied = false;

  if (ticksToDeath != null && ticksToDeath <= deltaTicks) {
    // Player will die during this advance - only apply ticks until death
    effectiveTicks = ticksToDeath;
    playerDied = true;
  }

  // Compute expected gold gain (convert outputs to gold immediately)
  final expectedGold = (rates.goldPerTick * effectiveTicks).floor();
  final newGp = state.gp + expectedGold;

  // Compute expected skill XP gains
  final newSkillStates = Map<Skill, SkillState>.from(state.skillStates);
  for (final entry in rates.xpPerTickBySkill.entries) {
    final skill = entry.key;
    final xpPerTick = entry.value;
    final xpGain = (xpPerTick * effectiveTicks).floor();
    if (xpGain > 0) {
      final current = state.skillState(skill);
      final newXp = current.xp + xpGain;
      newSkillStates[skill] = current.copyWith(xp: newXp);
    }
  }

  // Compute expected mastery XP gains
  var newActionStates = state.actionStates;
  if (rates.masteryXpPerTick > 0 && rates.actionName != null) {
    final masteryXpGain = (rates.masteryXpPerTick * effectiveTicks).floor();
    if (masteryXpGain > 0) {
      final actionName = rates.actionName!;
      final currentActionState = state.actionState(actionName);
      final newMasteryXp = currentActionState.masteryXp + masteryXpGain;
      newActionStates = Map.from(state.actionStates);
      newActionStates[actionName] = currentActionState.copyWith(
        masteryXp: newMasteryXp,
      );
    }
  }

  // Handle death: reset HP and stop activity
  // Note: can't use copyWith(activeAction: null) because null means "keep existing"
  if (playerDied) {
    return GlobalState(
      gp: newGp,
      skillStates: newSkillStates,
      activeAction: null, // Activity stops on death
      health: const HealthState.full(), // HP resets on death
      inventory: state.inventory,
      actionStates: newActionStates,
      updatedAt: DateTime.timestamp(),
      shop: state.shop,
      equipment: state.equipment,
      stunned: state.stunned,
    );
  }

  // Compute expected HP loss for thieving (even when not dying)
  HealthState? newHealth;
  if (rates.hpLossPerTick > 0) {
    final hpLoss = (rates.hpLossPerTick * effectiveTicks).floor();
    if (hpLoss > 0) {
      final newLostHp = state.health.lostHp + hpLoss;
      newHealth = HealthState(lostHp: newLostHp);
    }
  }

  // Return updated state (ignore inventory - gold is computed directly)
  return state.copyWith(
    gp: newGp,
    skillStates: newSkillStates,
    actionStates: newActionStates,
    health: newHealth,
  );
}

/// Full simulation advance using consumeTicks.
GlobalState _advanceFullSim(GlobalState state, int deltaTicks) {
  if (deltaTicks <= 0) return state;

  // Use a fixed random for deterministic planning
  final random = Random(42);

  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, deltaTicks, random: random);
  return builder.build();
}

/// Advances the game state by a given number of ticks.
/// Uses O(1) expected-value advance for rate-modelable activities,
/// falls back to full simulation for combat/complex activities.
GlobalState advance(GlobalState state, int deltaTicks) {
  if (deltaTicks <= 0) return state;

  if (_isRateModelable(state)) {
    return _advanceExpected(state, deltaTicks);
  }
  return _advanceFullSim(state, deltaTicks);
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
  final goal = Goal(targetCredits: goalCredits);
  final profile = SolverProfile();
  final totalStopwatch = Stopwatch()..start();

  // Check if goal is already satisfied (considering inventory value)
  if (_effectiveCredits(initial) >= goalCredits) {
    return SolverSuccess(const Plan.empty(), profile);
  }

  // Rate cache for A* heuristic (caches best unlocked rate by state)
  final rateCache = _RateCache();

  // Dominance pruning frontier
  final frontier = _ParetoFrontier();

  // Node storage - indices are node IDs
  final nodes = <_Node>[];

  // A* priority: f(n) = g(n) + h(n) = ticksSoFar + heuristic
  // Break ties by lower ticksSoFar (prefer actual progress over estimates)
  final pq = PriorityQueue<int>((a, b) {
    final fA =
        nodes[a].ticks + _heuristic(nodes[a].state, goalCredits, rateCache);
    final fB =
        nodes[b].ticks + _heuristic(nodes[b].state, goalCredits, rateCache);
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
  final rootKey = _stateKey(initial);
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
    hashStopwatch.reset();
    hashStopwatch.start();
    final nodeKey = _stateKey(node.state);
    profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

    final nodeCredits = _effectiveCredits(node.state);
    final nodeReachedGoal = nodeCredits >= goalCredits;

    final bestForKey = bestTicks[nodeKey];
    if (!nodeReachedGoal && bestForKey != null && bestForKey < node.ticks) {
      continue;
    }

    expandedNodes++;
    var neighborsThisNode = 0;

    // Track best credits seen (effective credits = GP + inventory value)
    final nodeEffectiveCredits = _effectiveCredits(node.state);
    if (nodeEffectiveCredits > bestCredits) {
      bestCredits = nodeEffectiveCredits;
    }

    // Check if goal is reached (considering inventory value)
    if (nodeEffectiveCredits >= goalCredits) {
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
    final candidates = enumerateCandidates(node.state);
    profile.enumerateCandidatesTimeUs += enumStopwatch.elapsedMicroseconds;

    // Expand interaction edges (0 time cost)
    final interactions = availableInteractions(node.state);
    for (final interaction in interactions) {
      // Only consider interactions that are in our candidate set (for pruning)
      if (!_isRelevantInteraction(interaction, candidates)) continue;

      try {
        final newState = applyInteraction(node.state, interaction);
        final newGold = _effectiveCredits(newState);
        final newBucketKey = _bucketKeyFromState(newState);

        // Dominance pruning: skip if dominated by existing frontier point
        if (frontier.isDominatedOrInsert(newBucketKey, node.ticks, newGold)) {
          profile.dominatedSkipped++;
          continue;
        }

        hashStopwatch.reset();
        hashStopwatch.start();
        final newKey = _stateKey(newState);
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
      } catch (_) {
        // Interaction failed (e.g., can't afford upgrade) - skip
        continue;
      }
    }

    // Expand wait edge
    final deltaResult = nextDecisionDelta(node.state, goal, candidates);

    if (!deltaResult.isDeadEnd && deltaResult.deltaTicks > 0) {
      profile.decisionDeltas.add(deltaResult.deltaTicks);

      final advanceStopwatch = Stopwatch()..start();
      final newState = advance(node.state, deltaResult.deltaTicks);
      profile.advanceTimeUs += advanceStopwatch.elapsedMicroseconds;

      final newTicks = node.ticks + deltaResult.deltaTicks;
      final newGold = _effectiveCredits(newState);
      final newBucketKey = _bucketKeyFromState(newState);

      // Check if we've reached the goal BEFORE dominance pruning
      final reachedGoal = newGold >= goalCredits;

      // Dominance pruning: skip if dominated by existing frontier point
      // BUT: never skip if we've reached the goal
      if (!reachedGoal &&
          frontier.isDominatedOrInsert(newBucketKey, newTicks, newGold)) {
        profile.dominatedSkipped++;
      } else {
        // If we reached goal, still add to frontier for tracking
        if (reachedGoal) {
          frontier.isDominatedOrInsert(newBucketKey, newTicks, newGold);
        }
        hashStopwatch.reset();
        hashStopwatch.start();
        final newKey = _stateKey(newState);
        profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

        // Safety: check for zero-progress waits (same state key after advance)
        // BUT: always allow if we've reached the goal (even if state key unchanged)
        if (newKey != nodeKey || reachedGoal) {
          final existingBest = bestTicks[newKey];
          // Always add if we've reached the goal (this is the terminal state we want)
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
                reason: deltaResult.waitReason,
              ),
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
    SwitchActivity(:final actionName) => candidates.switchToActivities.contains(
      actionName,
    ),
    BuyUpgrade(:final type) => candidates.buyUpgrades.contains(type),
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

  final goalNode = nodes[goalNodeId];
  return Plan(
    steps: reversedSteps,
    totalTicks: goalNode.ticks,
    interactionCount: goalNode.interactions,
    expandedNodes: expandedNodes,
    enqueuedNodes: enqueuedNodes,
  );
}
