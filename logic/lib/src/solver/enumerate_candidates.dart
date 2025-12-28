/// Candidate enumeration: builds a "cheap frontier" for the solver.
///
/// ## Two Distinct Outputs
///
/// * **Branch candidates** ([Candidates.switchToActivities],
///   [Candidates.buyUpgrades], [Candidates.includeSellAll]):
///   actions we're willing to consider now.
/// * **Watch candidates** ([WatchList]): events that define "interesting times"
///   for waiting (affordability, unlocks, inventory).
///
/// ## Key Invariant: Watch ≠ Action
///
/// [Candidates.buyUpgrades] must contain only upgrades that are **actionable
/// and competitive** under the current policy:
/// - Apply to current activity or top candidate activities
/// - Positive gain under ValueModel
/// - Pass heuristics / top-K filters
///
/// [WatchList.upgradePurchaseIds] may include a broader set to compute
/// time-to-afford / future replan moments.
///
/// **Never promote watch-only upgrades into buyUpgrades just because they are
/// affordable.** Example: we may watch FishingRod affordability, but we don't
/// branch on buying it while thieving unless it improves value for a candidate
/// activity.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/macro_candidate.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:meta/meta.dart';

/// Default constants for candidate selection.
const int defaultActivityCandidateCount = 8; // K
const int defaultUpgradeCandidateCount = 8; // M
const int defaultLockedWatchCount = 3; // L
const double defaultInventoryThreshold = 0.8;

/// Summary of an action's expected rates for the planner.
@immutable
class ActionSummary {
  const ActionSummary({
    required this.actionId,
    required this.skill,
    required this.unlockLevel,
    required this.isUnlocked,
    required this.expectedTicks,
    required this.goldRatePerTick,
    required this.xpRatePerTick,
    this.hasInputs = false,
    this.canStartNow = true,
    this.missingInputs = const {},
  });

  final ActionId actionId;
  final Skill skill;
  final int unlockLevel;
  final bool isUnlocked;

  /// Expected ticks per action completion.
  final double expectedTicks;

  /// Expected gold per tick from selling outputs.
  final double goldRatePerTick;

  /// Expected skill XP per tick.
  final double xpRatePerTick;

  /// Whether this action requires inputs (firemaking, cooking, etc).
  final bool hasInputs;

  /// Whether the action can start now (has required inputs available).
  /// Always true for actions without inputs.
  final bool canStartNow;

  /// Items needed but not available in inventory.
  /// Maps item ID to quantity still needed.
  final Map<MelvorId, int> missingInputs;
}

/// What events the planner should watch for to define "wait until interesting".
@immutable
class WatchList {
  const WatchList({
    this.upgradePurchaseIds = const [],
    this.lockedActivityIds = const [],
    this.consumingActivityIds = const [],
    this.inventory = false,
  });

  /// Shop purchase IDs for upgrades whose affordability defines wait points.
  final List<MelvorId> upgradePurchaseIds;

  /// Locked activities whose unlock defines wait points.
  final List<ActionId> lockedActivityIds;

  /// Consuming activities (with inputs) that we're gathering inputs for.
  /// Used to compute "inputs available" wait points.
  final List<ActionId> consumingActivityIds;

  /// Whether inventory-full should define a wait point.
  final bool inventory;
}

/// Output of enumerateCandidates - defines what interactions to consider
/// and what future events define "wait until interesting time".
@immutable
class Candidates {
  const Candidates({
    required this.switchToActivities,
    required this.buyUpgrades,
    required this.includeSellAll,
    required this.watch,
    required this.macros,
  });

  /// Top-K unlocked activities to consider switching to.
  final List<ActionId> switchToActivities;

  /// Top-K upgrade purchase IDs worth considering (may be unaffordable).
  final List<MelvorId> buyUpgrades;

  /// Whether SellAll should be offered.
  final bool includeSellAll;

  /// Events to watch for "wait until interesting time".
  final WatchList watch;

  /// Macro-level candidates (train skill until boundary).
  final List<MacroCandidate> macros;
}

