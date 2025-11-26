import 'state.dart';

enum Skill { woodcutting }

final allActivities = [
  Activity(
    skill: Skill.woodcutting,
    name: 'Normal Tree',
    duration: Duration(seconds: 3),
    xp: 10,
    rewards: [ItemStack(name: 'Normal Logs', count: 1)],
  ),
  Activity(
    skill: Skill.woodcutting,
    name: 'Oak Tree',
    duration: Duration(seconds: 3),
    xp: 15,
    rewards: [ItemStack(name: 'Oak Logs', count: 1)],
  ),
];

Activity getActivity(String name) {
  return allActivities.firstWhere((activity) => activity.name == name);
}
