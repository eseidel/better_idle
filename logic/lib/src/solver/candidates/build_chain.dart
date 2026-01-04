/// Production chain building for multi-tier item production.
///
/// This module provides `buildChainForItem` which constructs a tree of
/// production steps needed to produce a target item in a specified quantity.
///
/// Example: For Smithing, producing Bronze Daggers requires:
/// - Bronze Bars (from Smithing)
///   - Copper Ore (from Mining)
///   - Tin Ore (from Mining)
///
/// The chain captures this structure explicitly, allowing the planner to
/// emit the correct sequence of EnsureStock / SwitchActivity steps.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart' show ticksFromDuration;

/// Maximum depth for chain building to prevent stack overflow.
const int maxChainDepth = 10;

/// A node in the production chain tree.
///
/// Each node represents producing a specific item via a specific action,
/// with child nodes for any required input items.
class PlannedChain {
  const PlannedChain({
    required this.itemId,
    required this.quantity,
    required this.actionId,
    required this.children,
    required this.actionsNeeded,
    required this.ticksNeeded,
  });

  /// Deserializes a [PlannedChain] from a JSON-compatible map.
  factory PlannedChain.fromJson(Map<String, dynamic> json) => PlannedChain(
    itemId: MelvorId.fromJson(json['itemId'] as String),
    quantity: json['quantity'] as int,
    actionId: ActionId.fromJson(json['actionId'] as String),
    actionsNeeded: json['actionsNeeded'] as int,
    ticksNeeded: json['ticksNeeded'] as int,
    children: (json['children'] as List<dynamic>)
        .map((c) => PlannedChain.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  /// The item being produced at this node.
  final MelvorId itemId;

  /// How many of this item to produce.
  final int quantity;

  /// The action used to produce this item.
  final ActionId actionId;

  /// Child chains for input items (empty for leaf nodes like Mining).
  final List<PlannedChain> children;

  /// Number of action completions needed.
  final int actionsNeeded;

  /// Estimated ticks to complete this production step (not including children).
  final int ticksNeeded;

  /// Returns true if this is a leaf node (no input requirements).
  bool get isLeaf => children.isEmpty;

  /// Total estimated ticks including all children (production time).
  int get totalTicks {
    var total = ticksNeeded;
    for (final child in children) {
      total += child.totalTicks;
    }
    return total;
  }

  /// Iterates over all nodes in bottom-up order (leaves first, root last).
  ///
  /// This is the execution order: produce inputs before outputs.
  Iterable<PlannedChain> get bottomUpTraversal sync* {
    for (final child in children) {
      yield* child.bottomUpTraversal;
    }
    yield this;
  }

  /// Iterates over all nodes in top-down order (root first, leaves last).
  ///
  /// Useful for debugging and printing the chain structure.
  Iterable<PlannedChain> get topDownTraversal sync* {
    yield this;
    for (final child in children) {
      yield* child.topDownTraversal;
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    _toStringIndented(buffer, '');
    return buffer.toString();
  }

  void _toStringIndented(StringBuffer buffer, String indent) {
    buffer.writeln(
      '$indent${itemId.localId} x$quantity via ${actionId.localId.localId} '
      '($actionsNeeded actions, $ticksNeeded ticks)',
    );
    for (final child in children) {
      child._toStringIndented(buffer, '$indent  ');
    }
  }

  /// Serializes this [PlannedChain] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'itemId': itemId.toJson(),
    'quantity': quantity,
    'actionId': actionId.toJson(),
    'actionsNeeded': actionsNeeded,
    'ticksNeeded': ticksNeeded,
    'children': children.map((c) => c.toJson()).toList(),
  };
}

/// Result of attempting to build a production chain.
sealed class BuildChainResult {
  const BuildChainResult();
}

/// Successfully built the production chain.
class ChainBuilt extends BuildChainResult {
  const ChainBuilt(this.chain);

  final PlannedChain chain;
}

/// Failed to build the chain due to missing prerequisites.
class ChainNeedsUnlock extends BuildChainResult {
  const ChainNeedsUnlock({
    required this.skill,
    required this.requiredLevel,
    required this.forItem,
    required this.reason,
  });

  /// The skill that needs to be trained.
  final Skill skill;

  /// The level required to unlock the producer.
  final int requiredLevel;

  /// The item we were trying to produce.
  final MelvorId forItem;

  /// Human-readable explanation.
  final String reason;
}

/// Failed to build the chain due to an error (cycle, depth, no producer).
class ChainFailed extends BuildChainResult {
  const ChainFailed(this.reason);

  final String reason;
}

/// Builds a production chain for acquiring [quantity] of [itemId].
///
/// This function recursively discovers the full production tree:
/// 1. Finds a producer action for [itemId] (preferring unlocked)
/// 2. Reads the recipe inputs for that action
/// 3. For each input, recursively builds child chains
/// 4. Returns a [PlannedChain] node capturing the structure
///
/// ## Cycle Detection
///
/// Uses a [visited] set of (itemId, actionId) pairs to detect cycles.
/// If a cycle is detected, returns [ChainFailed].
///
/// ## Depth Limiting
///
/// Enforces a maximum depth to prevent stack overflow on degenerate
/// data. Returns [ChainFailed] if depth exceeded.
///
/// ## Unlock Prerequisites
///
/// If the best producer for an item is locked (skill level too low),
/// returns [ChainNeedsUnlock] with the required skill/level info.
/// The caller can then generate a TrainSkillUntil macro before retrying.
///
/// ## Parameters
///
/// - [state]: Current game state (for skill levels, registries)
/// - [itemId]: The item to produce
/// - [quantity]: How many to produce
/// - [goal]: The solver goal (for producer selection heuristics)
/// - [depth]: Current recursion depth (default 0)
/// - [visited]: Set of (itemId, actionId) pairs already in the chain
BuildChainResult buildChainForItem(
  GlobalState state,
  MelvorId itemId,
  int quantity,
  Goal goal, {
  int depth = 0,
  Set<(MelvorId, ActionId)>? visited,
}) {
  visited ??= <(MelvorId, ActionId)>{};

  // Depth guard
  if (depth >= maxChainDepth) {
    return ChainFailed(
      'Depth limit ($maxChainDepth) exceeded for ${itemId.localId}',
    );
  }

  // Find a producer for this item
  final producerResult = _findBestProducer(state, itemId, goal);

  switch (producerResult) {
    case _ProducerFound(:final action, :final actionId):
      // Cycle guard: check if we've already visited this (item, action) pair
      final key = (itemId, actionId);
      if (visited.contains(key)) {
        return ChainFailed(
          'Cycle detected: ${itemId.localId} via ${actionId.localId.localId}',
        );
      }
      visited.add(key);

      // Calculate how many actions needed
      final outputsPerAction = action.outputs[itemId] ?? 1;
      final actionsNeeded = (quantity / outputsPerAction).ceil();
      final ticksPerAction = ticksFromDuration(action.meanDuration);
      final ticksNeeded = actionsNeeded * ticksPerAction;

      // Build children for each input
      final children = <PlannedChain>[];
      for (final inputEntry in action.inputs.entries) {
        final inputItemId = inputEntry.key;
        final inputPerAction = inputEntry.value;
        final inputNeeded = actionsNeeded * inputPerAction;

        final childResult = buildChainForItem(
          state,
          inputItemId,
          inputNeeded,
          goal,
          depth: depth + 1,
          visited: visited,
        );

        switch (childResult) {
          case ChainBuilt(:final chain):
            children.add(chain);
          case ChainNeedsUnlock():
            // Propagate unlock requirement up
            return childResult;
          case ChainFailed():
            // Propagate failure up
            return childResult;
        }
      }

      return ChainBuilt(
        PlannedChain(
          itemId: itemId,
          quantity: quantity,
          actionId: actionId,
          children: children,
          actionsNeeded: actionsNeeded,
          ticksNeeded: ticksNeeded,
        ),
      );

    case _ProducerLocked(:final action):
      return ChainNeedsUnlock(
        skill: action.skill,
        requiredLevel: action.unlockLevel,
        forItem: itemId,
        reason:
            'Need ${action.skill.name} L${action.unlockLevel} '
            'to produce ${itemId.localId}',
      );

    case _NoProducer(:final reason):
      return ChainFailed(reason);
  }
}

// ---------------------------------------------------------------------------
// Private helpers for producer selection
// ---------------------------------------------------------------------------

/// Result of searching for a producer action.
sealed class _ProducerSearchResult {
  const _ProducerSearchResult();
}

/// Found an unlocked producer.
class _ProducerFound extends _ProducerSearchResult {
  const _ProducerFound(this.action, this.actionId);
  final SkillAction action;
  final ActionId actionId;
}

/// Found a producer but it's locked (skill level too low).
class _ProducerLocked extends _ProducerSearchResult {
  const _ProducerLocked(this.action);
  final SkillAction action;
}

/// No producer exists for this item.
class _NoProducer extends _ProducerSearchResult {
  const _NoProducer(this.reason);
  final String reason;
}

/// Finds the best producer for an item.
///
/// Prefers unlocked producers, ranked by production rate.
/// If no unlocked producer exists, returns the first locked producer found.
/// If no producer exists at all, returns [_NoProducer].
_ProducerSearchResult _findBestProducer(
  GlobalState state,
  MelvorId itemId,
  Goal goal,
) {
  int skillLevel(Skill skill) => state.skillState(skill).skillLevel;

  // Find all actions that produce this item
  final allProducers = state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.outputs.containsKey(itemId))
      .toList();

  if (allProducers.isEmpty) {
    return _NoProducer('No action produces ${itemId.localId}');
  }

  // Separate into unlocked and locked
  final unlocked = <SkillAction>[];
  final locked = <SkillAction>[];

  for (final action in allProducers) {
    if (action.unlockLevel <= skillLevel(action.skill)) {
      unlocked.add(action);
    } else {
      locked.add(action);
    }
  }

  // If we have unlocked producers, pick the best by rate
  if (unlocked.isNotEmpty) {
    SkillAction? best;
    double bestRate = 0;

    for (final action in unlocked) {
      final ticksPerAction = ticksFromDuration(action.meanDuration).toDouble();
      final outputsPerAction = action.outputs[itemId] ?? 1;
      final outputsPerTick = outputsPerAction / ticksPerAction;

      if (outputsPerTick > bestRate) {
        bestRate = outputsPerTick;
        best = action;
      }
    }

    return _ProducerFound(best!, best.id);
  }

  // No unlocked producers - return the locked one with lowest level requirement
  locked.sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));
  return _ProducerLocked(locked.first);
}

/// Converts a PlannedChain to a map of inputItem -> producerAction.
///
/// This extracts the producerByInputItem map needed for
/// TrainConsumingSkillUntil execution.
///
/// Only includes direct children (one level deep) since the executor
/// handles multi-tier chains by calling buildChain for each level.
Map<MelvorId, ActionId> chainToProducerMap(PlannedChain chain) {
  final result = <MelvorId, ActionId>{};
  for (final child in chain.children) {
    result[child.itemId] = child.actionId;
  }
  return result;
}

/// Computes total input requirements from a chain (all leaf quantities).
///
/// Returns a map from raw input item ID to total quantity needed.
/// "Raw" inputs are items at leaf nodes that don't require production
/// themselves (e.g., Mining outputs).
Map<MelvorId, int> chainToInputRequirements(PlannedChain chain) {
  final result = <MelvorId, int>{};

  void collectLeaves(PlannedChain node) {
    if (node.isLeaf) {
      result[node.itemId] = (result[node.itemId] ?? 0) + node.quantity;
    } else {
      node.children.forEach(collectLeaves);
    }
  }

  // For the root chain, collect from its children (not the root itself)
  chain.children.forEach(collectLeaves);

  return result;
}
