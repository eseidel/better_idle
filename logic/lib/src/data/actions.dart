import 'dart:math';

import 'package:logic/src/tick.dart';
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

import 'combat.dart';
import 'melvor_id.dart';
import 'mining.dart';

export 'combat.dart';
export 'cooking.dart';
export 'crafting.dart';
export 'firemaking.dart';
export 'fishing.dart';
export 'fletching.dart';
export 'items.dart';
export 'mining.dart';
export 'smithing.dart';
export 'thieving.dart';
export 'woodcutting.dart';

/// Hard-coded list of skills.  We sometimes wish to refer to a skill in code
/// this allows us to do that at compile time rather than at runtime.
enum Skill {
  hitpoints('Hitpoints'),
  attack('Attack'),
  woodcutting('Woodcutting'),
  firemaking('Firemaking'),
  fishing('Fishing'),
  cooking('Cooking'),
  mining('Mining'),
  smithing('Smithing'),
  thieving('Thieving'),
  fletching('Fletching'),
  crafting('Crafting');

  const Skill(this.name);

  /// Returns the skill for the given name (e.g., "Woodcutting").
  /// Used for deserializing saved game state. Throws if not recognized.
  factory Skill.fromName(String name) {
    return Skill.values.firstWhere((e) => e.name == name);
  }

  final String name;

  /// Returns the skill for the given ID.
  /// Throws if the skill is not recognized.
  factory Skill.fromId(MelvorId id) {
    return values.firstWhere(
      (e) => e.id == id,
      orElse: () => throw ArgumentError('Unknown skill ID: $id'),
    );
  }

  /// Returns the skill for the given ID, or null if not recognized.
  static Skill? tryFromId(MelvorId id) {
    for (final skill in values) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  /// The Melvor ID for this skill (e.g., melvorD:Woodcutting).
  /// All skills use the melvorD namespace (e.g., melvorD:Woodcutting).
  MelvorId get id => MelvorId('melvorD:$name');
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
  });

  final int xp;
  final int unlockLevel;
  final Duration minDuration;
  final Duration maxDuration;
  final Map<MelvorId, int> inputs;
  final Map<MelvorId, int> outputs;

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

  CombatAction combatActionById(MelvorId id) => byId(id) as CombatAction;
}

class DropsRegistry {
  DropsRegistry(this._skillDrops);

  final Map<Skill, List<Droppable>> _skillDrops;

  /// Returns all skill-level drops for a given skill.
  List<Droppable> forSkill(Skill skill) {
    return _skillDrops[skill] ?? [];
  }

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
      // Missing global drops.
    ];
  }
}
