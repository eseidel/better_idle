import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

const _woodcutting = [
  Item('Normal Logs', gp: 1),
  Item('Oak Logs', gp: 5),
  Item('Willow Logs', gp: 10),
  Item('Teak Logs', gp: 20),
  Item('Bird Nest', gp: 350),
];

const _firemaking = [Item('Coal Ore', gp: 13), Item('Ash', gp: 5)];

const _fishing = [
  Item('Raw Shrimp', gp: 3),
  Item('Raw Lobster', gp: 65),
  Item('Raw Crab', gp: 135),
  Item('Raw Sardine', gp: 3),
  Item('Raw Herring', gp: 8),
];

const _cooking = [
  Item('Shrimp', gp: 2, healsFor: 30),
  Item('Lobster', gp: 108, healsFor: 110),
  Item('Crab', gp: 280, healsFor: 150),
  Item('Sardine', gp: 5, healsFor: 40),
  Item('Herring', gp: 10, healsFor: 50),
];

const _mining = [
  Item('Rune Essence', gp: 0),
  Item('Copper Ore', gp: 2),
  Item('Tin Ore', gp: 2),
  Item('Iron Ore', gp: 5),
];

const _bars = [
  Item('Bronze Bar', gp: 6),
  Item('Iron Bar', gp: 12),
  Item('Steel Bar', gp: 30),
];

const _smithing = <Item>[..._bars, Item('Bronze Dagger', gp: 1)];

const _gems = [
  Item('Topaz', gp: 225),
  Item('Sapphire', gp: 335),
  Item('Ruby', gp: 555),
  Item('Emerald', gp: 555),
  Item('Diamond', gp: 1150),
];

const _thieving = [Item("Bobby's Pocket", gp: 4000)];

// Farming items (from openables like Egg Chest)
const _farming = [
  Item('Feathers', gp: 2), // Inferred from 1-1000 feathers = 2-2000GP
  Item('Raw Chicken', gp: 1), // Inferred from 1-40 chicken = 1-40GP
];

// Openable items (chests, etc.)
const _openables = [Item('Egg Chest', gp: 100)];

const List<Item> _all = [
  ..._woodcutting,
  ..._firemaking,
  ..._fishing,
  ..._cooking,
  ..._mining,
  ..._smithing,
  ..._gems,
  ..._thieving,
  ..._farming,
  ..._openables,
];

@immutable
class Item extends Equatable {
  const Item(this.name, {required int gp, this.healsFor}) : sellsFor = gp;

  final String name;
  final int sellsFor;

  /// The amount of HP this item heals when consumed. Null if not consumable.
  final int? healsFor;

  /// Whether this item can be consumed for healing.
  bool get isConsumable => healsFor != null;

  @override
  List<Object?> get props => [name, sellsFor, healsFor];
}

class ItemRegistry {
  ItemRegistry(this._all);

  final List<Item> _all;

  Item byName(String name) {
    return _all.firstWhere((item) => item.name == name);
  }
}

final itemRegistry = ItemRegistry(_all);
