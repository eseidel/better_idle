import 'state.dart';

typedef OnComplete = GlobalState Function(GlobalState state);

enum Skill { woodcutting }

OnComplete add(String itemName, int count) =>
    (state) => state.copyWith(
      inventory: state.inventory.adding(
        ItemStack(name: itemName, count: count),
      ),
    );

final allActivities = [
  Activity(
    skill: Skill.woodcutting,
    name: 'Normal Tree',
    duration: Duration(seconds: 3),
    onComplete: add('Normal Logs', 1),
  ),
  Activity(
    skill: Skill.woodcutting,
    name: 'Oak Tree',
    duration: Duration(seconds: 3),
    onComplete: add('Oak Logs', 1),
  ),
];

Activity getActivity(String name) {
  return allActivities.firstWhere((activity) => activity.name == name);
}
