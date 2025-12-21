/// Candidate enumeration: builds a "cheap frontier" for the solver.
///
/// ## Two Distinct Outputs
///
/// * **Branch candidates** ([Candidates.switchToActivities], [buyUpgrades],
///   [includeSellAll]): actions we're willing to consider now.
/// * **Watch candidates** ([WatchList]): events that define "interesting times"
///   for waiting (affordability, unlocks, inventory).
///
/// ## Key Invariant: Watch ≠ Action
///
/// [buyUpgrades] must contain only upgrades that are **actionable and
/// competitive** under the current policy:
/// - Apply to current activity or top candidate activities
/// - Positive gain under ValueModel
/// - Pass heuristics / top-K filters
///
/// [WatchList.upgradeTypes] may include a broader set to compute time-to-afford
/// / future replan moments.
///
/// **Never promote watch-only upgrades into buyUpgrades just because they are
/// affordable.** Example: we may watch FishingRod affordability, but we don't
/// branch on buying it while thieving unless it improves value for a candidate
/// activity.
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/upgrades.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:meta/meta.dart';

import 'goal.dart';

/// Default constants for candidate selection.
const int defaultActivityCandidateCount = 8; // K
const int defaultUpgradeCandidateCount = 8; // M
const int defaultLockedWatchCount = 3; // L
const double defaultInventoryThreshold = 0.8;

/// Summary of an action's expected rates for the planner.
@immutable
class ActionSummary {
  const ActionSummary({
    required this.actionName,
    required this.skill,
    required this.unlockLevel,
    required this.isUnlocked,
    required this.expectedTicks,
    required this.goldRatePerTick,
    required this.xpRatePerTick,
  });

  final String actionName;
  final Skill skill;
  final int unlockLevel;
  final bool isUnlocked;

  /// Expected ticks per action completion.
  final double expectedTicks;

  /// Expected gold per tick from selling outputs.
  final double goldRatePerTick;

  /// Expected skill XP per tick.
  final double xpRatePerTick;
}

/// What events the planner should watch for to define "wait until interesting".
@immutable
class WatchList {
  const WatchList({
    this.upgradeTypes = const [],
    this.lockedActivityNames = const [],
    this.inventory = false,
  });

  /// Upgrades whose affordability defines wait points.
  final List<UpgradeType> upgradeTypes;

  /// Locked activities whose unlock defines wait points.
  final List<String> lockedActivityNames;

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
  });

  /// Top-K unlocked activities to consider switching to.
  final List<String> switchToActivities;

  /// Top-K upgrades worth considering (may be unaffordable).
  final List<UpgradeType> buyUpgrades;

  /// Whether SellAll should be offered.
  final bool includeSellAll;

  /// Events to watch for "wait until interesting time".
  final WatchList watch;
}

/// Builds action summaries for all skill actions.
///
/// For each action, computes:
/// - isUnlocked: whether the player has the required skill level
/// - expectedTicks: mean duration in ticks
/// - goldRatePerTick: expected sell value per tick
/// - xpRatePerTick: skill XP per tick
List<ActionSummary> buildActionSummaries(GlobalState state) {
  final summaries = <ActionSummary>[];
  final registries = state.registries;

  for (final skill in Skill.values) {
    final skillLevel = state.skillState(skill).skillLevel;

    for (final action in registries.actions.forSkill(skill)) {
      // Skip actions that require inputs (firemaking, cooking, smithing)
      // These aren't standalone activities for gold generation
      if (action.inputs.isNotEmpty) continue;

      final isUnlocked = skillLevel >= action.unlockLevel;

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
        final mastery = state.actionState(action.name).masteryLevel;
        final stealth = calculateStealth(thievingLevel, mastery);
        final successChance = ((100 + stealth) / (100 + action.perception))
            .clamp(0.0, 1.0);
        final failureChance = 1.0 - successChance;

        // Expected gold = successChance * (1 + maxGold) / 2
        final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
        expectedGoldPerAction += expectedThievingGold;

        // Effective ticks per attempt = action duration + (failure chance * stun)
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
            actionName: action.name,
            skill: action.skill,
            unlockLevel: action.unlockLevel,
            isUnlocked: isUnlocked,
            expectedTicks: effectiveTicks,
            goldRatePerTick: goldRatePerTick,
            xpRatePerTick: xpRatePerTick,
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
          actionName: action.name,
          skill: action.skill,
          unlockLevel: action.unlockLevel,
          isUnlocked: isUnlocked,
          expectedTicks: expectedTicks,
          goldRatePerTick: goldRatePerTick,
          xpRatePerTick: xpRatePerTick,
        ),
      );
    }
  }

  return summaries;
}