/// Builds action summaries for all skill actions.
///
/// For each action, computes:
/// - isUnlocked: whether the player has the required skill level
/// - expectedTicks: mean duration in ticks
/// - goldRatePerTick: expected sell value per tick
/// - xpRatePerTick: skill XP per tick
/// - hasInputs: whether the action requires input items
/// - canStartNow: whether required inputs are available
/// - missingInputs: items needed but not available
List<ActionSummary> buildActionSummaries(GlobalState state) {
  final summaries = <ActionSummary>[];
  final registries = state.registries;

  for (final skill in Skill.values) {
    final skillLevel = state.skillState(skill).skillLevel;

    for (final action in registries.actions.forSkill(skill)) {
      final isUnlocked = skillLevel >= action.unlockLevel;

      // Check if action has inputs and whether they are available
      final actionStateVal = state.actionState(action.id);
      final selection = actionStateVal.recipeSelection(action);
      final inputs = action.inputsForRecipe(selection);
      final hasInputs = inputs.isNotEmpty;

      // Compute missing inputs (skip items not in registry)
      final missingInputs = <MelvorId, int>{};
      if (hasInputs) {
        for (final entry in inputs.entries) {
          final item = registries.items.byId(entry.key);
          final available = state.inventory.countOfItem(item);
          if (available < entry.value) {
            missingInputs[entry.key] = entry.value - available;
          }
        }
      }
      final canStartNow = missingInputs.isEmpty;

      // Calculate expected ticks per action (mean duration)
      final expectedTicks = ticksFromDuration(action.meanDuration).toDouble();

      // Calculate expected gold per action from selling outputs
      var expectedGoldPerAction = 0.0;
      for (final output in action.outputs.entries) {
        final item = registries.items.byId(output.key);
        expectedGoldPerAction += item.sellsFor * output.value;
      }

      // For thieving, account for success rate and stun time on failure
      if (action is ThievingAction) {
        // Success rate depends on stealth vs perception
        // stealth = 40 + thievingLevel + masteryLevel
        final thievingLevel = state.skillState(Skill.thieving).skillLevel;
        final mastery = state.actionState(action.id).masteryLevel;
        final stealth = calculateStealth(thievingLevel, mastery);
        final successChance = ((100 + stealth) / (100 + action.perception))
            .clamp(0.0, 1.0);
        final failureChance = 1.0 - successChance;

        // Expected gold = successChance * (1 + maxGold) / 2
        final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
        expectedGoldPerAction += expectedThievingGold;

        // Effective ticks per attempt =
        // action duration + (failure chance * stun)
        final effectiveTicks =
            expectedTicks + failureChance * stunnedDurationTicks;

        final goldRatePerTick = effectiveTicks > 0
            ? expectedGoldPerAction / effectiveTicks
            : 0.0;
        // XP is only gained on success
        final expectedXpPerAction = successChance * action.xp;
        final xpRatePerTick = effectiveTicks > 0
            ? expectedXpPerAction / effectiveTicks
            : 0.0;

        summaries.add(
          ActionSummary(
            actionId: action.id,
            skill: action.skill,
            unlockLevel: action.unlockLevel,
            isUnlocked: isUnlocked,
            expectedTicks: effectiveTicks,
            goldRatePerTick: goldRatePerTick,
            xpRatePerTick: xpRatePerTick,
            hasInputs: hasInputs,
            canStartNow: canStartNow,
            missingInputs: missingInputs,
          ),
        );
        continue;
      }

      final goldRatePerTick = expectedTicks > 0
          ? expectedGoldPerAction / expectedTicks
          : 0.0;
      final xpRatePerTick = expectedTicks > 0 ? action.xp / expectedTicks : 0.0;

      summaries.add(
        ActionSummary(
          actionId: action.id,
          skill: action.skill,
          unlockLevel: action.unlockLevel,
          isUnlocked: isUnlocked,
          expectedTicks: expectedTicks,
          goldRatePerTick: goldRatePerTick,
          xpRatePerTick: xpRatePerTick,
          hasInputs: hasInputs,
          canStartNow: canStartNow,
          missingInputs: missingInputs,
        ),
      );
    }
  }

  return summaries;
}

