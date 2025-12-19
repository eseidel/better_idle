import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/items.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';

import 'apply_interaction.dart';
import 'available_interactions.dart';
import 'enumerate_candidates.dart';
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

/// Bucket key for dominance pruning - groups states with same structural situation.
class _BucketKey {
  _BucketKey({
    required this.activityName,
    required this.axeLevel,
    required this.rodLevel,
    required this.pickLevel,
  });

  final String activityName;
  final int axeLevel;
  final int rodLevel;
  final int pickLevel;

  @override
  bool operator ==(Object other) =>
      other is _BucketKey &&
      other.activityName == activityName &&
      other.axeLevel == axeLevel &&
      other.rodLevel == rodLevel &&
      other.pickLevel == pickLevel;

  @override
  int get hashCode => Object.hash(activityName, axeLevel, rodLevel, pickLevel);
}

/// Creates a bucket key from a game state.
_BucketKey _bucketKeyFromState(GlobalState state) {
  return _BucketKey(
    activityName: state.activeAction?.name ?? 'none',
    axeLevel: state.shop.axeLevel,
    rodLevel: state.shop.fishingRodLevel,
    pickLevel: state.shop.pickaxeLevel,
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

/// Computes R_max: the maximum gold rate per tick across ALL actions.
/// This is an optimistic upper bound ignoring unlocks/upgrades/gating.
double _computeMaxGoldRate() {
  var maxRate = 0.0;

  for (final skill in Skill.values) {
    for (final action in actionRegistry.forSkill(skill)) {
      // Skip actions that require inputs
      if (action.inputs.isNotEmpty) continue;

      final expectedTicks = ticksFromDuration(action.meanDuration).toDouble();
      if (expectedTicks <= 0) continue;

      // Calculate expected gold per action from selling outputs
      var expectedGoldPerAction = 0.0;
      for (final output in action.outputs.entries) {
        final item = itemRegistry.byName(output.key);
        expectedGoldPerAction += item.sellsFor * output.value;
      }

      // For thieving, use optimistic estimate (assume 100% success, max gold)
      if (action is ThievingAction) {
        expectedGoldPerAction += action.maxGold.toDouble();
      }

      final rate = expectedGoldPerAction / expectedTicks;
      if (rate > maxRate) {
        maxRate = rate;
      }
    }
  }

  return maxRate;
}

/// A* heuristic: optimistic lower bound on ticks to reach goal.
/// h(state) = ceil(remainingGold / R_max)
int _heuristic(GlobalState state, int goalCredits, double rMax) {
  if (rMax <= 0) return 0; // Fallback to Dijkstra if no gold rate
  final remaining = goalCredits - _effectiveCredits(state);
  if (remaining <= 0) return 0;
  return (remaining / rMax).ceil();
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

/// Computes a hash key for a game state for visited tracking.
///
/// For v0, we use a simple hash based on:
/// - Effective credits (GP + inventory value)
/// - Current activity
/// - Upgrade levels
/// - Skill levels (for level-based gating)
String _stateKey(GlobalState state) {
  final buffer = StringBuffer();

  // Effective credits (GP + sellable inventory value)
  buffer.write('ec:${_effectiveCredits(state)}|');

  // Active action
  buffer.write('act:${state.activeAction?.name ?? 'none'}|');

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

/// Advances the game state by a given number of ticks.
///
/// This is a deterministic wrapper around consumeTicks that uses a fixed
/// random seed for planning purposes.
GlobalState advance(GlobalState state, int deltaTicks) {
  if (deltaTicks <= 0) return state;

  // Use a fixed random for deterministic planning
  final random = Random(42);

  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, deltaTicks, random: random);
  return builder.build();
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

  // Precompute R_max for A* heuristic
  final rMax = _computeMaxGoldRate();

  // Dominance pruning frontier
  final frontier = _ParetoFrontier();

  // Node storage - indices are node IDs
  final nodes = <_Node>[];

  // A* priority: f(n) = g(n) + h(n) = ticksSoFar + heuristic
  // Break ties by lower ticksSoFar (prefer actual progress over estimates)
  final pq = PriorityQueue<int>((a, b) {
    final fA = nodes[a].ticks + _heuristic(nodes[a].state, goalCredits, rMax);
    final fB = nodes[b].ticks + _heuristic(nodes[b].state, goalCredits, rMax);
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
    hashStopwatch.reset();
    hashStopwatch.start();
    final nodeKey = _stateKey(node.state);
    profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

    final bestForKey = bestTicks[nodeKey];
    if (bestForKey != null && bestForKey < node.ticks) {
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

      // Dominance pruning: skip if dominated by existing frontier point
      if (frontier.isDominatedOrInsert(newBucketKey, newTicks, newGold)) {
        profile.dominatedSkipped++;
      } else {
        hashStopwatch.reset();
        hashStopwatch.start();
        final newKey = _stateKey(newState);
        profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

        // Safety: check for zero-progress waits (same state key after advance)
        if (newKey != nodeKey) {
          final existingBest = bestTicks[newKey];
          if (existingBest == null || newTicks < existingBest) {
            bestTicks[newKey] = newTicks;

            final newNode = _Node(
              state: newState,
              ticks: newTicks,
              interactions: node.interactions,
              parentId: nodeId,
              stepFromParent: WaitStep(deltaResult.deltaTicks),
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

  // Merge consecutive wait steps
  final mergedSteps = _mergeWaitSteps(reversedSteps);

  final goalNode = nodes[goalNodeId];
  return Plan(
    steps: mergedSteps,
    totalTicks: goalNode.ticks,
    interactionCount: goalNode.interactions,
    expandedNodes: expandedNodes,
    enqueuedNodes: enqueuedNodes,
  );
}

/// Merges consecutive WaitStep entries into single steps.
List<PlanStep> _mergeWaitSteps(List<PlanStep> steps) {
  if (steps.isEmpty) return steps;

  final merged = <PlanStep>[];
  var accumulatedWait = 0;

  for (final step in steps) {
    if (step is WaitStep) {
      accumulatedWait += step.deltaTicks;
    } else {
      // Flush any accumulated wait
      if (accumulatedWait > 0) {
        merged.add(WaitStep(accumulatedWait));
        accumulatedWait = 0;
      }
      merged.add(step);
    }
  }

  // Flush final accumulated wait
  if (accumulatedWait > 0) {
    merged.add(WaitStep(accumulatedWait));
  }

  return merged;
}
