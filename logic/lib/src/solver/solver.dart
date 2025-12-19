import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/state.dart';

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
    return buffer.toString();
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
/// Uses Dijkstra's algorithm to find the minimum-ticks path from the initial
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

  // Node storage - indices are node IDs
  final nodes = <_Node>[];

  // Priority queue ordered by ticks (min-heap)
  final pq = PriorityQueue<int>(
    (a, b) => nodes[a].ticks.compareTo(nodes[b].ticks),
  );

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
        ..totalTimeUs = totalStopwatch.elapsedMicroseconds;
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
        ..totalTimeUs = totalStopwatch.elapsedMicroseconds;
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
        ..totalTimeUs = totalStopwatch.elapsedMicroseconds;
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

      hashStopwatch.reset();
      hashStopwatch.start();
      final newKey = _stateKey(newState);
      profile.hashingTimeUs += hashStopwatch.elapsedMicroseconds;

      final newTicks = node.ticks + deltaResult.deltaTicks;

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

    profile.totalNeighborsGenerated += neighborsThisNode;
  }

  // Priority queue exhausted without finding goal
  totalStopwatch.stop();
  profile
    ..expandedNodes = expandedNodes
    ..totalTimeUs = totalStopwatch.elapsedMicroseconds;
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
