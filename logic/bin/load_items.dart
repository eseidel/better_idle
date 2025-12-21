import 'dart:io';

import 'package:args/args.dart';
import 'package:equatable/equatable.dart';
import 'package:logic/logic.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// An entry in a drop table, representing a possible drop with quantity range.
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

  @override
  List<Object?> get props => [itemID, minQuantity, maxQuantity, weight];

  @override
  String toString() =>
      'DropTableEntry($itemID, $minQuantity-$maxQuantity, weight: $weight)';
}

/// An item loaded from the Melvor game data.
///
/// This class uses field names matching the JSON data structure.
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
    this.dropTable,
  });

  /// Creates an Item from a JSON map.
  factory Item.fromJson(Map<String, dynamic> json) {
    final dropTableJson = json['dropTable'] as List<dynamic>?;
    final dropTable = dropTableJson
        ?.map((e) => DropTableEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    return Item(
      id: json['id'] as String,
      name: json['name'] as String,
      itemType: json['itemType'] as String,
      sellsFor: json['sellsFor'] as int,
      category: json['category'] as String?,
      type: json['type'] as String?,
      healsFor: json['healsFor'] as num?,
      dropTable: dropTable,
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
  /// Note: This can be a decimal value for percentage-based healing.
  final num? healsFor;

  /// The drop table for openable items. Null if not openable.
  final List<DropTableEntry>? dropTable;

  /// Whether this item can be consumed for healing.
  bool get isConsumable => healsFor != null;

  /// Whether this item is openable (has a drop table).
  bool get isOpenable => dropTable != null;

  @override
  List<Object?> get props => [
    id,
    name,
    itemType,
    sellsFor,
    category,
    type,
    healsFor,
    dropTable,
  ];

  @override
  String toString() {
    final buffer = StringBuffer('Item($name');
    buffer.write(', id: $id');
    buffer.write(', itemType: $itemType');
    buffer.write(', sellsFor: $sellsFor');
    if (category != null) buffer.write(', category: $category');
    if (type != null) buffer.write(', type: $type');
    if (healsFor != null) buffer.write(', healsFor: $healsFor');
    if (dropTable != null) {
      buffer.write(', dropTable: ${dropTable!.length} entries');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

/// Loads all items from the Melvor data and returns them as Item objects.
List<Item> loadItems(MelvorData melvorData) {
  final items = <Item>[];
  for (final name in melvorData.itemNames) {
    final json = melvorData.lookupItem(name);
    if (json != null) {
      items.add(Item.fromJson(json));
    }
  }
  return items;
}

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'cache',
      abbr: 'c',
      help: 'Cache directory for game assets',
      defaultsTo: path.basename(defaultCacheDir.path),
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message',
    );

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    print('Error: $e\n');
    print('Usage: dart run bin/load_items.dart [options]');
    print(parser.usage);
    exit(1);
  }

  if (args['help'] as bool) {
    print('Load Items - Loads items from Melvor game data as Item objects');
    print('');
    print('Usage: dart run bin/load_items.dart [options]');
    print('');
    print(parser.usage);
    exit(0);
  }

  final cachePath = args['cache'] as String;
  final cacheDir = Directory(path.absolute(cachePath));

  print('Initializing cache at ${cacheDir.path}');

  final cache = Cache(cacheDir: cacheDir);
  try {
    print('Fetching ${Cache.demoDataPath}...');
    final demoData = await cache.ensureDemoData();
    print('Demo data loaded.');

    print('Fetching ${Cache.fullDataPath}...');
    final fullData = await cache.ensureFullData();
    print('Full data loaded.');
    print('');

    // Combine both data files.
    final melvorData = MelvorData([demoData, fullData]);

    // Load all items as Item objects.
    final items = loadItems(melvorData);
    print('Loaded ${items.length} items');
    print('');

    // Group items by itemType for summary.
    final itemsByType = <String, List<Item>>{};
    for (final item in items) {
      itemsByType.putIfAbsent(item.itemType, () => []).add(item);
    }

    print('Items by type:');
    for (final entry in itemsByType.entries) {
      print('  ${entry.key}: ${entry.value.length}');
    }
    print('');

    // Print first few items as examples.
    print('First 10 items:');
    for (final item in items.take(10)) {
      print('  $item');
    }
    print('');

    // Print all food items.
    final foodItems = items.where((item) => item.itemType == 'Food').toList();
    print('Food items (${foodItems.length}):');
    for (final item in foodItems.take(10)) {
      print(
        '  ${item.name}: healsFor=${item.healsFor}, sellsFor=${item.sellsFor}',
      );
    }
    print('');

    // Print openable items with their drop tables.
    final openableItems = items
        .where((item) => item.itemType == 'Openable')
        .toList();
    print('Openable items (${openableItems.length}):');
    for (final item in openableItems.take(5)) {
      print('  ${item.name} (${item.dropTable!.length} drops):');
      for (final drop in item.dropTable!.take(3)) {
        print('    $drop');
      }
      if (item.dropTable!.length > 3) {
        print('    ... and ${item.dropTable!.length - 3} more');
      }
    }
  } finally {
    cache.close();
  }
}
