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

const _fishing = [Item('Raw Shrimp', gp: 3)];

const _cooking = [Item('Shrimp', gp: 2, healsFor: 30)];

const _mining = [
  Item('Rune Essence', gp: 0),
  Item('Copper Ore', gp: 2),
  Item('Tin Ore', gp: 2),
  Item('Iron Ore', gp: 5),
];

const _bars = [Item('Bronze Bar', gp: 6), Item('Iron Bar', gp: 12)];

const _smithing = <Item>[..._bars, Item('Bronze Dagger', gp: 1)];

const _gems = [
  Item('Topaz', gp: 225),
  Item('Sapphire', gp: 335),
  Item('Ruby', gp: 555),
  Item('Emerald', gp: 555),
  Item('Diamond', gp: 1150),
];

const List<Item> _all = [
  ..._woodcutting,
  ..._firemaking,
  ..._fishing,
  ..._cooking,
  ..._mining,
  ..._smithing,
  ..._gems,
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
