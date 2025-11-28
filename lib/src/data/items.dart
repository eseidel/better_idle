final _all = [
  Item(name: 'Normal Logs', goldValue: 5),
  Item(name: 'Oak Logs', goldValue: 10),
];

class Item {
  const Item({required this.name, required this.goldValue});

  final String name;
  final int goldValue;
}

class ItemRegistry {
  ItemRegistry(this._all);

  final List<Item> _all;

  Item byName(String name) {
    return _all.firstWhere((item) => item.name == name);
  }
}

final itemRegistry = ItemRegistry(_all);