/// Enumerates candidate interactions for the planner.
///
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

  // Build list of candidate activity names (current + switchTo)
  final candidateActivityNames = <String>[
    ...switchToActivities,
    if (state.activeAction != null) state.activeAction!.name,
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
    candidateActivityNames: candidateActivityNames,
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

  return Candidates(
    switchToActivities: switchToActivities,
    buyUpgrades: upgradeResult.candidates,
    includeSellAll: includeSellAll,
    watch: WatchList(
      upgradeTypes: upgradeResult.toWatch,
      lockedActivityNames: lockedActivitiesToWatch,
      inventory: includeSellAll,
    ),
  );
}

/// Selects top K unlocked activities by a custom ranking function.
///
/// Only includes activities with positive ranking (> 0). This filters out
/// activities that don't contribute to the goal (e.g., fishing when the
/// goal is a woodcutting level).
List<String> _selectUnlockedActivitiesByRanking(
  List<ActionSummary> summaries,
  GlobalState state,
  int count,
  double Function(ActionSummary) rankingFn,
) {
  final currentActionName = state.activeAction?.name;

  // Filter to unlocked actions with positive ranking, excluding current action
  final unlocked = summaries
      .where(
        (s) =>
            s.isUnlocked &&
            s.actionName != currentActionName &&
            rankingFn(s) > 0,
      )
      .toList();

  // Sort by ranking function descending
  unlocked.sort((a, b) => rankingFn(b).compareTo(rankingFn(a)));

  // Take top K
  return unlocked.take(count).map((s) => s.actionName).toList();
}

/// Selects top L locked activities by smallest unlockDeltaTicks.
///
/// Only activities for skills relevant to the [goal] are considered.
List<String> _selectLockedActivitiesToWatch(
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
  final withDelta = <(String, double)>[];
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
    withDelta.add((summary.actionName, unlockDeltaTicks));
  }

  // Sort by smallest unlockDeltaTicks
  withDelta.sort((a, b) => a.$2.compareTo(b.$2));

  // Take top L
  return withDelta.take(count).map((e) => e.$1).toList();
}

/// Gets the best XP rate per tick for a skill from unlocked activities.
double _currentXpRateForSkill(List<ActionSummary> summaries, Skill skill) {
  final forSkill = summaries.where((s) => s.skill == skill && s.isUnlocked);
  if (forSkill.isEmpty) return 0.0;
  return forSkill.map((s) => s.xpRatePerTick).reduce((a, b) => a > b ? a : b);
}

/// Result of upgrade candidate selection.
class _UpgradeResult {
  const _UpgradeResult({required this.candidates, required this.toWatch});
  final List<UpgradeType> candidates;
  final List<UpgradeType> toWatch;
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
  List<String>? candidateActivityNames,
  double bestCurrentRate = 0.0,
  required Goal goal,
}) {
  final candidates = <(UpgradeType, double)>[];
  final toWatch = <UpgradeType>[];

  for (final type in UpgradeType.values) {
    final currentLevel = state.shop.upgradeLevel(type);
    final next = nextUpgrade(type, currentLevel);

    // No more upgrades available for this type
    if (next == null) continue;

    // Only consider upgrades for skills relevant to the goal
    if (!goal.isSkillRelevant(next.skill)) continue;

    // Doesn't meet skill requirement
    final skillLevel = state.skillState(next.skill).skillLevel;
    if (skillLevel < next.requiredLevel) continue;

    // Find affected activities that are:
    // 1. Same skill as upgrade
    // 2. Unlocked
    // 3. In the candidate list (if provided)
    final affectedActivities = summaries.where((s) {
      if (s.skill != next.skill) return false;
      if (!s.isUnlocked) return false;
      if (candidateActivityNames != null &&
          !candidateActivityNames.contains(s.actionName)) {
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
    // Upgrade gives durationPercentModifier (e.g., 0.95 = -5% duration)
    // Shorter duration means higher rate: newRate = baseRate / modifier
    final modifier = next.durationPercentModifier;
    final newRate = baseRate / modifier;
    final gain = newRate - baseRate;

    if (gain <= 0) continue;

    // Add to watch list - planner needs to know when any valid upgrade
    // becomes affordable, even if not currently competitive.
    // Invariant: toWatch is for timing waits, NOT for deciding to buy.
    toWatch.add(type);

    // Invariant: only add to candidates if competitive.
    // Skip if upgraded rate wouldn't beat or match best current rate -
    // buying this upgrade won't make this activity worth switching to.
    // This is the key guard that prevents "buy axe while thieving" bugs.
    if (newRate < bestCurrentRate) continue;

    // Payback time = cost / gain per tick
    final paybackTicks = next.cost / gain;
    candidates.add((type, paybackTicks));
  }

  // Sort by smallest paybackTicks
  candidates.sort((a, b) => a.$2.compareTo(b.$2));

  // Take top M
  final topCandidates = candidates.take(count).map((e) => e.$1).toList();

  return _UpgradeResult(candidates: topCandidates, toWatch: toWatch);
}