/// Enumerates candidate interactions for the planner.
///
/// Generates macro candidates for goal-relevant skills.
///
/// For each skill relevant to the goal:
/// - Creates TrainSkillUntil macros with primaryStop = StopAtNextBoundary
/// - If skill has a goal target, also creates macro with primaryStop = StopAtGoal
/// - Adds watchedStops for competitive upgrades (future extension)
List<MacroCandidate> _generateMacros(GlobalState state, Goal goal) {
  final macros = <MacroCandidate>[];

  // For MultiSkillGoal, generate macros for each subgoal
  if (goal is MultiSkillGoal) {
    for (final subgoal in goal.subgoals) {
      if (subgoal.isSatisfied(state)) continue;

      // Primary macro: train until next boundary
      macros.add(
        TrainSkillUntil(
          subgoal.skill,
          StopAtNextBoundary(subgoal.skill),
          watchedStops: [StopAtGoal(subgoal.skill, subgoal.targetXp)],
        ),
      );
    }
  }

  // For ReachSkillLevelGoal, generate macros for the target skill
  if (goal is ReachSkillLevelGoal) {
    if (!goal.isSatisfied(state)) {
      // Primary macro: train until next boundary, watching for goal
      macros.add(
        TrainSkillUntil(
          goal.skill,
          StopAtNextBoundary(goal.skill),
          watchedStops: [StopAtGoal(goal.skill, goal.targetXp)],
        ),
      );
    }
  }

  // For ReachGpGoal, we don't generate macros (use micro-steps instead)
  // GP goals benefit from frequent re-evaluation for upgrade purchases

  return macros;
}

/// Returns a small, cheap, deterministic set of candidate interactions
/// and future "interesting times". Does NOT simulate.
///
/// Activities are ranked by progress rate toward the [goal].
/// For [ReachGpGoal], this is gold/tick. For [ReachSkillLevelGoal],
/// this is XP/tick for the target skill.
Candidates enumerateCandidates(
  GlobalState state,
  Goal goal, {
  int activityCount = defaultActivityCandidateCount,
  int upgradeCount = defaultUpgradeCandidateCount,
  int lockedWatchCount = defaultLockedWatchCount,
  double inventoryThreshold = defaultInventoryThreshold,
}) {
  final summaries = buildActionSummaries(state);

  // Generate macro candidates for skill goals
  final macros = _generateMacros(state, goal);

  // Ranking function uses goal's activityRate to determine value
  double rankingFn(ActionSummary s) =>
      goal.activityRate(s.skill, s.goldRatePerTick, s.xpRatePerTick);

  // Select unlocked activity candidates (top K by ranking function)
  final switchToActivities = _selectUnlockedActivitiesByRanking(
    summaries,
    state,
    activityCount,
    rankingFn,
  );

  // Select locked activities to watch (top L by smallest unlockDeltaTicks)
  // Only watch activities for skills relevant to the goal
  final lockedActivitiesToWatch = _selectLockedActivitiesToWatch(
    summaries,
    state,
    lockedWatchCount,
    goal: goal,
  );

  // Build list of candidate activity IDs (current + switchTo)
  final candidateActivityIds = <ActionId>[
    ...switchToActivities,
    if (state.activeAction != null) state.activeAction!.id,
  ];

  // Find the best current rate among all unlocked activities using ranking fn
  final unlockedSummaries = summaries.where((s) => s.isUnlocked);
  final bestCurrentRate = unlockedSummaries.isEmpty
      ? 0.0
      : unlockedSummaries.map(rankingFn).reduce((a, b) => a > b ? a : b);

  // Select upgrade candidates
  // Only include upgrades for skills relevant to the goal
  final upgradeResult = _selectUpgradeCandidates(
    summaries,
    state,
    upgradeCount,
    candidateActivityIds: candidateActivityIds,
    bestCurrentRate: bestCurrentRate,
    goal: goal,
  );

  // Determine SellAll and inventory watch
  // For skill goals, selling is less relevant (doesn't contribute to XP)
  final inventoryUsedFraction = state.inventoryCapacity > 0
      ? state.inventoryUsed / state.inventoryCapacity
      : 0.0;
  final includeSellAll =
      goal.isSellRelevant && inventoryUsedFraction > inventoryThreshold;

  // Find consuming activities relevant to the goal.
  // Include even activities that can start now, because we may need to
  // gather MORE inputs to complete the goal, not just enough to start.
  final consumingActivitiesToWatch = <ActionId>[];
  for (final summary in summaries) {
    if (!summary.isUnlocked) continue;
    if (!summary.hasInputs) continue;
    if (!goal.isSkillRelevant(summary.skill)) continue;
    consumingActivitiesToWatch.add(summary.actionId);
  }

  return Candidates(
    switchToActivities: switchToActivities,
    buyUpgrades: upgradeResult.candidates,
    includeSellAll: includeSellAll,
    watch: WatchList(
      upgradePurchaseIds: upgradeResult.toWatch,
      lockedActivityIds: lockedActivitiesToWatch,
      consumingActivityIds: consumingActivitiesToWatch,
      inventory: includeSellAll,
    ),
    macros: macros,
  );
}

