/// WatchSet: unified boundary detection for segment-based planning.
///
/// ## Purpose
///
/// A WatchSet defines what boundaries are "material" for a segment.
/// Both planning (_SegmentGoal.isSatisfied) and execution (executeSegment)
/// use the SAME WatchSet instance, ensuring identical boundary logic.
///
/// ## Key Design
///
/// WatchSet is computed from registries/goal directly, NOT from
/// enumerateCandidates(). This keeps segment logic decoupled from
/// candidate enumeration.
///
/// ## Boundary Detection
///
/// - For goal: checks goal.isSatisfied()
/// - For upgrades: checks if watched upgrade is affordable
/// - For unlocks: detects level TRANSITIONS (not snapshots)
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/interactions/interaction.dart'
    show
        ReserveConsumingInputsSpec,
        SellPolicy,
        SellPolicySpec,
        effectiveCredits;
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Configuration for segment stopping behavior.
@immutable
class SegmentConfig {
  const SegmentConfig({
    this.stopAtUpgradeAffordable = true,
    this.stopAtUnlockBoundary = true,
    this.stopAtInputsDepleted = true,
    this.stopAtInventoryPressure = false,
    this.maxSegmentTicks,
    this.inventoryPressureThreshold = 0.9,
    this.sellPolicySpec = const ReserveConsumingInputsSpec(),
  });

  /// Whether to stop when a watched upgrade becomes affordable.
  final bool stopAtUpgradeAffordable;

  /// Whether to stop when a skill level crosses an unlock boundary.
  final bool stopAtUnlockBoundary;

  /// Whether to stop when a consuming action runs out of inputs.
  final bool stopAtInputsDepleted;

  /// Whether to stop when inventory is getting full.
  ///
  /// When true, segment will stop when inventory usage exceeds
  /// [inventoryPressureThreshold]. This allows the solver to plan
  /// a sell action before hitting hard inventory-full.
  final bool stopAtInventoryPressure;

  /// Maximum ticks for a single segment (horizon cap).
  ///
  /// If set, segments will stop after this many ticks even if no
  /// other boundary is reached. This prevents unbounded planning
  /// and allows periodic replanning.
  ///
  /// If null, no tick limit is applied.
  final int? maxSegmentTicks;

  /// Threshold for inventory pressure (0.0 to 1.0).
  ///
  /// When [stopAtInventoryPressure] is true, segment stops when
  /// inventory usage exceeds this percentage. Default is 0.9 (90%).
  final double inventoryPressureThreshold;

  /// The sell policy specification to use for this segment.
  ///
  /// This determines the liquidation philosophy - which items to keep vs sell.
  /// The concrete [SellPolicy] is computed once at segment start using
  /// [SellPolicySpec.instantiate].
  ///
  /// Defaults to [ReserveConsumingInputsSpec] which preserves inputs for
  /// consuming skills.
  final SellPolicySpec sellPolicySpec;
}

/// A WatchSet defines what boundaries are "material" for a segment.
///
/// This is the SINGLE source of truth for:
/// - Which upgrades to watch for affordability
/// - Which skill levels trigger unlock boundaries
/// - Whether a ReplanBoundary from _applyStep is material
///
/// Both planning (_SegmentGoal.isSatisfied) and execution (executeSegment)
/// use the SAME WatchSet instance.
@immutable
class WatchSet {
  const WatchSet({
    required this.goal,
    required this.config,
    required this.upgradePurchaseIds,
    required this.unlockLevels,
    required this.watchedSkills,
    required this.previousLevels,
    required this.registries,
    required this.sellPolicy,
  });

  /// The goal we're trying to reach.
  final Goal goal;

  /// Configuration for stopping behavior.
  final SegmentConfig config;

  /// Upgrade purchase IDs to watch for affordability.
  final Set<MelvorId> upgradePurchaseIds;

  /// Map of skill -> set of levels that unlock things.
  final Map<Skill, Set<int>> unlockLevels;

