import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/types/inventory.dart';

class Drop {
  const Drop(this.name, {this.count = 1, this.rate = 1.0});

  final String name;
  final int count;
  final double rate;

  ItemStack toItemStack() {
    final item = itemRegistry.byName(name);
    return ItemStack(item, count: count);
  }
}
