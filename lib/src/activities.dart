import 'state.dart';

typedef OnComplete = GlobalState Function(GlobalState state);

OnComplete add(String itemName, int count) =>
    (state) => state.copyWith(
      inventory: state.inventory.adding(
        ItemStack(name: itemName, count: count),
      ),
    );

final woodcutting = Activity(
  name: 'Woodcutting',
  maxValue: 10,
  onComplete: add('Wood', 1),
);

final allActivities = [woodcutting];

Activity getActivity(String name) {
  return allActivities.firstWhere((activity) => activity.name == name);
}
