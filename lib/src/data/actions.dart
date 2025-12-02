import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/drop.dart';

enum Skill {
  woodcutting('Woodcutting');

  const Skill(this.name);

  factory Skill.fromName(String name) {
    return Skill.values.firstWhere((e) => e.name == name);
  }

  final String name;
}

final _all = [
  const Action(
    skill: Skill.woodcutting,
    name: 'Normal Tree',
    duration: Duration(seconds: 3),
    xp: 10,
    rewards: [
      Drop(name: 'Normal Logs'),
      Drop(name: 'Bird Nest', rate: 0.005),
    ],
  ),
  const Action(
    skill: Skill.woodcutting,
    name: 'Oak Tree',
    duration: Duration(seconds: 4),
    xp: 15,
    rewards: [
      Drop(name: 'Oak Logs'),
      Drop(name: 'Bird Nest', rate: 0.005),
    ],
  ),
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