/// Finds producer actions for a given item.
///
/// Returns action summaries for unlocked actions that produce the given item
/// in their outputs. Used to find input-producing actions when a consuming
/// action can't start due to missing inputs.
List<ActionSummary> _findProducersForItem(
  List<ActionSummary> summaries,
  GlobalState state,
  MelvorId itemId,
) {
  final producers = <ActionSummary>[];
  final registries = state.registries;

  for (final summary in summaries) {
    if (!summary.isUnlocked) continue;
    if (summary.hasInputs) continue; // Don't chain consuming actions

    final action = registries.actions.byId(summary.actionId);
    if (action is! SkillAction) continue;

    // Check if this action produces the item we need
    if (action.outputs.containsKey(itemId)) {
      producers.add(summary);
    }
  }

  return producers;
}

/// Selects top K unlocked activities by a custom ranking function.
///
/// Only includes activities with positive ranking (> 0). This filters out
/// activities that don't contribute to the goal (e.g., fishing when the
/// goal is a woodcutting level).
///
/// For consuming actions (those with inputs):
/// - If the action can start now (has inputs), include it
/// - If the action can't start, include producer actions for missing inputs
List<ActionId> _selectUnlockedActivitiesByRanking(
  List<ActionSummary> summaries,
  GlobalState state,
  int count,
  double Function(ActionSummary) rankingFn,
) {
  final currentActionId = state.activeAction?.id;

  // Filter to unlocked actions with positive ranking, excluding current action
  final unlocked =
      summaries
          .where(
            (s) =>
                s.isUnlocked &&
                s.actionId != currentActionId &&
                rankingFn(s) > 0,
          )
          .toList()
        ..sort((a, b) => rankingFn(b).compareTo(rankingFn(a)));

  // Build result set, handling consuming actions specially
  final result = <ActionId>{};
  final producersAdded = <ActionId>{};

  for (final summary in unlocked) {
    if (result.length >= count) break;

    if (!summary.hasInputs) {
      // Non-consuming action: always include
      result.add(summary.actionId);
    } else if (summary.canStartNow) {
      // Consuming action with inputs available: include
      result.add(summary.actionId);
    } else {
      // Consuming action that can't start: add producers for missing inputs
      // Also add the consuming action itself so the solver can switch to it
      // when inputs become available
      result.add(summary.actionId);

      for (final missingItemId in summary.missingInputs.keys) {
        final producers = _findProducersForItem(
          summaries,
          state,
          missingItemId,
        );
        for (final producer in producers) {
          if (!producersAdded.contains(producer.actionId) &&
              producer.actionId != currentActionId) {
            producersAdded.add(producer.actionId);
            result.add(producer.actionId);
          }
        }
      }
    }
  }

  return result.take(count * 2).toList(); // Allow extra for producers
}

/// Selects top L locked activities by smallest unlockDeltaTicks.
///
/// Only activities for skills relevant to the [goal] are considered.
List<ActionId> _selectLockedActivitiesToWatch(
  List<ActionSummary> summaries,
  GlobalState state,
  int count, {
  required Goal goal,
}) {
  // Filter to locked actions for skills relevant to the goal
  final locked = summaries.where((s) {
    if (s.isUnlocked) return false;
    if (!goal.isSkillRelevant(s.skill)) return false;
    return true;
  }).toList();

  // For each locked action, compute ticks until unlock
  final withDelta = <(ActionId, double)>[];
  for (final summary in locked) {
    final skillState = state.skillState(summary.skill);
    final currentXp = skillState.xp;
    final requiredXp = startXpForLevel(summary.unlockLevel);
    final xpNeeded = requiredXp - currentXp;

    if (xpNeeded <= 0) {
      // Already have enough XP (shouldn't happen since !isUnlocked)
      continue;
    }

    // Find current XP rate for this skill from unlocked activities
    final xpRate = _currentXpRateForSkill(summaries, summary.skill);
    if (xpRate <= 0) {
      // No way to gain XP for this skill
      continue;
    }

    final unlockDeltaTicks = xpNeeded / xpRate;
    withDelta.add((summary.actionId, unlockDeltaTicks));
  }

  // Sort by smallest unlockDeltaTicks
  withDelta.sort((a, b) => a.$2.compareTo(b.$2));

  // Take top L
  return withDelta.take(count).map((e) => e.$1).toList();
}

