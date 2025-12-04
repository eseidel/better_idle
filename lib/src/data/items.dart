const _all = [
  Item(name: 'Normal Logs', sellsFor: 1),
  Item(name: 'Oak Logs', sellsFor: 5),
  Item(name: 'Bird Nest', sellsFor: 350),
  Item(name: 'Coal Ore', sellsFor: 13),
  Item(name: 'Ash', sellsFor: 5),
];

class Item {
  const Item({required this.name, required this.sellsFor});

  final String name;
  final int sellsFor;
}

class ItemRegistry {
  ItemRegistry(this._all);

  final List<Item> _all;

  Item byName(String name) {
    return _all.firstWhere((item) => item.name == name);
  }
}

final itemRegistry = ItemRegistry(_all);
