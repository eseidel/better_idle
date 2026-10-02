import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/registries.dart';

// Generated with tool/xp_table.dart
// From https://wiki.melvoridle.com/w/Experience_Table
final _xpTable = <int>[
  0,
  83,
  174,
  276,
  388,
  512,
  650,
  801,
  969,
  1154,
  1358,
  1584,
  1833,
  2107,
  2411,
  2746,
  3115,
  3523,
  3973,
  4470,
  5018,
  5624,
  6291,
  7028,
  7842,
  8740,
  9730,
  10824,
  12031,
  13363,
  14833,
  16456,
  18247,
  20224,
  22406,
  24815,
  27473,
  30408,
  33648,
  37224,
  41171,
  45529,
  50339,
  55649,
  61512,
  67983,
  75127,
  83014,
  91721,
  101333,
  111945,
  123660,
  136594,
  150872,
  166636,
  184040,
  203254,
  224466,
  247886,
  273742,
  302288,
  333804,
  368599,
  407015,
  449428,
  496254,
  547953,
  605032,
  668051,
  737627,
  814445,
  899257,
  992895,
  1096278,
  1210421,
  1336443,
  1475581,
  1629200,
  1798808,
  1986068,
  2192818,
  2421087,
  2673114,
  2951373,
  3258594,
  3597792,
  3972294,
  4385776,
  4842295,
  5346332,
  5902831,
  6517253,
  7195629,
  7944614,
  8771558,
  9684577,
  10692629,
  11805606,
  13034431,
  14391160,
  15889109,
  17542976,
  19368992,
  21385073,
  23611006,
  26068632,
  28782069,
  31777943,
  35085654,
  38737661,
  42769801,
  47221641,
  52136869,
  57563718,
  63555443,
  70170840,
  77474828,
  85539082,
  94442737,
  104273167,
];

final int maxLevel = _xpTable.length;

// Each action stops accumulating mastery xp at level 99.
final int maxMasteryXp = _xpTable[99];

/// Maximum mastery pool XP for a skill is 500,000 multiplied by the total
/// number of actions in that skill.
int maxMasteryPoolXpForSkill(Registries registries, Skill skill) {
  final actionCount = registries.masteryActionsForSkill(skill).length;
  return actionCount * 500000;
}

class XpProgress {
  const XpProgress({
    required this.level,
    required this.progress,
    required this.lastLevelXp,
    required this.nextLevelXp,
  });
  final int level;
  final double progress;
  final int lastLevelXp;
  final int? nextLevelXp;
}

int levelForXp(int xp) {
  // Binary search for the last index where _xpTable[index] <= xp.
  var lo = 0;
  var hi = _xpTable.length;
  while (lo < hi) {
    final mid = (lo + hi) >>> 1;
    if (_xpTable[mid] <= xp) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  // lo is now the first index where _xpTable[lo] > xp, so lo-1 is the
  // last index where _xpTable[index] <= xp. Levels are 1-based.
  if (lo == 0) throw StateError('XP is less than all values in table');
  return lo;
}

int startXpForLevel(int level) {
  if (level < 1 || level > maxLevel) {
    throw StateError('Invalid level: $level');
  }
  return _xpTable[level - 1];
}

/// Mastery XP progress, capped at level 99.
XpProgress masteryProgressForXp(int xp) => _progressForXp(xp, maxLevel: 99);

/// Skill XP progress, uncapped (levels 1 to [maxLevel]).
XpProgress skillProgressForXp(int xp) => _progressForXp(xp);

XpProgress _progressForXp(int xp, {int? maxLevel}) {
  final effectiveMaxLevel = maxLevel ?? _xpTable.length;
  final level = levelForXp(xp);

  if (level >= effectiveMaxLevel) {
    return XpProgress(
      level: effectiveMaxLevel,
      progress: 1,
      lastLevelXp: startXpForLevel(effectiveMaxLevel),
      nextLevelXp: null,
    );
  }

  final startXp = startXpForLevel(level);
  final nextLevelXp = startXpForLevel(level + 1);
  final progress =
      (xp - startXp).toDouble() / (nextLevelXp - startXp).toDouble();
  return XpProgress(
    level: level,
    progress: progress.clamp(0.0, 1.0),
    lastLevelXp: startXp,
    nextLevelXp: nextLevelXp,
  );
}

/// Returns the mastery pool XP earned alongside [masteryXp] for one action.
///
/// Melvor grants 25% of the action's mastery XP to the skill's mastery pool.
int masteryPoolXpForMasteryXp(int masteryXp) =>
    max(1, (0.25 * masteryXp).toInt());

/// Calculates the amount of mastery XP gained per action from raw values.
/// Derived from https://wiki.melvoridle.com/w/Mastery.
///
/// The formula uses mastery **levels** (1-99), not mastery XP values:
/// - playerTotalMasteryLevel: sum of mastery levels across all actions in skill
/// - totalMasteryForSkill: totalItems × 99 (max mastery level)
int calculateMasteryXpPerAction({
  required Registries registries,
  required SkillAction action,
  required int unlockedActions,
  required int playerTotalMasteryLevel,
  required int itemMasteryLevel,
  required double bonus, // e.g. 0.1 for +10%
}) {
  final masteryActions = registries.masteryActionsForSkill(action.skill);
  final totalItemsInSkill = masteryActions.length;
  // A skill with no registered actions has no mastery to spread; bail out
  // rather than dividing by zero below.
  if (totalItemsInSkill == 0) return 1;
  final actionTime = action.masteryActionTime;
  // Total Mastery for Skill = number of items × 99 (max mastery level per item)
  final totalMasteryForSkill = totalItemsInSkill * 99;
  final masteryPortion =
      unlockedActions * (playerTotalMasteryLevel / totalMasteryForSkill);
  final itemPortion = itemMasteryLevel * (totalItemsInSkill / 10);
  final baseValue = masteryPortion + itemPortion;
  return max(1, baseValue * actionTime * 0.5 * (1 + bonus)).toInt();
}
