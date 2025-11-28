import 'state.dart';

enum Skill {
  woodcutting('Woodcutting');

  const Skill(this.name);

  final String name;

  factory Skill.fromName(String name) {
    return Skill.values.firstWhere((e) => e.name == name);
  }
}

final _all = [
  Action(
    skill: Skill.woodcutting,
    name: 'Normal Tree',
    duration: Duration(seconds: 3),
    xp: 10,
    rewards: [ItemStack(name: 'Normal Logs', count: 1)],
  ),
  Action(
    skill: Skill.woodcutting,
    name: 'Oak Tree',
    duration: Duration(seconds: 4),
    xp: 15,
    rewards: [ItemStack(name: 'Oak Logs', count: 1)],
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
