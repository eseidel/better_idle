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
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show detailed item information',
    );

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    print('Error: $e\n');
    print('Usage: dart run bin/map_items.dart [options]');
    print(parser.usage);
    exit(1);
  }

  if (args['help'] as bool) {
    print('Map Items - Maps our items to Melvor game data');
    print('');
    print('Usage: dart run bin/map_items.dart [options]');
    print('');
    print(parser.usage);
    exit(0);
  }

  final cachePath = args['cache'] as String;
  final verbose = args['verbose'] as bool;
  final cacheDir = Directory(path.absolute(cachePath));

  print('Loading Melvor game data...');

  final cache = Cache(cacheDir: cacheDir);
  try {
    // Load both demo (base game) and full (expansion) data.
    final demoData = await cache.ensureDemoData();
    final fullData = await cache.ensureFullData();
    final melvorData = MelvorData([demoData, fullData]);

    print('Loaded ${melvorData.itemCount} items from Melvor data.');
    print('');

    // Check each item in our registry by name.
    final found = <String>[];
    final notFound = <String>[];

    for (final item in itemRegistry.all) {
      final name = item.name;
      final melvorItem = melvorData.lookupItem(name);

      if (melvorItem != null) {
        found.add(name);
        if (verbose) {
          final sellsFor = melvorItem['sellsFor'] as int?;
          print('✓ $name (sells for: $sellsFor GP)');
        }
      } else {
        notFound.add(name);
      }
    }

    // Print summary.
    print('=== Summary ===');
    print('Total items in our registry: ${itemRegistry.all.length}');
    print('Found in Melvor data: ${found.length}');
    print('Not found in Melvor data: ${notFound.length}');
    print('');

    if (notFound.isNotEmpty) {
      print('Items not found in Melvor data:');
      for (final name in notFound) {
        print('  - $name');
      }
      print('');

      // Search for similar names.
      if (verbose) {
        print('Searching for similar names in Melvor data:');
        for (final name in notFound.take(5)) {
          final searchTerm = name.split(' ').first.toLowerCase();
          final matches = melvorData.itemNames
              .where((n) => n.toLowerCase().contains(searchTerm))
              .take(3);
          if (matches.isNotEmpty) {
            print('  "$name" -> possible matches: ${matches.join(', ')}');
          }
        }
      }
    }

    if (found.length == itemRegistry.all.length) {
      print('All items found in Melvor data!');
    }
  } finally {
    cache.close();
  }
}
