import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logic/src/action_state.dart';
import 'package:logic/src/data/combat.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

/// Gem drop table for mining - 1% chance to trigger, then weighted selection.
const miningGemTable = DropTable(
  rate: 0.01, // 1% chance to get a gem
  entries: [
    Drop('Topaz', rate: 50), // 50% of 1% = 0.5%
    Drop('Sapphire', rate: 17.5), // 17.5% of 1% = 0.175%
    Drop('Ruby', rate: 17.5), // 17.5% of 1% = 0.175%
    Drop('Emerald', rate: 10), // 10% of 1% = 0.1%
    Drop('Diamond', rate: 5), // 5% of 1% = 0.05%
  ],
);

enum Skill {
  hitpoints('Hitpoints'),
  attack('Attack'),
  woodcutting('Woodcutting'),
  firemaking('Firemaking'),
  fishing('Fishing'),
  cooking('Cooking'),
  mining('Mining'),
  smithing('Smithing'),
  thieving('Thieving');

  const Skill(this.name);

  factory Skill.fromName(String name) {
    return Skill.values.firstWhere((e) => e.name == name);
  }

  final String name;
}

enum RockType { essence, ore }

/// Base class for all actions that can occupy the "active" slot.
/// Subclasses: SkillAction (duration-based with xp/outputs) and CombatAction.
@immutable
abstract class Action {
  const Action({required this.name, required this.skill});

  final String name;
  final Skill skill;
}

List<Droppable> defaultRewards(SkillAction action, int masteryLevel) {
  return [...action.outputs.entries.map((e) => Drop(e.key, count: e.value))];
}

List<Droppable> woodcuttingRewards(SkillAction action, int masteryLevel) {
  final outputs = action.outputs;
  if (outputs.length != 1 || outputs.values.first != 1) {
    throw StateError('Unsupported outputs: $outputs.');
  }
  final name = outputs.keys.first;
  final doubleMultiplier = masteryLevel ~/ 10;
  final doublePercent = (doubleMultiplier * 0.05).clamp(0.0, 1.0);
  final singlePercent = (1.0 - doublePercent).clamp(0.0, 1.0);
  return [
    DropTable(
      rate: 1.0,
      entries: [
        Drop(name, rate: singlePercent),
        Drop(name, rate: doublePercent, count: 2),
      ],
    ),
  ];
}

/// A skill-based action that completes after a duration, granting xp and drops.
/// This covers woodcutting, firemaking, fishing, smithing, and mining actions.
@immutable
class SkillAction extends Action {
  const SkillAction({
    required super.skill,
    required super.name,
    required Duration duration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
    this.rewardsAtLevel = defaultRewards,
  }) : minDuration = duration,
       maxDuration = duration;

  const SkillAction.ranged({
    required super.skill,
    required super.name,
    required this.minDuration,
    required this.maxDuration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
    this.rewardsAtLevel = defaultRewards,
  });

  final int xp;
  final int unlockLevel;
  final Duration minDuration;
  final Duration maxDuration;
  final Map<String, int> inputs;
  final Map<String, int> outputs;

  final List<Droppable> Function(SkillAction, int masteryLevel) rewardsAtLevel;

  bool get isFixedDuration => minDuration == maxDuration;

  Duration get meanDuration {
    final totalMicroseconds =
        (minDuration.inMicroseconds + maxDuration.inMicroseconds) ~/ 2;
    return Duration(microseconds: totalMicroseconds);
  }

  Tick rollDuration(Random random) {
    if (isFixedDuration) {
      return ticksFromDuration(minDuration);
    }
    final minTicks = ticksFromDuration(minDuration);
    final maxTicks = ticksFromDuration(maxDuration);
    // random.nextInt(n) creates [0, n-1] so use +1 to produce a uniform random
    // value between minTicks and maxTicks (inclusive).
    return minTicks + random.nextInt((maxTicks - minTicks) + 1);
  }

  List<Droppable> rewardsForMasteryLevel(int masteryLevel) =>
      rewardsAtLevel(this, masteryLevel);
}

const miningSwingDuration = Duration(seconds: 3);

/// Mining action with rock HP and respawn mechanics.
@immutable
class MiningAction extends SkillAction {
  MiningAction({
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.outputs,
    required int respawnSeconds,
    required this.rockType,
  }) : respawnTime = Duration(seconds: respawnSeconds),
       super(skill: Skill.mining, duration: miningSwingDuration);

  final RockType rockType;
  final Duration respawnTime;

  int get respawnTicks => ticksFromDuration(respawnTime);

  // Rock HP = 5 + Mastery Level + Boosts
  // For now, boosts are 0
  int maxHpForMasteryLevel(int masteryLevel) => 5 + masteryLevel;

  /// Returns progress (0.0 to 1.0) toward respawn completion, or null if
  /// not respawning.
  double? respawnProgress(ActionState actionState) {
    final remaining = actionState.mining?.respawnTicksRemaining;
    if (remaining == null) return null;
    return 1.0 - (remaining / respawnTicks);
  }
}

/// Duration for all thieving actions.
const thievingDuration = Duration(seconds: 3);