/// Gets the best XP rate per tick for a skill from unlocked activities.
double _currentXpRateForSkill(List<ActionSummary> summaries, Skill skill) {
  final forSkill = summaries.where((s) => s.skill == skill && s.isUnlocked);
  if (forSkill.isEmpty) return 0;
  return forSkill.map((s) => s.xpRatePerTick).reduce((a, b) => a > b ? a : b);
}

/// Result of upgrade candidate selection.
class _UpgradeResult {
  const _UpgradeResult({required this.candidates, required this.toWatch});
  final List<MelvorId> candidates;
  final List<MelvorId> toWatch;
}

/// Selects top M upgrades by smallest paybackTicks.
///
/// Only includes upgrades that improve rate for at least one of the
/// candidate activities AND would make that activity competitive with or
/// better than the best current rate.
///
/// Only upgrades for skills relevant to the [goal] are considered.
///
/// The watch list includes all upgrades that meet skill requirements and have
/// positive gain, regardless of competitiveness (the planner needs to know
/// when they become affordable to reconsider decisions).
_UpgradeResult _selectUpgradeCandidates(
  List<ActionSummary> summaries,
  GlobalState state,
  int count, {
  required Goal goal,
  List<ActionId>? candidateActivityIds,
  double bestCurrentRate = 0.0,
}) {
  final candidates = <(MelvorId, double)>[];
  final toWatch = <MelvorId>[];

  final shopRegistry = state.registries.shop;
  final availableUpgrades = shopRegistry.availableSkillUpgrades(
    state.shop.purchaseCounts,
  );

  for (final (purchase, skill) in availableUpgrades) {
    // Only consider upgrades for skills relevant to the goal
    if (!goal.isSkillRelevant(skill)) continue;

    // Doesn't meet skill requirement
    final requirements = shopRegistry.skillLevelRequirements(purchase);
    final meetsAllRequirements = requirements.every((req) {
      final skillLevel = state.skillState(req.skill).skillLevel;
      return skillLevel >= req.level;
    });
    if (!meetsAllRequirements) continue;

    // Find affected activities that are:
    // 1. Same skill as upgrade
    // 2. Unlocked
    // 3. In the candidate list (if provided)
    final affectedActivities = summaries.where((s) {
      if (s.skill != skill) return false;
      if (!s.isUnlocked) return false;
      if (candidateActivityIds != null &&
          !candidateActivityIds.contains(s.actionId)) {
        return false;
      }
      return true;
    });

    if (affectedActivities.isEmpty) continue;

    // Get best rate among affected activities using goal's rate function
    final baseRate = affectedActivities
        .map(
          (s) => goal.activityRate(s.skill, s.goldRatePerTick, s.xpRatePerTick),
        )
        .reduce((a, b) => a > b ? a : b);

    if (baseRate <= 0) continue;

    // Compute new rate after upgrade
    // Upgrade gives durationMultiplier (e.g., 0.95 = -5% duration)
    // Shorter duration means higher rate: newRate = baseRate / modifier
    final modifier = shopRegistry.durationMultiplier(purchase);
    final newRate = baseRate / modifier;
    final gain = newRate - baseRate;

    if (gain <= 0) continue;

    // Add to watch list - planner needs to know when any valid upgrade
    // becomes affordable, even if not currently competitive.
    // Invariant: toWatch is for timing waits, NOT for deciding to buy.
    toWatch.add(purchase.id);

    // Invariant: only add to candidates if competitive.
    // Skip if upgraded rate wouldn't beat or match best current rate -
    // buying this upgrade won't make this activity worth switching to.
    // This is the key guard that prevents "buy axe while thieving" bugs.
    if (newRate < bestCurrentRate) continue;

    // Payback time = cost / gain per tick
    final cost = shopRegistry.gpCost(purchase);
    if (cost == null) continue; // Skip upgrades with special pricing
    final paybackTicks = cost / gain;
    candidates.add((purchase.id, paybackTicks));
  }

  // Sort by smallest paybackTicks
  candidates.sort((a, b) => a.$2.compareTo(b.$2));

  // Take top M
  final topCandidates = candidates.take(count).map((e) => e.$1).toList();

  return _UpgradeResult(candidates: topCandidates, toWatch: toWatch);
}
