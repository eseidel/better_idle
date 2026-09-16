// This is a CLI tool that reports progress to stdout.
// ignore_for_file: avoid_print

// Downloads the Melvor data files into .cache before the test suite runs.
//
// `dart test` runs each test file in its own isolate, and every one of them
// calls loadTestRegistries(). On a cold cache that is dozens of concurrent
// fetches of the same two JSON files, which is slow and hammers the CDN for
// no reason. Warming first means exactly one fetch and every suite reading
// from disk.
//
//     dart run tool/warm_cache.dart
import 'dart:io';

import 'package:logic/src/data/registries_io.dart';

Future<void> main(List<String> args) async {
  // Defaults to .cache relative to the current directory, matching
  // defaultCacheDir. Pass a path to warm another package's cache.
  final cacheDir = args.isEmpty ? null : Directory(args.first);
  final stopwatch = Stopwatch()..start();
  final registries = await loadRegistries(cacheDir: cacheDir);
  stopwatch.stop();
  print(
    'Warmed ${cacheDir?.path ?? '.cache'} in '
    '${stopwatch.elapsedMilliseconds}ms '
    '(${registries.allActions.length} actions).',
  );
}
