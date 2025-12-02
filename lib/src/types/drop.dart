import 'package:better_idle/src/types/inventory.dart';

class Drop {
  const Drop({required this.name, this.count = 1, this.rate = 1.0});

  final String name;
  final int count;
  final double rate;

  ItemStack toItemStack() {
    return ItemStack(name: name, count: count);
  }
}