  /// Skills to watch for unlock boundaries.
  final Set<Skill> watchedSkills;

  /// Skill levels at segment start (for transition detection).
  final Map<Skill, int> previousLevels;

  /// Registries for looking up purchase names.
  final Registries registries;

  /// Sell policy from the goal, used for effectiveCredits calculation.
  /// This determines which items count as sellable for boundary detection.
  final SellPolicy sellPolicy;

  /// Detects if a state has hit a material boundary.
  ///
  /// Used by _SegmentGoal.isSatisfied() during planning.
  /// For unlock boundaries, detects TRANSITIONS
  /// (previousLevel < boundary <= currentLevel).
  ///
  /// The optional [elapsedTicks] parameter is used for horizon cap detection.
  /// If not provided, horizon cap is not checked.
  SegmentBoundary? detectBoundary(GlobalState state, {int? elapsedTicks}) {
    // 1. Goal reached?
    if (goal.isSatisfied(state)) {
      return const GoalReachedBoundary();
    }

    // 2. Horizon cap reached?
    final maxTicks = config.maxSegmentTicks;
    if (maxTicks != null && elapsedTicks != null) {
      if (elapsedTicks >= maxTicks) {
        return HorizonCapBoundary(elapsedTicks);
      }
    }

    // 3. Inventory pressure?
    if (config.stopAtInventoryPressure) {
      final usedSlots = state.inventoryUsed;
      final totalSlots = state.inventoryCapacity;
      if (totalSlots > 0) {
        final usage = usedSlots / totalSlots;
        if (usage >= config.inventoryPressureThreshold) {
          return InventoryPressureBoundary(usedSlots, totalSlots);
        }
      }
    }

    // 4. Upgrade affordable? (only for watched upgrades)
    // Use effective credits (GP + sellable inventory) since selling is instant
    // The sell policy determines which items are sellable
    if (config.stopAtUpgradeAffordable) {
      final effectiveGp = effectiveCredits(state, sellPolicy);
      for (final upgradeId in upgradePurchaseIds) {
        final purchase = registries.shop.byId(upgradeId);
        if (purchase != null) {
          final gpCost = purchase.cost.gpCost;
          if (gpCost != null && effectiveGp >= gpCost) {
            return UpgradeAffordableBoundary(upgradeId, purchase.name);
          }
        }
      }
    }

    // 5. Unlock boundary? Detect level TRANSITION, not snapshot
    if (config.stopAtUnlockBoundary) {
      for (final skill in watchedSkills) {
        final currentLevel = state.skillState(skill).skillLevel;
        final prevLevel = previousLevels[skill] ?? 1;

        // Check if we crossed any unlock boundary
        final skillUnlocks = unlockLevels[skill];
        if (skillUnlocks != null) {
          for (final boundaryLevel in skillUnlocks) {
            if (prevLevel < boundaryLevel && currentLevel >= boundaryLevel) {
              return UnlockBoundary(
                skill,
                boundaryLevel,
                _describeUnlock(skill, boundaryLevel),
              );
            }
          }
        }
      }
    }

    return null;
  }

  /// Checks if a ReplanBoundary from _applyStep is material for this segment.
  ///
  /// Used by executeSegment() to decide whether to stop.
  /// This ensures we don't have two separate filtering functions.
  bool isMaterial(ReplanBoundary boundary) {
    return switch (boundary) {
      GoalReached() => true,
      InputsDepleted() => config.stopAtInputsDepleted,
      InventoryFull() => true, // Always stop on full inventory
      InventoryPressure() => true, // Stop to handle inventory pressure
      Death() => false, // Deaths are handled by restart, not segment stop
      WaitConditionSatisfied() => false, // Normal completion, not a stop
      UpgradeAffordableEarly(:final purchaseId) =>
        config.stopAtUpgradeAffordable &&
            upgradePurchaseIds.contains(purchaseId),
      UnexpectedUnlock(:final actionId) =>
        config.stopAtUnlockBoundary && _isWatchedUnlock(actionId),
      UnlockObserved() => config.stopAtUnlockBoundary, // New unlock observed
      PlannedSegmentStop() => true, // Planned stop - always material
      CannotAfford() => true, // Error - always stop
      ActionUnavailable() => true, // Error - always stop
      NoProgressPossible() => true, // Error - always stop
      ReplanLimitExceeded() => true, // Budget exceeded - always stop
      TimeBudgetExceeded() => true, // Budget exceeded - always stop
    };
  }