/// Thieving action with success/fail mechanics.
/// On success: grants 1-maxGold GP and rolls for drops.
/// On failure: deals 1-maxHit damage and stuns the player.
@immutable
class ThievingAction extends SkillAction {
  const ThievingAction({
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required this.perception,
    required this.maxHit,
    required this.maxGold,
    super.outputs = const {},
  }) : super(skill: Skill.thieving, duration: thievingDuration);

  /// NPC perception - used to calculate success rate.
  final int perception;

  /// Maximum damage dealt on failure (1-maxHit).
  final int maxHit;

  /// Maximum gold granted on success (1-maxGold).
  final int maxGold;

  /// Rolls damage dealt on failure (1 to maxHit inclusive).
  int rollDamage(Random random) {
    if (maxHit <= 1) return 1;
    return 1 + random.nextInt(maxHit);
  }

  /// Rolls gold granted on success (1 to maxGold inclusive).
  int rollGold(Random random) {
    if (maxGold <= 1) return 1;
    return 1 + random.nextInt(maxGold);
  }

  /// Determines if the thieving attempt succeeds.
  /// Success chance = min(1, (100 + stealth) / (100 + perception))
  /// where stealth = 40 + thievingLevel + actionMasteryLevel
  bool rollSuccess(Random random, int thievingLevel, int actionMasteryLevel) {
    final stealth = calculateStealth(thievingLevel, actionMasteryLevel);
    final successChance = ((100 + stealth) / (100 + perception)).clamp(
      0.0,
      1.0,
    );
    final roll = random.nextDouble();
    return roll < successChance;
  }
}

/// Base stealth value before skill/mastery bonuses.
const int baseStealth = 40;

/// Calculates stealth value for thieving.
/// Stealth = 40 + thieving level + action mastery level
int calculateStealth(int thievingLevel, int actionMasteryLevel) {
  return baseStealth + thievingLevel + actionMasteryLevel;
}

ThievingAction _thieving(
  String name, {
  required int level,
  required int xp,
  required int perception,
  required int maxHit,
  required int maxGold,
}) {
  return ThievingAction(
    name: name,
    unlockLevel: level,
    xp: xp,
    perception: perception,
    maxHit: maxHit,
    maxGold: maxGold,
  );
}

final thievingActions = <ThievingAction>[
  _thieving('Man', level: 1, xp: 5, perception: 110, maxHit: 22, maxGold: 100),
];

/// Look up a ThievingAction by name.
ThievingAction thievingActionByName(String name) {
  return thievingActions.firstWhere((action) => action.name == name);
}

/// Fixed player attack speed in seconds.
const double playerAttackSpeed = 4;

SkillAction _woodcutting(
  String name, {
  required int level,
  required int xp,
  required int seconds,
}) {
  return SkillAction(
    skill: Skill.woodcutting,
    name: '$name Tree',
    unlockLevel: level,
    duration: Duration(seconds: seconds),
    xp: xp,
    outputs: {'$name Logs': 1},
    rewardsAtLevel: woodcuttingRewards,
  );
}

final _woodcuttingActions = <SkillAction>[
  _woodcutting('Normal', level: 1, seconds: 3, xp: 10),
  _woodcutting('Oak', level: 10, seconds: 4, xp: 15),
  _woodcutting('Willow', level: 20, seconds: 5, xp: 22),
  _woodcutting('Teak', level: 35, seconds: 6, xp: 30),
];

SkillAction _firemaking(
  String name, {
  required int level,
  required int xp,
  required int seconds,
}) {
  return SkillAction(
    skill: Skill.firemaking,
    name: 'Burn $name Logs',
    unlockLevel: level,
    duration: Duration(seconds: seconds),
    xp: xp,
    inputs: {'$name Logs': 1},
  );
}

final _firemakingActions = <SkillAction>[
  _firemaking('Normal', level: 1, seconds: 2, xp: 19),
  _firemaking('Oak', level: 10, seconds: 2, xp: 39),
  _firemaking('Willow', level: 25, seconds: 3, xp: 52),
  _firemaking('Teak', level: 35, seconds: 4, xp: 84),
];

SkillAction _fishing(
  String name, {
  required int level,
  required int xp,
  required int minSeconds,
  required int maxSeconds,
}) {
  return SkillAction.ranged(
    skill: Skill.fishing,
    name: name,
    unlockLevel: level,
    xp: xp,
    minDuration: Duration(seconds: minSeconds),
    maxDuration: Duration(seconds: maxSeconds),
    outputs: {name: 1},
  );
}

final fishingActions = <SkillAction>[
  _fishing('Raw Shrimp', level: 1, xp: 10, minSeconds: 4, maxSeconds: 8),
];

MiningAction _mining(
  String name, {
  required int level,
  required int xp,
  required int respawnSeconds,
  int outputCount = 1,
  RockType rockType = RockType.ore,
}) {
  final outputName = rockType == RockType.ore ? '$name Ore' : name;
  return MiningAction(
    name: name,
    unlockLevel: level,
    xp: xp,
    outputs: {outputName: outputCount},
    respawnSeconds: respawnSeconds,
    rockType: rockType,
  );
}

