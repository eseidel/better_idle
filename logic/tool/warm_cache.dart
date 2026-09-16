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
import 'package:logic/src/data/registries_io.dart';

Future<void> main() async {
  final stopwatch = Stopwatch()..start();
  final registries = await loadRegistries();
  stopwatch.stop();
  print(
    'Warmed cache in ${stopwatch.elapsedMilliseconds}ms '
    '(${registries.allActions.length} actions).',
  );
}
