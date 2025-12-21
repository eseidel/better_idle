import 'dart:io';

import 'package:args/args.dart';
import 'package:logic/logic.dart';
import 'package:path/path.dart' as path;

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

  print('Loading Melvor data from ${cacheDir.path}...');

  final melvorData = await MelvorData.load(cacheDir: cacheDir);
  initializeItems(melvorData);

  print('Loaded ${itemRegistry.all.length} items');
  print('');

  // Group items by itemType for summary.
  final itemsByType = <String, List<Item>>{};
  for (final item in itemRegistry.all) {
    itemsByType.putIfAbsent(item.itemType, () => []).add(item);
  }

  print('Items by type:');
  for (final entry in itemsByType.entries) {
    print('  ${entry.key}: ${entry.value.length}');
  }
  print('');

  // Print first few items as examples.
  print('First 10 items:');
  for (final item in itemRegistry.all.take(10)) {
    print('  $item');
  }
  print('');

  // Print all food items.
  final foodItems = itemRegistry.all
      .where((item) => item.itemType == 'Food')
      .toList();
  print('Food items (${foodItems.length}):');
  for (final item in foodItems.take(10)) {
    print(
      '  ${item.name}: healsFor=${item.healsFor}, sellsFor=${item.sellsFor}',
    );
  }
  print('');

  // Print openable items with their drop tables.
  final openableItems = itemRegistry.all.whereType<Openable>().toList();
  print('Openable items (${openableItems.length}):');
  for (final item in openableItems.take(5)) {
    print('  ${item.name} (${item.dropTable.entries.length} drops):');
    for (final drop in item.dropTable.entries.take(3)) {
      print(
        '    ${drop.name}: ${drop.minCount}-${drop.maxCount}, weight: ${drop.weight}',
      );
    }
    if (item.dropTable.entries.length > 3) {
      print('    ... and ${item.dropTable.entries.length - 3} more');
    }
  }
}
