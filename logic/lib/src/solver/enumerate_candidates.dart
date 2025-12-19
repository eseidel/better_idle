import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/upgrades.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
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

  for (final skill in Skill.values) {
    final skillLevel = state.skillState(skill).skillLevel;

    for (final action in actionRegistry.forSkill(skill)) {
      // Skip actions that require inputs (firemaking, cooking, smithing)
      // These aren't standalone activities for gold generation
      if (action.inputs.isNotEmpty) continue;

      final isUnlocked = skillLevel >= action.unlockLevel;

      // Calculate expected ticks per action (mean duration)
      final expectedTicks = ticksFromDuration(action.meanDuration).toDouble();

      // Calculate expected gold per action from selling outputs
      var expectedGoldPerAction = 0.0;
      for (final output in action.outputs.entries) {
        final item = itemRegistry.byName(output.key);
        expectedGoldPerAction += item.sellsFor * output.value;
      }

      // For thieving, add expected gold from the action itself
      if (action is ThievingAction) {
        // Success rate depends on stealth vs perception
        // stealth = 40 + thievingLevel + masteryLevel
        // At level 1 with 0 mastery: stealth = 41
        // successChance = (100 + 41) / (100 + perception)
        final thievingLevel = state.skillState(Skill.thieving).skillLevel;
        final mastery = state.actionState(action.name).masteryLevel;
        final stealth = calculateStealth(thievingLevel, mastery);
        final successChance = ((100 + stealth) / (100 + action.perception))
            .clamp(0.0, 1.0);
        // Expected gold = successChance * (1 + maxGold) / 2
        final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
        expectedGoldPerAction += expectedThievingGold;
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
Candidates enumerateCandidates(
  GlobalState state, {
  int activityCount = defaultActivityCandidateCount,
  int upgradeCount = defaultUpgradeCandidateCount,
  int lockedWatchCount = defaultLockedWatchCount,
  double inventoryThreshold = defaultInventoryThreshold,
}) {
  final summaries = buildActionSummaries(state);

  // Select unlocked activity candidates (top K by goldRatePerTick)
  final switchToActivities = _selectUnlockedActivities(
    summaries,
    state,
    activityCount,
  );

  // Select locked activities to watch (top L by smallest unlockDeltaTicks)
  final lockedActivitiesToWatch = _selectLockedActivitiesToWatch(
    summaries,
    state,
    lockedWatchCount,
  );

  // Build list of candidate activity names (current + switchTo)
  final candidateActivityNames = <String>[
    ...switchToActivities,
    if (state.activeAction != null) state.activeAction!.name,
  ];

  // Find the best current gold rate among all unlocked activities
  final unlockedSummaries = summaries.where((s) => s.isUnlocked);
  final bestCurrentRate = unlockedSummaries.isEmpty
      ? 0.0
      : unlockedSummaries
            .map((s) => s.goldRatePerTick)
            .reduce((a, b) => a > b ? a : b);

  // Select upgrade candidates (top M by smallest paybackTicks)
  // Only includes upgrades that improve gold/tick for candidate activities
  // AND could make that activity become the best activity
  final upgradeResult = _selectUpgradeCandidates(
    summaries,
    state,
    upgradeCount,
    candidateActivityNames: candidateActivityNames,
    bestCurrentRate: bestCurrentRate,
  );

  // Determine SellAll and inventory watch
  final inventoryUsedFraction = state.inventoryCapacity > 0
      ? state.inventoryUsed / state.inventoryCapacity
      : 0.0;
  final includeSellAll = inventoryUsedFraction > inventoryThreshold;

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

/// Selects top K unlocked activities by goldRatePerTick.
List<String> _selectUnlockedActivities(
  List<ActionSummary> summaries,
  GlobalState state,
  int count,
) {
  final currentActionName = state.activeAction?.name;

  // Filter to unlocked actions, excluding current action
  final unlocked = summaries
      .where((s) => s.isUnlocked && s.actionName != currentActionName)
      .toList();

  // Sort by goldRatePerTick descending
  unlocked.sort((a, b) => b.goldRatePerTick.compareTo(a.goldRatePerTick));

  // Take top K
  return unlocked.take(count).map((s) => s.actionName).toList();
}

/// Selects top L locked activities by smallest unlockDeltaTicks.
List<String> _selectLockedActivitiesToWatch(
  List<ActionSummary> summaries,
  GlobalState state,
  int count,
) {
  // Filter to locked actions
  final locked = summaries.where((s) => !s.isUnlocked).toList();

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
/// Only includes upgrades that improve gold/tick for at least one of the
/// candidate activities AND would make that activity competitive with or
/// better than the best current rate.
_UpgradeResult _selectUpgradeCandidates(
  List<ActionSummary> summaries,
  GlobalState state,
  int count, {
  List<String>? candidateActivityNames,
  double bestCurrentRate = 0.0,
}) {
  final candidates = <(UpgradeType, double)>[];

  for (final type in UpgradeType.values) {
    final currentLevel = state.shop.upgradeLevel(type);
    final next = nextUpgrade(type, currentLevel);

    // No more upgrades available for this type
    if (next == null) continue;

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

    // Get best gold rate among affected activities
    final baseRate = affectedActivities
        .map((s) => s.goldRatePerTick)
        .reduce((a, b) => a > b ? a : b);

    if (baseRate <= 0) continue;

    // Compute new rate after upgrade
    // Upgrade gives durationPercentModifier (e.g., 0.95 = -5% duration)
    // Shorter duration means higher rate: newRate = baseRate / modifier
    final modifier = next.durationPercentModifier;
    final newRate = baseRate / modifier;
    final gain = newRate - baseRate;

    if (gain <= 0) continue;

    // Skip if upgraded rate wouldn't be competitive with best current rate
    // (buying this upgrade won't make this activity worth switching to)
    if (newRate < bestCurrentRate) continue;

    // Payback time = cost / gain per tick
    final paybackTicks = next.cost / gain;
    candidates.add((type, paybackTicks));
  }

  // Sort by smallest paybackTicks
  candidates.sort((a, b) => a.$2.compareTo(b.$2));

  // Take top M
  final topCandidates = candidates.take(count).map((e) => e.$1).toList();

  // Watch all candidates (even if unaffordable - planner needs to know when
  // they become affordable)
  return _UpgradeResult(candidates: topCandidates, toWatch: topCandidates);
}
