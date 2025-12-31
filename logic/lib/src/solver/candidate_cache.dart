/// Capability cache for enumerateCandidates results.
///
/// ## Purpose
///
/// `enumerateCandidates` is expensive (~29% of solver time) and called on
/// every A* expansion (~100k+ times for large goals). Many expansions share
/// the same capability state (skill levels, upgrades), allowing cached
/// results to be reused after dynamic filtering.
///
/// ## Cache Key Design (Capability-Based)
///
/// The cache key captures only **capability dimensions** that affect which
/// candidates are *possible*:
/// - Goal-relevant skill levels (determines unlocks)
/// - Purchased upgrade tiers per skill (affects rates/rankings)
/// - Inventory fullness bucket (affects sell policy)
///
/// Items NOT in the key (filtered dynamically instead):
/// - Active action ID (excluded from switchToActivities)
/// - Input availability (affects canStartNow, but cached superset includes all)
/// - Exact GP amount (affordability is a filter, not a key)
///
/// ## Filtering
///
/// The cached `Candidates` is a **superset**. When retrieved, we filter:
/// - `switchToActivities`: remove current `activeActionId`
///
/// This ensures high cache hit rates while maintaining correctness.
library;

import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Cache for enumerateCandidates results.
///
/// Returns capability-based cached results with dynamic filtering applied.
class CandidateCache {
  final Map<CandidateCacheKey, Candidates> _cache = {};

  /// Stats for debugging.
  int hits = 0;
  int misses = 0;
  int keyTimeUs = 0;

  /// Verification stats (sampled checks).
  int verifyChecks = 0;
  int verifyFailures = 0;

  /// Returns cached candidates (filtered) or computes and caches them.
  ///
  /// The [state] is used for dynamic filtering (e.g., excluding active action).
  /// The [computeForState] function is called with a modified state (active
  /// action cleared) to compute the superset of candidates. This ensures the
  /// cached candidates include all possible activities, which are then filtered
  /// based on the actual active action.
  Candidates getOrCompute(
    GlobalState state,
    Goal goal,
    Candidates Function(GlobalState) computeForState,
  ) {
    final keyStopwatch = Stopwatch()..start();
    final key = CandidateCacheKey.fromState(state, goal);
    keyTimeUs += keyStopwatch.elapsedMicroseconds;

    final cached = _cache[key];
    if (cached != null) {
      hits++;
      // Apply dynamic filters to cached superset
      return _filterCandidates(cached, state);
    }
    misses++;
    // Compute with cleared active action to get the full superset.
    // enumerateCandidates excludes the active action, so we need to clear it
    // to cache the full set of candidates.
    final stateForCompute = state.activeAction != null
        ? state.clearAction()
        : state;
    final result = computeForState(stateForCompute);
    _cache[key] = result;
    // Return filtered result (same filtering as cache hit path)
    return _filterCandidates(result, state);
  }

  /// Filters cached candidates based on current state.
  ///
  /// Removes the current active action from switchToActivities.
  Candidates _filterCandidates(Candidates candidates, GlobalState state) {
    final activeActionId = state.activeAction?.id;

    // Fast path: no active action, no filtering needed
    if (activeActionId == null) {
      return candidates;
    }

    // Filter out the active action from switchToActivities
    final filteredActivities = candidates.switchToActivities
        .where((id) => id != activeActionId)
        .toList();

    // If nothing was filtered, return original to save allocation
    if (filteredActivities.length == candidates.switchToActivities.length) {
      return candidates;
    }

    return Candidates(
      switchToActivities: filteredActivities,
      buyUpgrades: candidates.buyUpgrades,
      sellPolicy: candidates.sellPolicy,
      watch: candidates.watch,
      macros: candidates.macros,
      consumingSkillStats: candidates.consumingSkillStats,
    );
  }

  /// Performs a sampled verification that filtered cache matches fresh compute.
  ///
  /// Call this periodically during solving to catch cache key bugs.
  /// Returns true if verification passed (or was skipped due to sampling).
  bool sampleVerify(
    GlobalState state,
    Goal goal,
    Candidates cached,
    Candidates Function() freshCompute, {
    double sampleRate = 0.01,
  }) {
    // Sample at the given rate
    if (math.Random().nextDouble() > sampleRate) {
      return true;
    }

    verifyChecks++;
    final fresh = freshCompute();

    // Compare filtered cached vs fresh (both should be filtered)
    final cachedFiltered = _filterCandidates(cached, state);

    // Check switchToActivities match (order may differ, compare as sets)
    final cachedSet = cachedFiltered.switchToActivities.toSet();
    final freshSet = fresh.switchToActivities.toSet();

    if (!_setsEqual(cachedSet, freshSet)) {
      verifyFailures++;
      return false;
    }

    // Check buyUpgrades match
    final cachedUpgrades = cachedFiltered.buyUpgrades.toSet();
    final freshUpgrades = fresh.buyUpgrades.toSet();

    if (!_setsEqual(cachedUpgrades, freshUpgrades)) {
      verifyFailures++;
      return false;
    }

    return true;
  }

  bool _setsEqual<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  /// Clears the cache (call when starting a new solve).
  void clear() {
    _cache.clear();
    hits = 0;
    misses = 0;
    verifyChecks = 0;
    verifyFailures = 0;
  }

  /// Number of unique keys in the cache.
  int get size => _cache.length;

  /// Cache hit rate as a percentage (0-100).
  double get hitRate {
    final total = hits + misses;
    if (total == 0) return 0;
    return (hits / total) * 100;
  }
}

