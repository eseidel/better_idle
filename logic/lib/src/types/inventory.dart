import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/melvor_id.dart';

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
  Inventory.fromJson(ItemRegistry items, Map<String, dynamic> json)
    : _items = items,
      _counts = {},
      _orderedItems = [] {
    final countsJson = json['counts'] as Map<String, dynamic>;
    final orderedItemsJson = json['orderedItems'] as List<dynamic>;

    for (final idString in orderedItemsJson) {
      // If the item id is not in the registry this will throw a StateError.
      // Consider a mode that gracefully ignores unknown items.
      final id = MelvorId.fromJson(idString as String);
      final item = items.byId(id);
      _counts[item] = countsJson[idString] as int;
      _orderedItems.add(item);
    }
  }
  const Inventory.empty(ItemRegistry items)
    : _items = items,
      _counts = const {},
      _orderedItems = const [];

  Inventory.fromItems(ItemRegistry items, List<ItemStack> stacks)
    : _items = items,
      _counts = {},
      _orderedItems = [] {
    for (final stack in stacks) {
      _counts[stack.item] = stack.count;
      _orderedItems.add(stack.item);
    }
  }

  Inventory._({
    required ItemRegistry items,
    required Map<Item, int> counts,
    required List<Item> orderedItems,
  }) : _items = items,
       _counts = counts,
       _orderedItems = orderedItems;

  final ItemRegistry _items;

  Map<String, dynamic> toJson() {
    return {
      'counts': _counts.map((key, value) => MapEntry(key.id.toJson(), value)),
      'orderedItems': _orderedItems.map((item) => item.id.toJson()).toList(),
    };
  }

  final Map<Item, int> _counts;
  final List<Item> _orderedItems;

  List<ItemStack> get items => _orderedItems
      .map((item) => ItemStack(item, count: _counts[item]!))
      .toList();

  int countOfItem(Item item) => _counts[item] ?? 0;

  int countById(MelvorId id) {
    final item = _items.byId(id);
    return countOfItem(item);
  }

  /// Returns true if the item can be added to this inventory.
  /// An item can be added if there's an existing stack of the same item,
  /// or if there's room for a new item type (slots < capacity).
  bool canAdd(Item item, {required int capacity}) {
    // If we already have this item type, we can always stack more
    if (_counts.containsKey(item)) {
      return true;
    }
    // Otherwise, we need an empty slot
    return _orderedItems.length < capacity;
  }

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
    return Inventory._(
      items: _items,
      counts: counts,
      orderedItems: orderedItems,
    );
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
    return Inventory._(
      items: _items,
      counts: counts,
      orderedItems: orderedItems,
    );
  }

  int _itemRegistryOrder(Item a, Item b) {
    final indexA = _items.indexForItem(a);
    final indexB = _items.indexForItem(b);
    return indexA.compareTo(indexB);
  }

  /// Returns a new inventory with items sorted by their registry order.
  Inventory sorted([int Function(Item, Item)? compare]) {
    final orderedItems = List<Item>.from(_orderedItems)
      ..sort(compare ?? _itemRegistryOrder);
    return Inventory._(
      items: _items,
      counts: Map<Item, int>.from(_counts),
      orderedItems: orderedItems,
    );
  }
}
