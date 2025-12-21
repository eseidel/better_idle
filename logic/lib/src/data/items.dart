import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/melvor_data.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// An entry in a drop table from the Melvor JSON data.
@immutable
class DropTableEntry extends Equatable {
  const DropTableEntry({
    required this.itemID,
    required this.minQuantity,
    required this.maxQuantity,
    required this.weight,
  });

  /// Creates a DropTableEntry from a JSON map.
  factory DropTableEntry.fromJson(Map<String, dynamic> json) {
    return DropTableEntry(
      itemID: json['itemID'] as String,
      minQuantity: json['minQuantity'] as int,
      maxQuantity: json['maxQuantity'] as int,
      weight: json['weight'] as int,
    );
  }

  /// The fully qualified item ID (e.g., "melvorD:Normal_Logs").
  final String itemID;

  /// The minimum quantity that can drop.
  final int minQuantity;

  /// The maximum quantity that can drop.
  final int maxQuantity;

  /// The weight of this entry in the drop table.
  final int weight;

  /// Extracts the item name from the fully qualified itemID.
  /// e.g., "melvorD:Normal_Logs" -> "Normal_Logs"
  String get itemIdWithoutNamespace {
    final colonIndex = itemID.indexOf(':');
    return colonIndex >= 0 ? itemID.substring(colonIndex + 1) : itemID;
  }

  /// Converts this entry to a Pick for use in a DropTable.
  Pick toPick(Map<String, Item> itemsById) {
    final item = itemsById[itemIdWithoutNamespace];
    if (item == null) {
      throw StateError('Item not found for drop table entry: $itemID');
    }
    return Pick.range(
      item.name,
      min: minQuantity,
      max: maxQuantity,
      weight: weight.toDouble(),
    );
  }

  @override
  List<Object?> get props => [itemID, minQuantity, maxQuantity, weight];

  @override
  String toString() =>
      'DropTableEntry($itemID, $minQuantity-$maxQuantity, weight: $weight)';
}

/// An item loaded from the Melvor game data.
@immutable
class Item extends Equatable {
  const Item({
    required this.id,
    required this.name,
    required this.itemType,
    required this.sellsFor,
    this.category,
    this.type,
    this.healsFor,
  });

  /// Creates a simple test item with minimal required fields.
  /// Only for use in tests.
  @visibleForTesting
  const Item.test(this.name, {required int gp, this.healsFor})
    : id = name,
      itemType = 'Item',
      sellsFor = gp,
      category = null,
      type = null;

  /// Creates an Item from a JSON map.
  factory Item.fromJson(Map<String, dynamic> json) {
    // Melvor uses HP/10, we use actual HP values, so multiply by 10.
    final rawHealsFor = json['healsFor'] as num?;
    final healsFor = rawHealsFor != null ? (rawHealsFor * 10).toInt() : null;

    return Item(
      id: json['id'] as String,
      name: json['name'] as String,
      itemType: json['itemType'] as String,
      sellsFor: json['sellsFor'] as int,
      category: json['category'] as String?,
      type: json['type'] as String?,
      healsFor: healsFor,
    );
  }

  /// The unique identifier for this item (e.g., "Normal_Logs").
  final String id;

  /// The display name for this item (e.g., "Normal Logs").
  final String name;

  /// The type of item (e.g., "Item", "Food", "Weapon", "Equipment").
  final String itemType;

  /// The amount of GP this item sells for.
  final int sellsFor;

  /// The category of this item (e.g., "Woodcutting", "Fishing").
  final String? category;

  /// The sub-type of this item (e.g., "Logs", "Raw Fish", "Food").
  final String? type;

  /// The amount of HP this item heals when consumed. Null if not consumable.
  final int? healsFor;

  /// Whether this item can be consumed for healing.
  bool get isConsumable => healsFor != null;

  @override
  List<Object?> get props => [
    id,
    name,
    itemType,
    sellsFor,
    category,
    type,
    healsFor,
  ];

  @override
  String toString() => 'Item($name)';
}

/// An item that can be opened to receive drops from a weighted table.
@immutable
class Openable extends Item {
  const Openable({
    required super.id,
    required super.name,
    required super.itemType,
    required super.sellsFor,
    super.category,
    super.type,
    super.healsFor,
    required this.dropTable,
  });

  /// The drop table for this openable.
  final DropTable dropTable;

  /// Opens this item once and returns the resulting drop.
  ItemStack open(Random random) => dropTable.roll(random);

  @override
  List<Object?> get props => [...super.props, dropTable];
}

class ItemRegistry {
  ItemRegistry._(this._all, this._byName, this._byId);

  final List<Item> _all;
  final Map<String, Item> _byName;
  final Map<String, Item> _byId;

  /// All registered items.
  List<Item> get all => _all;

  /// Returns the item by name, or throws a StateError if not found.
  Item byName(String name) {
    final item = _byName[name];
    if (item == null) {
      throw StateError('Item not found: $name');
    }
    return item;
  }

  /// Returns the item by id, or throws a StateError if not found.
  Item byId(String id) {
    final item = _byId[id];
    if (item == null) {
      throw StateError('Item not found by id: $id');
    }
    return item;
  }

  /// Returns the index of the item in the registry, or -1 if not found.
  int indexForItem(Item item) => _all.indexOf(item);
}

late ItemRegistry itemRegistry;

/// Initializes the global itemRegistry from MelvorData.
void initializeItems(MelvorData data) {
  final items = <Item>[];
  final byName = <String, Item>{};
  final byId = <String, Item>{};

  // First pass: load all items as basic Items.
  for (final name in data.itemNames) {
    final json = data.lookupItem(name);
    if (json != null) {
      final item = Item.fromJson(json);
      items.add(item);
      byName[item.name] = item;
      byId[item.id] = item;
    }
  }

  // Second pass: convert Openable items, replacing the basic Item.
  final updatedItems = <Item>[];
  for (final item in items) {
    final json = data.lookupItem(item.name)!;
    final dropTableJson = json['dropTable'] as List<dynamic>?;

    if (dropTableJson != null && dropTableJson.isNotEmpty) {
      // Convert DropTableEntry list to Pick list for DropTable.
      final picks = <Pick>[];
      for (final entry in dropTableJson) {
        final dropEntry = DropTableEntry.fromJson(
          entry as Map<String, dynamic>,
        );
        try {
          picks.add(dropEntry.toPick(byId));
        } catch (e) {
          // Skip entries that reference items we don't have.
          // This can happen with expansion content.
        }
      }

      if (picks.isNotEmpty) {
        final openable = Openable(
          id: item.id,
          name: item.name,
          itemType: item.itemType,
          sellsFor: item.sellsFor,
          category: item.category,
          type: item.type,
          healsFor: item.healsFor,
          dropTable: DropTable(picks),
        );
        updatedItems.add(openable);
        byName[item.name] = openable;
        byId[item.id] = openable;
      } else {
        updatedItems.add(item);
      }
    } else {
      updatedItems.add(item);
    }
  }

  itemRegistry = ItemRegistry._(updatedItems, byName, byId);
}
