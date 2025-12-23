import 'dart:math';

import 'package:logic/src/tick.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

import 'combat.dart';
import 'items.dart';
import 'melvor_id.dart';
import 'mining.dart';

export 'combat.dart';
export 'cooking.dart';
export 'firemaking.dart';
export 'fishing.dart';
export 'items.dart';
export 'mining.dart';
export 'smithing.dart';
export 'thieving.dart';
export 'woodcutting.dart';

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

/// Base class for all actions that can occupy the "active" slot.
/// Subclasses: SkillAction (duration-based with xp/outputs) and CombatAction.
@immutable
abstract class Action {
  const Action({required this.id, required this.name, required this.skill});

  final MelvorId id;

  final String name;
  final Skill skill;
}

List<Droppable> defaultRewards(SkillAction action, int masteryLevel) {
  return [...action.outputs.entries.map((e) => Drop(e.key, count: e.value))];
}

/// Default duration modifier function - returns no modifier.
Modifier defaultDurationModifier(SkillAction action, int masteryLevel) {
  return const Modifier();
}

/// Woodcutting duration modifier - at mastery level 99, reduces duration by 0.2s.
Modifier woodcuttingDurationModifier(SkillAction action, int masteryLevel) {
  if (masteryLevel >= 99) {
    // 0.2s = 2 ticks (100ms per tick)
    return const Modifier(flat: -2);
  }
  return const Modifier();
}

// TODO(eseidel): Make this into a more generalized "chance to double" behavior.
List<Droppable> woodcuttingRewards(SkillAction action, int masteryLevel) {
  final outputs = action.outputs;
  if (outputs.length != 1 || outputs.values.first != 1) {
    throw StateError('Unsupported outputs: $outputs.');
  }
  final name = outputs.keys.first.name;
  final doubleMultiplier = masteryLevel ~/ 10;
  final doublePercent = (doubleMultiplier * 0.05 * 100).toInt().clamp(0, 100);
  final singlePercent = (100 - doublePercent).clamp(0, 100);
  return [
    DropTable([
      DropTableEntry.fromName(name, weight: singlePercent),
      DropTableEntry.fromName(name, count: 2, weight: doublePercent),
    ]),
  ];
}

/// A skill-based action that completes after a duration, granting xp and drops.
/// This covers woodcutting, firemaking, fishing, smithing, and mining actions.
@immutable
class SkillAction extends Action {
  const SkillAction({
    required super.id,
    required super.skill,
    required super.name,
    required Duration duration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
    this.rewardsAtLevel = defaultRewards,
    this.durationModifierAtLevel = defaultDurationModifier,
  }) : minDuration = duration,
       maxDuration = duration;

  const SkillAction.ranged({
    required super.id,
    required super.skill,
    required super.name,
    required this.minDuration,
    required this.maxDuration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
    this.rewardsAtLevel = defaultRewards,
    this.durationModifierAtLevel = defaultDurationModifier,
  });

  final int xp;
  final int unlockLevel;
  final Duration minDuration;
  final Duration maxDuration;
  final Map<MelvorId, int> inputs;
  final Map<MelvorId, int> outputs;

  final List<Droppable> Function(SkillAction, int masteryLevel) rewardsAtLevel;
  final Modifier Function(SkillAction, int masteryLevel)
  durationModifierAtLevel;

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

  /// Returns the duration modifier for a given mastery level.
  Modifier durationModifierForMasteryLevel(int masteryLevel) =>
      durationModifierAtLevel(this, masteryLevel);
}

/// Fixed player attack speed in seconds.
const double playerAttackSpeed = 4;

// Skill-level drops: shared across all actions in a skill.
// This can include both simple Drops and DropTables.
final skillDrops = <Skill, List<Droppable>>{
  Skill.woodcutting: [Drop.fromName('Bird Nest', rate: 0.005)],
  Skill.firemaking: [
    Drop.fromName('Coal Ore', rate: 0.40),
    Drop.fromName('Ash', rate: 0.20),
    // Missing Charcoal, Generous Fire Spirit
  ],
  Skill.mining: [miningGemTable],
  Skill.thieving: [Drop(MelvorId('melvorF:Bobbys_Pocket'), rate: 1 / 120)],
};

// Global drops: shared across all skills/actions
final globalDrops = <Droppable>[
  // Add global drops here as needed
  // Example: Drop(name: 'Lucky Coin', rate: 0.0001),
];

class ActionRegistry {
  ActionRegistry(List<Action> all) : _all = all {
    _byId = {for (final action in _all) action.id: action};
    _byName = {for (final action in _all) action.name: action};
  }

  final List<Action> _all;
  late final Map<MelvorId, Action> _byId;
  late final Map<String, Action> _byName;

  /// Returns an Action by id, or throws a StateError if not found.
  Action byId(MelvorId id) {
    final action = _byId[id];
    if (action == null) {
      throw StateError('Missing action with id: $id');
    }
    return action;
  }

  /// Returns an Action by name, or throws a StateError if not found.
  Action byName(String name) {
    final action = _byName[name];
    if (action == null) {
      throw StateError('Missing action $name');
    }
    return action;
  }

  @visibleForTesting
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

  CombatAction combatActionById(MelvorId id) {
    final action = _byId[id];
    if (action == null) {
      throw StateError('Missing combat action with id: $id');
    }
    if (action is! CombatAction) {
      throw StateError('Action $id is not a CombatAction');
    }
    return action;
  }
}

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