  /// Converts a ReplanBoundary to a SegmentBoundary if material.
  SegmentBoundary? toSegmentBoundary(ReplanBoundary boundary) {
    if (!isMaterial(boundary)) return null;
    return switch (boundary) {
      GoalReached() => const GoalReachedBoundary(),
      InputsDepleted(:final actionId, :final missingItemId) =>
        InputsDepletedBoundary(actionId, missingItemId),
      UpgradeAffordableEarly(:final purchaseId) => UpgradeAffordableBoundary(
        purchaseId,
        _upgradeName(purchaseId),
      ),
      UnexpectedUnlock(:final actionId) => _toUnlockBoundary(actionId),
      UnlockObserved(:final skill, :final level, :final unlocks) =>
        UnlockBoundary(
          skill ?? Skill.woodcutting, // Fallback if unknown
          level ?? 1,
          unlocks ?? 'unknown',
        ),
      InventoryPressure(:final usedSlots, :final totalSlots) =>
        InventoryPressureBoundary(usedSlots, totalSlots),
      PlannedSegmentStop(:final boundary) =>
        boundary is SegmentBoundary
            ? boundary
            : const GoalReachedBoundary(), // Extract wrapped boundary
      _ => const GoalReachedBoundary(), // Fallback for errors
    };
  }

  /// Checks if an unlocked action is in our watch set.
  bool _isWatchedUnlock(ActionId actionId) {
    final action = registries.actions.byId(actionId);
    if (action is! SkillAction) return false;
    return watchedSkills.contains(action.skill);
  }

  /// Gets human-readable name for an upgrade.
  String _upgradeName(MelvorId purchaseId) {
    return registries.shop.byId(purchaseId)?.name ?? purchaseId.name;
  }

  /// Converts an UnexpectedUnlock to an UnlockBoundary.
  SegmentBoundary _toUnlockBoundary(ActionId actionId) {
    final action = registries.actions.byId(actionId);
    if (action is SkillAction) {
      return UnlockBoundary(action.skill, action.unlockLevel, action.name);
    }
    return const GoalReachedBoundary();
  }

  /// Describes what gets unlocked at a given skill level.
  String _describeUnlock(Skill skill, int level) {
    final unlocks = <String>[];
    for (final action in registries.actions.all) {
      if (action is SkillAction &&
          action.skill == skill &&
          action.unlockLevel == level) {
        unlocks.add(action.name);
      }
    }
    return unlocks.isNotEmpty ? unlocks.join(', ') : 'new actions';
  }
}

/// Builds a WatchSet from registries and goal.
///
/// This is decoupled from enumerateCandidates - it computes watches
/// directly from registries and goal.
///
/// The [sellPolicy] parameter is required - it must be computed once at
/// segment start using [SellPolicySpec.instantiate] on [SegmentConfig] and
/// passed here. This ensures WatchSet and boundary handling share the
/// same policy.
WatchSet buildWatchSet(
  GlobalState state,
  Goal goal,
  SegmentConfig config,
  SellPolicy sellPolicy,
) {
  final registries = state.registries;

  // Compute upgrade watches from shop registry
  final upgrades = _computeWatchedUpgrades(registries, goal, state);

  // Compute unlock levels from action registry
  final skillBoundaries = computeUnlockBoundaries(registries);
  final unlockLevels = _toUnlockLevelSets(skillBoundaries);

  // Capture current levels for transition detection
  final previousLevels = <Skill, int>{
    for (final skill in goal.relevantSkillsForBucketing)
      skill: state.skillState(skill).skillLevel,
  };

  return WatchSet(
    goal: goal,
    config: config,
    upgradePurchaseIds: upgrades,
    unlockLevels: unlockLevels,
    watchedSkills: goal.relevantSkillsForBucketing,
    previousLevels: previousLevels,
    registries: registries,
    sellPolicy: sellPolicy,
  );
}