/// Key for caching enumerateCandidates results.
///
/// Captures only capability dimensions that affect which candidates are
/// possible. State-specific filters (active action, input availability)
/// are applied dynamically after cache lookup.
@immutable
class CandidateCacheKey extends Equatable {
  const CandidateCacheKey({
    required this.skillLevelBucket,
    required this.inventoryBucket,
    required this.upgradeTiers,
  });

  /// Creates a cache key from the current state and goal.
  factory CandidateCacheKey.fromState(GlobalState state, Goal goal) {
    // Compute skill level bucket for goal-relevant skills
    final skillLevelBucket = <Skill, int>{};
    for (final skill in goal.relevantSkillsForBucketing) {
      skillLevelBucket[skill] = state.skillState(skill).skillLevel;
    }

    // For consuming skills, also track producer skill levels
    // (affects which producer actions are available)
    switch (goal) {
      case ReachSkillLevelGoal(:final skill):
        if (skill.isConsuming) {
          _addProducerSkillLevels(skill, state, skillLevelBucket);
        }
      case MultiSkillGoal(:final subgoals):
        for (final subgoal in subgoals) {
          if (subgoal.skill.isConsuming) {
            _addProducerSkillLevels(subgoal.skill, state, skillLevelBucket);
          }
        }
      case ReachGpGoal():
        // GP goals consider all skills, already included
        break;
      case SegmentGoal(:final innerGoal):
        // Delegate to inner goal's consuming skill logic
        switch (innerGoal) {
          case ReachSkillLevelGoal(:final skill):
            if (skill.isConsuming) {
              _addProducerSkillLevels(skill, state, skillLevelBucket);
            }
          case MultiSkillGoal(:final subgoals):
            for (final subgoal in subgoals) {
              if (subgoal.skill.isConsuming) {
                _addProducerSkillLevels(subgoal.skill, state, skillLevelBucket);
              }
            }
          case ReachGpGoal():
          case SegmentGoal():
            // GP goals or nested SegmentGoal - no special handling
            break;
        }
    }

    // Compute inventory bucket (0-4 based on fullness percentage)
    final inventoryBucket = _computeInventoryBucket(state);

    // Compute upgrade tiers for relevant skills
    final upgradeTiers = _computeUpgradeTiers(state, goal);

    return CandidateCacheKey(
      skillLevelBucket: skillLevelBucket,
      inventoryBucket: inventoryBucket,
      upgradeTiers: upgradeTiers,
    );
  }

  /// Skill levels for goal-relevant skills.
  final Map<Skill, int> skillLevelBucket;

  /// Inventory fullness bucket (0=empty, 4=full).
  final int inventoryBucket;

  /// Upgrade tier counts per skill (number of tier-upgrades purchased).
  final Map<Skill, int> upgradeTiers;

  @override
  List<Object?> get props => [skillLevelBucket, inventoryBucket, upgradeTiers];
}

/// Adds producer skill levels for a consuming skill.
void _addProducerSkillLevels(
  Skill consumingSkill,
  GlobalState state,
  Map<Skill, int> levels,
) {
  // Map consuming skills to their primary producer skills
  final producerSkill = switch (consumingSkill) {
    Skill.firemaking => Skill.woodcutting,
    Skill.cooking => Skill.fishing,
    Skill.smithing => Skill.mining,
    _ => null,
  };
  if (producerSkill != null && !levels.containsKey(producerSkill)) {
    levels[producerSkill] = state.skillState(producerSkill).skillLevel;
  }
}

/// Computes inventory fullness bucket (0-4).
int _computeInventoryBucket(GlobalState state) {
  if (state.inventoryCapacity == 0) return 0;
  final fraction = state.inventoryUsed / state.inventoryCapacity;
  if (fraction < 0.2) return 0;
  if (fraction < 0.4) return 1;
  if (fraction < 0.6) return 2;
  if (fraction < 0.8) return 3;
  return 4;
}

/// Computes upgrade tier counts for relevant skills.
Map<Skill, int> _computeUpgradeTiers(GlobalState state, Goal goal) {
  final tiers = <Skill, int>{};

  // For now, track tool upgrades (axes, pickaxes, rods, etc.)
  // These are the main upgrades that affect candidate ranking.
  for (final skill in goal.relevantSkillsForBucketing) {
    tiers[skill] = _countToolUpgrades(state, skill);
  }

  return tiers;
}

/// Counts the number of tool upgrades purchased for a skill.
int _countToolUpgrades(GlobalState state, Skill skill) {
  // Tool upgrade purchase IDs follow a pattern: melvorD:{Material}_{ToolName}
  // We count how many tiers are purchased.
  final toolPurchases = switch (skill) {
    Skill.woodcutting => [
      'melvorD:Iron_Axe',
      'melvorD:Steel_Axe',
      'melvorD:Mithril_Axe',
      'melvorD:Adamant_Axe',
      'melvorD:Rune_Axe',
      'melvorD:Dragon_Axe',
    ],
    Skill.fishing => ['melvorD:Amulet_of_Fishing'],
    Skill.mining => [
      'melvorD:Iron_Pickaxe',
      'melvorD:Steel_Pickaxe',
      'melvorD:Mithril_Pickaxe',
      'melvorD:Adamant_Pickaxe',
      'melvorD:Rune_Pickaxe',
      'melvorD:Dragon_Pickaxe',
    ],
    _ => <String>[],
  };

  var count = 0;
  for (final purchaseId in toolPurchases) {
    final melvorId = MelvorId(purchaseId);
    if (state.shop.purchaseCount(melvorId) > 0) {
      count++;
    }
  }
  return count;
}
