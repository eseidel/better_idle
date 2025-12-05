import 'package:better_idle/src/data/items.dart';

class ItemStack {
  const ItemStack(this.item, {required this.count});
  final Item item;
  final int count;

  ItemStack copyWith({int? count}) {
    return ItemStack(item, count: count ?? this.count);
  }

  int get sellsFor => item.sellsFor * count;
}

class Inventory {
  const Inventory.empty() : _counts = const {}, _orderedItems = const [];

  Inventory.fromItems(List<ItemStack> stacks)
    : _counts = {},
      _orderedItems = [] {
    for (final stack in stacks) {
      _counts[stack.item] = stack.count;
      _orderedItems.add(stack.item);
    }
  }

  Inventory._({
    required Map<Item, int> counts,
    required List<Item> orderedItems,
  }) : _counts = counts,
       _orderedItems = orderedItems;

  Inventory.fromJson(Map<String, dynamic> json)
    : _counts = {},
      _orderedItems = [] {
    final countsJson = json['counts'] as Map<String, dynamic>;
    final orderedItemsJson = json['orderedItems'] as List<dynamic>;

    for (final name in orderedItemsJson) {
      // If the item name is not in the registry this will throw a BadStateError
      // Consider a mode that handles gracefully ignores unknown items.
      final item = itemRegistry.byName(name as String);
      _counts[item] = countsJson[name] as int;
      _orderedItems.add(item);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'counts': _counts.map((key, value) => MapEntry(key.name, value)),
      'orderedItems': _orderedItems.map((item) => item.name).toList(),
    };
  }

  final Map<Item, int> _counts;
  final List<Item> _orderedItems;

  List<ItemStack> get items => _orderedItems
      .map((item) => ItemStack(item, count: _counts[item]!))
      .toList();

  int countOfItem(Item item) => _counts[item] ?? 0;

  Inventory adding(ItemStack stack) {
    final counts = Map<Item, int>.from(_counts);
    final orderedItems = List<Item>.from(_orderedItems);
    final existingCount = counts[stack.item];
    if (existingCount == null) {
      counts[stack.item] = stack.count;
      orderedItems.add(stack.item);
    } else {
      counts[stack.item] = existingCount + stack.count;
    }
    return Inventory._(counts: counts, orderedItems: orderedItems);
  }

  Inventory removing(ItemStack stack) {
    final counts = Map<Item, int>.from(_counts);
    final orderedItems = List<Item>.from(_orderedItems);
    final existingCount = counts[stack.item];
    if (existingCount == null) {
      return this; // Item not in inventory, return unchanged
    }
    final newCount = existingCount - stack.count;
    if (newCount <= 0) {
      counts.remove(stack.item);
      orderedItems.remove(stack.item);
    } else {
      counts[stack.item] = newCount;
    }
    return Inventory._(counts: counts, orderedItems: orderedItems);
  }
}
