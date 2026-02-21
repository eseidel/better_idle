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
  final actionCount = registries.actionsForSkill(skill).length;
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
  // Find the last index where _xpTable[index] <= xp
  // This represents the level the player has reached
  for (var i = _xpTable.length - 1; i >= 0; i--) {
    if (_xpTable[i] <= xp) {
      return i + 1;
    }
  }
  throw StateError('XP is less than all values in table');
}

int startXpForLevel(int level) {
  if (level < 1 || level > maxLevel) {
    throw StateError('Invalid level: $level');
  }
  return _xpTable[level - 1];
}

/// Like [skillProgressForXp] but capped at mastery level 99.
XpProgress masteryProgressForXp(int xp) {
  const maxMasteryLevel = 99;
  final progress = skillProgressForXp(xp);
  if (progress.level >= maxMasteryLevel) {
    return XpProgress(
      level: maxMasteryLevel,
      progress: 1,
      lastLevelXp: startXpForLevel(maxMasteryLevel),
      nextLevelXp: null,
    );
  }
  return progress;
}

XpProgress skillProgressForXp(int xp) {
  final level = levelForXp(xp);
  final startXp = startXpForLevel(level);

  // Handle max level case - if we're at the last level in the table
  final maxLevel = _xpTable.length;
  if (level >= maxLevel) {
    // At max level, progress is 1.0 (or we could cap it)
    return XpProgress(
      level: maxLevel,
      progress: 1,
      lastLevelXp: startXp,
      nextLevelXp: null,
    );
  }

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
  final actionsForSkill = registries.actionsForSkill(action.skill);
  final totalItemsInSkill = actionsForSkill.length;
  final actionTime = actionTimeForMastery(action);
  // Total Mastery for Skill = number of items × 99 (max mastery level per item)
  final totalMasteryForSkill = totalItemsInSkill * 99;
  final masteryPortion =
      unlockedActions * (playerTotalMasteryLevel / totalMasteryForSkill);
  final itemPortion = itemMasteryLevel * (totalItemsInSkill / 10);
  final baseValue = masteryPortion + itemPortion;
  return max(1, baseValue * actionTime * 0.5 * (1 + bonus)).toInt();
}

/// Returns the "action time" in seconds used for mastery XP calculation.
///
/// Action time varies by skill type:
/// - Gathering skills (Woodcutting, Mining, Thieving, Fishing): actual action
///   duration in seconds
/// - Artisan skills: fixed values regardless of actual duration:
///   - Firemaking: 60% of base burn interval
///   - Cooking: 85% of base cooking interval
///   - Smithing: 1.7 seconds
double actionTimeForMastery(SkillAction action) {
  switch (action.skill) {
    // Gathering skills use actual action duration
    case Skill.woodcutting:
    case Skill.mining:
    case Skill.thieving:
    case Skill.fishing:
    case Skill.agility:
    case Skill.astrology:
      return action.maxDuration.inSeconds.toDouble();

    // Artisan skills use fixed values
    case Skill.firemaking:
      // 60% of the log's base burn interval
      return action.maxDuration.inSeconds * 0.6;
    case Skill.cooking:
      // 85% of the recipe's base cooking interval
      return action.maxDuration.inSeconds * 0.85;
    case Skill.smithing:
    case Skill.fletching:
    case Skill.crafting:
    case Skill.herblore:
    case Skill.runecrafting:
    case Skill.summoning:
    case Skill.altMagic:
      return 1.7;

    // Farming uses growth duration for mastery calculations
    case Skill.farming:
      return action.maxDuration.inSeconds.toDouble();

    // Combat skills don't use mastery XP in the same way
    case Skill.combat:
    case Skill.strength:
    case Skill.defence:
    case Skill.ranged:
    case Skill.magic:
    case Skill.prayer:
    case Skill.slayer:
    case Skill.town:
    case Skill.hitpoints:
    case Skill.attack:
      return action.maxDuration.inSeconds.toDouble();
  }
}
