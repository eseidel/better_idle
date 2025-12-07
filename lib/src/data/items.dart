import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

const _all = [
  Item(name: 'Normal Logs', sellsFor: 1),
  Item(name: 'Oak Logs', sellsFor: 5),
  Item(name: 'Willow Logs', sellsFor: 10),
  Item(name: 'Teak Logs', sellsFor: 20),
  Item(name: 'Bird Nest', sellsFor: 350),
  Item(name: 'Coal Ore', sellsFor: 13),
  Item(name: 'Ash', sellsFor: 5),
  Item(name: 'Raw Shrimp', sellsFor: 3),
  Item(name: 'Rune Essence', sellsFor: 0),
  Item(name: 'Copper Ore', sellsFor: 2),
  Item(name: 'Tin Ore', sellsFor: 2),
  Item(name: 'Iron Ore', sellsFor: 5),
];

@immutable
class Item extends Equatable {
  const Item({required this.name, required this.sellsFor});

  final String name;
  final int sellsFor;

  @override
  List<Object?> get props => [name, sellsFor];
}

class ItemRegistry {
  ItemRegistry(this._all);

  final List<Item> _all;

  Item byName(String name) {
    return _all.firstWhere((item) => item.name == name);
  }
}

final itemRegistry = ItemRegistry(_all);
