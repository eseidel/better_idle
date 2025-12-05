import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/drop.dart';

enum Skill {
  woodcutting('Woodcutting'),
  firemaking('Firemaking'),
  fishing('Fishing');

  const Skill(this.name);

  factory Skill.fromName(String name) {
    return Skill.values.firstWhere((e) => e.name == name);
  }

  final String name;
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

final List<Action> _all = [
  ..._woodcuttingActions,
  ..._firemakingActions,
  ..._fishingActions,
];

// Skill-level drops: shared across all actions in a skill
final _skillDrops = <Skill, List<Drop>>{
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
  // Add other skills as they're added
};

// Global drops: shared across all skills/actions
final _globalDrops = <Drop>[
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

  final Map<Skill, List<Drop>> _skillDrops;
  final List<Drop> _globalDrops;

  /// Returns all skill-level drops for a given skill.
  List<Drop> forSkill(Skill skill) {
    return _skillDrops[skill] ?? [];
  }

  /// Returns all global drops.
  List<Drop> get global => _globalDrops;

  /// Returns all drops that should be processed when an action completes.
  /// This combines action-level drops (from the action), skill-level drops,
  /// and global drops into a single list.
  List<Drop> allDropsForAction(Action action) {
    return [
      ...action.rewards, // Action-level drops
      ...forSkill(action.skill), // Skill-level drops
      ...global, // Global drops
    ];
  }
}

final dropsRegistry = DropsRegistry(_skillDrops, _globalDrops);
