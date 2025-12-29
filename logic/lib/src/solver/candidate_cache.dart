/// Cache for enumerateCandidates results to reduce redundant computation.
///
/// ## Purpose
///
/// `enumerateCandidates` is expensive (~29% of solver time) and called on
/// every A* expansion (~100k+ times for large goals). Many expansions share
/// the same relevant state (skill levels, upgrades, inventory bucket),
/// allowing cached results to be reused.
///
/// ## Cache Key Design
///
/// The cache key captures everything that affects candidate enumeration:
/// - Goal-relevant skill levels (bucketed)
/// - Purchased upgrade tiers per skill
/// - Inventory fullness bucket (0-4)
///
/// Items NOT in the key (because they don't affect candidates):
/// - Exact GP amount (only affects affordability, handled separately)
/// - Exact XP amounts (only the level matters)
/// - Active action (candidates are for what we COULD switch to)
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Cache for enumerateCandidates results.
///
/// Keyed by state buckets that affect candidate enumeration.
class CandidateCache {
  final Map<CandidateCacheKey, Candidates> _cache = {};

  /// Stats for debugging.
  int hits = 0;
  int misses = 0;
  int keyTimeUs = 0;

  /// Returns cached candidates or computes and caches them.
  Candidates getOrCompute(
    GlobalState state,
    Goal goal,
    Candidates Function() compute,
  ) {
    final keyStopwatch = Stopwatch()..start();
    final key = CandidateCacheKey.fromState(state, goal);
    keyTimeUs += keyStopwatch.elapsedMicroseconds;

    final cached = _cache[key];
    if (cached != null) {
      hits++;
      return cached;
    }
    misses++;
    final result = compute();
    _cache[key] = result;
    return result;
  }

  /// Clears the cache (call when starting a new solve).
  void clear() {
    _cache.clear();
    hits = 0;
    misses = 0;
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
/// Captures the state dimensions that affect candidate enumeration.
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
