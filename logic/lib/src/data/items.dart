import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/inventory.dart';
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
  Item('Raw Shrimp', gp: 1),
  Item('Raw Lobster', gp: 65),
  Item('Raw Crab', gp: 135),
  Item('Raw Sardine', gp: 3),
  Item('Raw Herring', gp: 8),
  Item('Raw Trout', gp: 16),
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
  Item('Mithril Bar', gp: 125),
];

const _smithing = <Item>[..._bars, Item('Bronze Dagger', gp: 1)];

const _gems = [
  Item('Topaz', gp: 225),
  Item('Sapphire', gp: 335),
  Item('Ruby', gp: 555),
  Item('Emerald', gp: 555),
  Item('Diamond', gp: 1150),
];

const _thieving = [
  Item("Bobby's Pocket", gp: 4000),
  // TODO(eseidel): Missing equipped effect for Jeweled Necklace.
  // +5% Global GP (except Item Sales)
  Item('Jeweled Necklace', gp: 5000),
];

// Ranged items (arrows)
const _ranged = [
  Item('Bronze Arrows', gp: 1),
  Item('Iron Arrows', gp: 2),
  Item('Steel Arrows', gp: 3),
  Item('Mithril Arrows', gp: 8),
];

// Farming items (from openables like Egg Chest)
const _farming = [
  Item('Feathers', gp: 2), // Inferred from 1-1000 feathers = 2-2000GP
  Item('Raw Chicken', gp: 1), // Inferred from 1-40 chicken = 1-40GP
];

// Openable items (chests, etc.)
final _openables = <Openable>[
  Openable(
    'Egg Chest',
    gp: 100,
    dropTable: DropTable([
      Pick.range('Feathers', weight: 1, min: 1, max: 1000),
      Pick.range('Raw Chicken', weight: 1, min: 1, max: 40),
    ]),
  ),
  Openable(
    'Crate of Basic Supplies',
    gp: 100,
    dropTable: DropTable([
      Pick.range('Bronze Arrows', weight: 25, min: 1, max: 200),
      Pick.range('Raw Shrimp', weight: 25, min: 1, max: 200),
      Pick.range('Iron Arrows', weight: 20, min: 1, max: 200),
      Pick.range('Raw Sardine', weight: 18, min: 1, max: 200),
      Pick.range('Steel Arrows', weight: 18, min: 1, max: 200),
      Pick.range('Bronze Bar', weight: 14, min: 1, max: 200),
      Pick.range('Raw Herring', weight: 13, min: 1, max: 200),
      Pick.range('Mithril Arrows', weight: 13, min: 1, max: 200),
      Pick.range('Iron Bar', weight: 11, min: 1, max: 200),
      Pick.range('Raw Trout', weight: 10, min: 1, max: 200),
      Pick.range('Steel Bar', weight: 9, min: 1, max: 200),
      Pick.range('Mithril Bar', weight: 5, min: 1, max: 200),
    ]),
  ),
];

final _all = <Item>[
  ..._woodcutting,
  ..._firemaking,
  ..._fishing,
  ..._cooking,
  ..._mining,
  ..._smithing,
  ..._gems,
  ..._thieving,
  ..._ranged,
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

/// An item that can be opened to receive drops from a weighted table.
@immutable
class Openable extends Item {
  // DropTable constructor guarantees non-empty entries.
  const Openable(super.name, {required super.gp, required this.dropTable});

  /// The drop table for this openable.
  final DropTable dropTable;

  /// Opens this item once and returns the resulting drop.
  ItemStack open(Random random) => dropTable.roll(random);

  @override
  List<Object?> get props => [...super.props, dropTable];
}

class ItemRegistry {
  ItemRegistry(this._all);

  final List<Item> _all;

  /// All registered items.
  List<Item> get all => _all;

  /// Returns the item by name, or throws a StateError if not found.
  Item byName(String name) => _all.firstWhere((item) => item.name == name);

  /// Returns the index of the item in the registry, or -1 if not found.
  int indexForItem(Item item) => _all.indexOf(item);
}

final itemRegistry = ItemRegistry(_all);
