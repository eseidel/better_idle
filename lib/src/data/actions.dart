import 'dart:math';

import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/drop.dart';
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
  woodcutting('Woodcutting'),
  firemaking('Firemaking'),
  fishing('Fishing'),
  mining('Mining'),
  smithing('Smithing');

  const Skill(this.name);

  factory Skill.fromName(String name) {
    return Skill.values.firstWhere((e) => e.name == name);
  }

  final String name;
}

enum RockType { essence, ore }

class Action {
  const Action({
    required this.skill,
    required this.name,
    required Duration duration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
  }) : minDuration = duration,
       maxDuration = duration;

  const Action.ranged({
    required this.skill,
    required this.name,
    required this.minDuration,
    required this.maxDuration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
  });

  final Skill skill;
  final String name;
  final int xp;
  final int unlockLevel;
  final Duration minDuration;
  final Duration maxDuration;
  final Map<String, int> inputs;
  final Map<String, int> outputs;

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

  List<Drop> get rewards => [
    ...outputs.entries.map((e) => Drop(e.key, count: e.value)),
  ];
}

const miningSwingDuration = Duration(seconds: 3);

/// Mining action with rock HP and respawn mechanics.
@immutable
class MiningAction extends Action {
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

final _woodcuttingActions = <Action>[
  const Action(
    skill: Skill.woodcutting,
    name: 'Normal Tree',
    unlockLevel: 1,
    duration: Duration(seconds: 3),
    xp: 10,
    outputs: {'Normal Logs': 1},
  ),
  const Action(
    skill: Skill.woodcutting,
    name: 'Oak Tree',
    unlockLevel: 10,
    duration: Duration(seconds: 4),
    xp: 15,
    outputs: {'Oak Logs': 1},
  ),
  const Action(
    skill: Skill.woodcutting,
    name: 'Willow Tree',
    unlockLevel: 20,
    duration: Duration(seconds: 5),
    xp: 22,
    outputs: {'Willow Logs': 1},
  ),
  const Action(
    skill: Skill.woodcutting,
    name: 'Teak Tree',
    unlockLevel: 35,
    duration: Duration(seconds: 6),
    xp: 30,
    outputs: {'Teak Logs': 1},
  ),
];

final _firemakingActions = <Action>[
  const Action(
    skill: Skill.firemaking,
    name: 'Burn Normal Logs',
    unlockLevel: 1,
    duration: Duration(seconds: 2),
    xp: 19,
    inputs: {'Normal Logs': 1},
  ),
  const Action(
    skill: Skill.firemaking,
    name: 'Burn Oak Logs',
    unlockLevel: 10,
    duration: Duration(seconds: 2),
    xp: 39,
    inputs: {'Oak Logs': 1},
  ),
  const Action(
    skill: Skill.firemaking,
    name: 'Burn Willow Logs',
    unlockLevel: 25,
    duration: Duration(seconds: 3),
    xp: 52,
    inputs: {'Willow Logs': 1},
  ),
  const Action(
    skill: Skill.firemaking,
    name: 'Burn Teak Logs',
    unlockLevel: 35,
    duration: Duration(seconds: 4),
    xp: 84,
    inputs: {'Teak Logs': 1},
  ),
];

final _fishingActions = <Action>[
  const Action.ranged(
    skill: Skill.fishing,
    name: 'Raw Shrimp',
    unlockLevel: 1,
    minDuration: Duration(seconds: 4),
    maxDuration: Duration(seconds: 8),
    xp: 10,
    outputs: {'Raw Shrimp': 1},
  ),
];

final _miningActions = <MiningAction>[
  MiningAction(
    name: 'Rune Essence',
    unlockLevel: 1,
    xp: 5,
    outputs: const {'Rune Essence': 2},
    respawnSeconds: 1,
    rockType: RockType.essence,
  ),
  MiningAction(
    name: 'Copper',
    unlockLevel: 1,
    xp: 7,
    outputs: const {'Copper Ore': 1},
    respawnSeconds: 5,
    rockType: RockType.ore,
  ),
  MiningAction(
    name: 'Tin',
    unlockLevel: 1,
    xp: 7,
    outputs: const {'Tin Ore': 1},
    respawnSeconds: 5,
    rockType: RockType.ore,
  ),
  MiningAction(
    name: 'Iron',
    unlockLevel: 15,
    xp: 14,
    outputs: const {'Iron Ore': 1},
    respawnSeconds: 10,
    rockType: RockType.ore,
  ),
];

final _smithingActions = <Action>[
  const Action(
    skill: Skill.smithing,
    name: 'Bronze Bar',
    unlockLevel: 1,
    duration: Duration(seconds: 2),
    xp: 5,
    inputs: {'Copper Ore': 1, 'Tin Ore': 1},
    outputs: {'Bronze Bar': 1},
  ),
  const Action(
    skill: Skill.smithing,
    name: 'Iron Bar',
    unlockLevel: 10,
    duration: Duration(seconds: 2),
    xp: 8,
    inputs: {'Iron Ore': 1},
    outputs: {'Iron Bar': 1},
  ),
];

final List<Action> _all = [
  ..._woodcuttingActions,
  ..._firemakingActions,
  ..._fishingActions,
  ..._miningActions,
  ..._smithingActions,
];

// Skill-level drops: shared across all actions in a skill.
// This can include both simple Drops and DropTables.
final _skillDrops = <Skill, List<Droppable>>{
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
  Skill.mining: [
    miningGemTable, // DropTable is a Drop, so it can go here
  ],
  Skill.smithing: [
    // Add smithing skill-level drops here as needed
  ],
};

// Global drops: shared across all skills/actions
final _globalDrops = <Droppable>[
  // Add global drops here as needed
  // Example: Drop(name: 'Lucky Coin', rate: 0.0001),
];

class ActionRegistry {
  ActionRegistry(this._all);

  final List<Action> _all;

  Action byName(String name) {
    return _all.firstWhere((action) => action.name == name);
  }

  Iterable<Action> forSkill(Skill skill) {
    return _all.where((action) => action.skill == skill);
  }
}

final actionRegistry = ActionRegistry(_all);

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

  /// Returns all drops that should be processed when an action completes.
  /// This combines action-level drops (from the action), skill-level drops,
  /// and global drops into a single list. Includes both simple Drops and
  /// DropTables, which are processed uniformly via Droppable.roll().
  List<Droppable> allDropsForAction(Action action) {
    return [
      ...action.rewards, // Action-level drops
      ...forSkill(action.skill), // Skill-level drops (may include DropTables)
      ...global, // Global drops
    ];
  }
}

final dropsRegistry = DropsRegistry(_skillDrops, _globalDrops);
