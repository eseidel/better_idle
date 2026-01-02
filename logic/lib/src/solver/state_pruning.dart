/// State pruning and bucketing for the A* solver.
///
/// Provides bucket keys for state grouping and Pareto frontier for dominance
/// pruning.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart' show Skill;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart'
    show SellAllPolicy, effectiveCredits;
import 'package:logic/src/solver/solver_profile.dart' show FrontierStats;
import 'package:logic/src/state.dart';

// Re-export FrontierStats for convenience
export 'package:logic/src/solver/solver_profile.dart' show FrontierStats;

/// Gold bucket size for coarse state grouping.
/// Larger values = fewer unique states = more pruning but less precision.
const int goldBucketSize = 50;

/// HP bucket size for coarse state grouping during thieving.
/// Groups HP into buckets to reduce state explosion while still
/// distinguishing "safe" vs "near death" states.
const int hpBucketSize = 10;

/// Size of inventory bucket for dominance pruning.
/// Groups inventory counts to reduce state explosion.
const int inventoryBucketSize = 10;

/// Bucket key for dominance pruning - groups states with same structural
/// situation. Goal-scoped: only tracks skills/upgrades relevant to the goal.
///
/// For WC=99/Fish=99 goal, tracks: {WC level, Fish level, axe tier, rod tier,
/// active action}.
/// For Thieving goal, tracks: {Thieving level, HP, mastery, active action}.
/// For GP goals, tracks all skills (current behavior).
class BucketKey extends Equatable {
  const BucketKey({
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

/// Creates a goal-scoped bucket key from a game state.
/// Only tracks skills, HP, mastery, and inventory relevant to the goal.
BucketKey bucketKeyFromState(GlobalState state, Goal goal) {
  // Track active action - needed to distinguish states
  final actionId = state.activeAction?.id;
  final activityName = actionId != null ? actionId.localId.name : 'none';

  // Build skill levels map for only goal-relevant skills
  final skillLevels = <Skill, int>{};
  for (final skill in goal.relevantSkillsForBucketing) {
    skillLevels[skill] = state.skillState(skill).skillLevel;
  }

  // Track HP only if goal requires it (thieving goals)
  final hpBucket = goal.shouldTrackHp ? state.playerHp ~/ hpBucketSize : 0;

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
              : 100 + (totalItems - 100) ~/ inventoryBucketSize;
        }()
      : 0;

  // Track which input item types are present for multi-input consuming skills.
  // This prevents incorrect dominance pruning where states with different ore
  // mixes (e.g., 10 copper vs 5 copper + 5 tin) are treated as equivalent.
  final inputItemMix = goal.shouldTrackInventory
      ? computeInputItemMix(state, goal)
      : 0;

  return BucketKey(
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

/// Computes a hash representing which input item types are present.
///
/// For consuming skills like smithing that require multiple input types
/// (e.g., copper ore AND tin ore), states with different mixes should not
/// dominate each other even if they have the same total item count.
///
/// This function identifies all items that could be inputs to consuming
/// actions for the goal's consuming skills, then creates a bitmask of
/// which of those input types are present (non-zero count) in inventory.
int computeInputItemMix(GlobalState state, Goal goal) {
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

/// A point on the Pareto frontier for dominance checking.
class FrontierPoint {
  FrontierPoint(this.ticks, this.progress);

  final int ticks;

  /// Progress toward goal (gold for GP goals, XP for skill goals).
  final int progress;
}

/// Manages per-bucket Pareto frontiers for dominance pruning.
/// The second dimension (progress) is goal-dependent:
/// - For GP goals: effective credits (GP + inventory value)
/// - For skill goals: current XP in the target skill
class ParetoFrontier {
  final Map<BucketKey, List<FrontierPoint>> _frontiers = {};

  // Stats
  int _inserted = 0;
  int _removed = 0;

  FrontierStats get stats =>
      FrontierStats(inserted: _inserted, removed: _removed);

  /// Checks if (ticks, progress) is dominated by existing frontier.
  /// If not dominated, inserts the point and removes any points it dominates.
  /// Returns true if dominated (caller should skip this node).
  bool isDominatedOrInsert(BucketKey key, int ticks, int progress) {
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
    frontier.add(FrontierPoint(ticks, progress));
    _inserted++;

    return false; // Not dominated
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
///    Currently uses [inventoryBucketSize] for large inventories.
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
({String key, int elapsedUs}) stateKey(GlobalState state, Goal goal) {
  final stopwatch = Stopwatch()..start();
  final buffer = StringBuffer();

  // Bucketed effective credits (GP + sellable inventory value).
  // States with equivalent purchasing power should bucket together.
  final credits = effectiveCredits(state, const SellAllPolicy());
  final goldBucket = credits ~/ goldBucketSize;
  buffer.write('gb:$goldBucket|');

  // Active action (always tracked for state deduplication)
  final actionId = state.activeAction?.id;
  buffer.write('act:${actionId ?? 'none'}|');

  // HP bucket - only if goal tracks HP (thieving)
  if (goal.shouldTrackHp && actionId != null) {
    final hpBucket = state.playerHp ~/ hpBucketSize;
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
        final invBucket = totalItems ~/ inventoryBucketSize;
        buffer.write('inv:$invBucket|');
      }
    }
  }

  return (key: buffer.toString(), elapsedUs: stopwatch.elapsedMicroseconds);
}
