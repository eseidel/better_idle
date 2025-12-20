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
    print('Usage: dart run bin/list_items.dart [options]');
    print(parser.usage);
    exit(1);
  }

  if (args['help'] as bool) {
    print('List Items - Fetches and caches Melvor game data');
    print('');
    print('Usage: dart run bin/list_items.dart [options]');
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
    print('Total items: ${melvorData.itemCount}');
  } finally {
    cache.close();
  }
}
