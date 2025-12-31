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
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/replan_boundary.dart';
import 'package:logic/src/solver/unlock_boundaries.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Calculates the total effective credits (GP + sellable inventory value).
///
/// If [keepItems] is provided, items in that set are excluded from the
/// sellable value (they're needed as inputs for consuming skills).
int _effectiveCredits(GlobalState state, {Set<MelvorId>? keepItems}) {
  var total = state.gp;
  for (final stack in state.inventory.items) {
    if (keepItems != null && keepItems.contains(stack.item.id)) {
      continue; // Don't count items we need to keep
    }
    total += stack.sellsFor;
  }
  return total;
}

/// Configuration for segment stopping behavior.
@immutable
class SegmentConfig {
  const SegmentConfig({
    this.stopAtUpgradeAffordable = true,
    this.stopAtUnlockBoundary = true,
    this.stopAtInputsDepleted = true,
  });

  /// Whether to stop when a watched upgrade becomes affordable.
  final bool stopAtUpgradeAffordable;

  /// Whether to stop when a skill level crosses an unlock boundary.
  final bool stopAtUnlockBoundary;

  /// Whether to stop when a consuming action runs out of inputs.
  final bool stopAtInputsDepleted;
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
    this.keepItems = const {},
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

  /// Items to keep (not count as sellable) for consuming skills.
  final Set<MelvorId> keepItems;

  /// Detects if a state has hit a material boundary.
  ///
  /// Used by _SegmentGoal.isSatisfied() during planning.
  /// For unlock boundaries, detects TRANSITIONS
  /// (previousLevel < boundary <= currentLevel).
  SegmentBoundary? detectBoundary(GlobalState state) {
    // 1. Goal reached?
    if (goal.isSatisfied(state)) {
      return const GoalReachedBoundary();
    }

    // 2. Upgrade affordable? (only for watched upgrades)
    // Use effective credits (GP + sellable inventory) since selling is instant
    // Exclude items we need to keep for consuming skills
    if (config.stopAtUpgradeAffordable) {
      final effectiveGp = _effectiveCredits(state, keepItems: keepItems);
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

    // 3. Unlock boundary? Detect level TRANSITION, not snapshot
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
      Death() => false, // Deaths are handled by restart, not segment stop
      WaitConditionSatisfied() => false, // Normal completion, not a stop
      UpgradeAffordableEarly(:final purchaseId) =>
        config.stopAtUpgradeAffordable &&
            upgradePurchaseIds.contains(purchaseId),
      UnexpectedUnlock(:final actionId) =>
        config.stopAtUnlockBoundary && _isWatchedUnlock(actionId),
      CannotAfford() => true, // Error - always stop
      ActionUnavailable() => true, // Error - always stop
      NoProgressPossible() => true, // Error - always stop
    };
  }

  /// Converts a ReplanBoundary to a SegmentBoundary if material.
  SegmentBoundary? toSegmentBoundary(ReplanBoundary boundary) {
    if (!isMaterial(boundary)) return null;
    return switch (boundary) {
      GoalReached() => const GoalReachedBoundary(),
      InputsDepleted(:final actionId) => InputsDepletedBoundary(actionId),
      UpgradeAffordableEarly(:final purchaseId) => UpgradeAffordableBoundary(
        purchaseId,
        _upgradeName(purchaseId),
      ),
      UnexpectedUnlock(:final actionId) => _toUnlockBoundary(actionId),
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
WatchSet buildWatchSet(GlobalState state, Goal goal, SegmentConfig config) {
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

  // Compute items to keep for consuming skills
  final keepItems = _computeKeepItems(registries, goal, state);

  return WatchSet(
    goal: goal,
    config: config,
    upgradePurchaseIds: upgrades,
    unlockLevels: unlockLevels,
    watchedSkills: goal.relevantSkillsForBucketing,
    previousLevels: previousLevels,
    registries: registries,
    keepItems: keepItems,
  );
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

/// Computes which items to keep (not sell) for consuming skill goals.
///
/// For goals involving consuming skills (Firemaking, Cooking, Smithing),
/// we need to keep items that are inputs for those skills.
Set<MelvorId> _computeKeepItems(
  Registries registries,
  Goal goal,
  GlobalState state,
) {
  final keepItems = <MelvorId>{};

  // Get consuming skills from the goal
  final consumingSkills = goal.consumingSkills;
  if (consumingSkills.isEmpty) {
    return keepItems;
  }

  // Find all consuming actions for those skills and collect their inputs
  for (final skill in consumingSkills) {
    for (final action in registries.actions.forSkill(skill)) {
      // Check if action is unlocked
      final skillLevel = state.skillState(skill).skillLevel;
      if (action.unlockLevel > skillLevel) continue;

      // Get input items for this action
      final actionStateVal = state.actionState(action.id);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);

      // Add all input item IDs to keep set
      inputs.keys.forEach(keepItems.add);
    }
  }

  return keepItems;
}
