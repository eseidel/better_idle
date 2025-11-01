import 'state.dart';

final woodcutting = Activity(
  name: 'Woodcutting',
  maxValue: 100,
  onComplete: (state) {
    return state.copyWith(
      inventory: state.inventory.adding(ItemStack(name: 'Wood', count: 1)),
    );
  },
);