final miningActions = <MiningAction>[
  _mining(
    'Rune Essence',
    level: 1,
    xp: 5,
    respawnSeconds: 1,
    outputCount: 2,
    rockType: RockType.essence,
  ),
  _mining('Copper', level: 1, xp: 7, respawnSeconds: 5),
  _mining('Tin', level: 1, xp: 7, respawnSeconds: 5, outputCount: 1),
  _mining('Iron', level: 15, xp: 14, respawnSeconds: 10),
];

SkillAction _smithing(
  String name, {
  required int level,
  required int xp,
  required Map<String, int> inputs,
  Map<String, int>? outputs,
}) {
  return SkillAction(
    skill: Skill.smithing,
    name: name,
    unlockLevel: level,
    duration: Duration(seconds: 2),
    xp: xp,
    inputs: inputs,
    outputs: outputs ?? {name: 1},
  );
}

final smithingActions = <SkillAction>[
  _smithing(
    'Bronze Bar',
    level: 1,
    xp: 5,
    inputs: {'Copper Ore': 1, 'Tin Ore': 1},
  ),
  _smithing('Iron Bar', level: 10, xp: 8, inputs: {'Iron Ore': 1}),
  _smithing('Bronze Dagger', level: 1, xp: 10, inputs: {'Bronze Bar': 1}),
];

SkillAction _cooking(
  String name, {
  required int level,
  required int xp,
  required int seconds,
}) {
  return SkillAction(
    skill: Skill.cooking,
    name: name,
    unlockLevel: level,
    duration: Duration(seconds: seconds),
    xp: xp,
    inputs: {'Raw $name': 1},
    outputs: {name: 1},
  );
}

final cookingActions = <SkillAction>[
  _cooking('Shrimp', level: 1, xp: 5, seconds: 2),
];

final List<Action> _allActions = [
  ..._woodcuttingActions,
  ..._firemakingActions,
  ...fishingActions,
  ...cookingActions,
  ...miningActions,
  ...smithingActions,
  ...thievingActions,
  ...combatActions,
];

// Skill-level drops: shared across all actions in a skill.
// This can include both simple Drops and DropTables.
final skillDrops = <Skill, List<Droppable>>{
  Skill.hitpoints: [],
  Skill.attack: [],
  Skill.woodcutting: [
    const Drop('Bird Nest', rate: 0.005),
    // Add other woodcutting skill-level drops here
  ],
  Skill.firemaking: [
    const Drop('Coal Ore', rate: 0.40),
    const Drop('Ash', rate: 0.20),
    // Missing Charcoal, Generous Fire Spirit
  ],
  Skill.fishing: [
    // Add fishing skill-level drops here as needed
  ],
  Skill.cooking: [
    // Add cooking skill-level drops here as needed
  ],
  Skill.mining: [
    miningGemTable, // DropTable is a Drop, so it can go here
  ],
  Skill.smithing: [
    // Add smithing skill-level drops here as needed
  ],
  Skill.thieving: [
    // Add thieving skill-level drops here as needed
  ],
};

// Global drops: shared across all skills/actions
final globalDrops = <Droppable>[
  // Add global drops here as needed
  // Example: Drop(name: 'Lucky Coin', rate: 0.0001),
];

class ActionRegistry {
  ActionRegistry(this._all);

  final List<Action> _all;

  /// Returns a SkillAction by name.
  Action byName(String name) {
    final action = _all.firstWhereOrNull((action) => action.name == name);
    if (action == null) {
      throw StateError('Missing action $name');
    }
    return action;
  }

  SkillAction skillActionByName(String name) {
    final action = byName(name);
    if (action is SkillAction) {
      return action;
    }
    throw StateError('Action $name is not a SkillAction');
  }

  /// Returns all skill actions for a given skill.
  Iterable<SkillAction> forSkill(Skill skill) {
    return _all.whereType<SkillAction>().where(
      (action) => action.skill == skill,
    );
  }
}

final actionRegistry = ActionRegistry(_allActions);

class DropsRegistry {
  DropsRegistry(this._skillDrops, this._globalDrops);

  final Map<Skill, List<Droppable>> _skillDrops;
  final List<Droppable> _globalDrops;

  /// Returns all skill-level drops for a given skill.
  List<Droppable> forSkill(Skill skill) {
    return _skillDrops[skill] ?? [];
  }

  /// Returns all global drops.
  List<Droppable> get global => _globalDrops;

  /// Returns all drops that should be processed when a skill action completes.
  /// This combines action-level drops (from the action), skill-level drops,
  /// and global drops into a single list. Includes both simple Drops and
  /// DropTables, which are processed uniformly via Droppable.roll().
  /// Note: Only SkillActions have rewards - CombatActions handle drops
  /// differently.
  List<Droppable> allDropsForAction(
    SkillAction action, {
    required masteryLevel,
  }) {
    return [
      ...action.rewardsForMasteryLevel(masteryLevel), // Action-level drops
      ...forSkill(action.skill), // Skill-level drops (may include DropTables)
      ...global, // Global drops
    ];
  }
}

final dropsRegistry = DropsRegistry(skillDrops, globalDrops);
