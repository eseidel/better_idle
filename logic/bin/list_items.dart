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
    print('Fetching ${Cache.mainDataPath}...');
    final data = await cache.ensureMainData();
    print('Main data loaded successfully.');
    print('');

    // Print some basic info about the data.
    final namespace = data['namespace'] as String?;
    final namespaceInfo = namespace != null ? ' (namespace: $namespace)' : '';
    print('Game data$namespaceInfo');

    if (data['data'] case final Map<String, dynamic> gameData) {
      for (final key in gameData.keys.take(10)) {
        final value = gameData[key];
        if (value is List) {
          print('  $key: ${value.length} entries');
        }
      }
      if (gameData.keys.length > 10) {
        print('  ... and ${gameData.keys.length - 10} more categories');
      }
    }
  } finally {
    cache.close();
  }
}
