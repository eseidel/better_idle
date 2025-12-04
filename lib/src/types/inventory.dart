class ItemStack {
  const ItemStack({required this.name, required this.count});
  final String name;
  final int count;

  ItemStack copyWith({int? count}) {
    return ItemStack(name: name, count: count ?? this.count);
  }
}

class Inventory {
  Inventory.fromItems(List<ItemStack> items)
    : _counts = {},
      _orderedItems = [] {
    for (final item in items) {
      _counts[item.name] = item.count;
      _orderedItems.add(item.name);
    }
  }

  Inventory.empty() : this.fromItems([]);

  Inventory._({
    required Map<String, int> counts,
    required List<String> orderedItems,
  }) : _counts = counts,
       _orderedItems = orderedItems;

  Inventory.fromJson(Map<String, dynamic> json)
    : _counts = Map<String, int>.from(json['counts'] as Map<String, dynamic>),
      _orderedItems = List<String>.from(json['orderedItems'] as List<dynamic>);

  Map<String, dynamic> toJson() {
    return {'counts': _counts, 'orderedItems': _orderedItems};
  }

  final Map<String, int> _counts;
  final List<String> _orderedItems;

  List<ItemStack> get items =>
      _orderedItems.map((e) => ItemStack(name: e, count: _counts[e]!)).toList();

  int countOfItem(String name) {
    return _counts[name] ?? 0;
  }

  Inventory adding(ItemStack item) {
    final counts = Map<String, int>.from(_counts);
    final orderedItems = List<String>.from(_orderedItems);
    final existingCount = counts[item.name];
    if (existingCount == null) {
      counts[item.name] = item.count;
      orderedItems.add(item.name);
    } else {
      counts[item.name] = existingCount + item.count;
    }
    return Inventory._(counts: counts, orderedItems: orderedItems);
  }

  Inventory removing(ItemStack item) {
    final counts = Map<String, int>.from(_counts);
    final orderedItems = List<String>.from(_orderedItems);
    final existingCount = counts[item.name];
    if (existingCount == null) {
      return this; // Item not in inventory, return unchanged
    }
    final newCount = existingCount - item.count;
    if (newCount <= 0) {
      counts.remove(item.name);
      orderedItems.remove(item.name);
    } else {
      counts[item.name] = newCount;
    }
    return Inventory._(counts: counts, orderedItems: orderedItems);
  }
}