// ---------------------------------------------------------------------------
// Segment Context
// ---------------------------------------------------------------------------

/// Bundles together the policy and derived objects for a segment.
///
/// Created once at segment start, this ensures that WatchSet, candidate
/// enumeration, and boundary handling all use the SAME [sellPolicy].
///
/// ## Design Rationale
///
/// Previously, `SellPolicy` was computed in multiple places:
/// - in `buildWatchSet()` (for effectiveCredits calculation)
/// - in `enumerateCandidates()` (for sell candidate emission)
/// - in boundary handling (when buying after UpgradeAffordableBoundary)
///
/// This violated a key invariant: if WatchSet reports an upgrade as
/// affordable (based on one SellPolicy), the boundary handler must be able
/// to liquidate and buy using the SAME policy.
///
/// SegmentContext ensures policy is computed once and reused everywhere.
@immutable
class SegmentContext {
  const SegmentContext({
    required this.goal,
    required this.config,
    required this.sellPolicySpec,
    required this.sellPolicy,
    required this.watchSet,
  });

  /// Creates a SegmentContext by computing the sell policy and watch set.
  ///
  /// This is the preferred way to create a SegmentContext - it ensures
  /// the sell policy is computed from the spec and passed to buildWatchSet.
  factory SegmentContext.build(
    GlobalState state,
    Goal goal,
    SegmentConfig config,
  ) {
    final spec = config.sellPolicySpec;
    final sellPolicy = spec.instantiate(state, goal.consumingSkills);
    final watchSet = buildWatchSet(state, goal, config, sellPolicy);

    return SegmentContext(
      goal: goal,
      config: config,
      sellPolicySpec: spec,
      sellPolicy: sellPolicy,
      watchSet: watchSet,
    );
  }

  /// The goal we're trying to reach.
  final Goal goal;

  /// Configuration for stopping behavior.
  final SegmentConfig config;

  /// The stable policy specification (chosen once per solve).
  final SellPolicySpec sellPolicySpec;

  /// The concrete policy computed from [sellPolicySpec] and current state.
  ///
  /// This is the SINGLE source of truth for what items to keep vs sell
  /// within this segment.
  final SellPolicy sellPolicy;

  /// The watch set for boundary detection.
  ///
  /// Uses [sellPolicy] for effectiveCredits calculation.
  final WatchSet watchSet;
}

/// Computes which upgrades to watch based on goal and current state.
Set<MelvorId> _computeWatchedUpgrades(
  Registries registries,
  Goal goal,
  GlobalState state,
) {
  final upgrades = <MelvorId>{};

  // Watch all upgrades relevant to goal skills
  // (axes for WC, rods for fishing, picks for mining, etc.)
  for (final skill in goal.relevantSkillsForBucketing) {
    final skillUpgrades = registries.shop.purchasesAffectingSkill(skill);
    for (final purchase in skillUpgrades) {
      // Only watch upgrades we haven't bought yet
      if (!state.shop.owns(purchase.id)) {
        upgrades.add(purchase.id);
      }
    }
  }

  return upgrades;
}

/// Converts SkillBoundaries map to unlock level sets.
Map<Skill, Set<int>> _toUnlockLevelSets(
  Map<Skill, SkillBoundaries> skillBoundaries,
) {
  return {
    for (final entry in skillBoundaries.entries)
      entry.key: entry.value.boundaries.toSet(),
  };
}
