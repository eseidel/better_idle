import 'dart:io';

import 'package:logic/src/data/file_cache.dart';
import 'package:logic/src/data/registries.dart';

/// Ensures the registries are initialized using the native file-system cache.
///
/// This should be called during app startup or in setUpAll() for tests.
/// It's safe to call multiple times; subsequent calls are no-ops.
Future<Registries> loadRegistries({Directory? cacheDir}) async {
  final cache = FileCache(cacheDir: cacheDir ?? defaultCacheDir);
  try {
    return await loadRegistriesFromCache(cache);
  } finally {
    cache.close();
  }
}

/// Loads the registries from the on-disk cache, never touching the network.
///
/// This is what tests use: it throws if the cache is cold rather than
/// downloading, so parallel suites cannot race each other over the network.
/// Populate the cache first with `dart run tool/warm_cache.dart`.
Future<Registries> loadCachedRegistries({Directory? cacheDir}) async {
  final cache = FileCache.offline(cacheDir: cacheDir ?? defaultCacheDir);
  try {
    return await loadRegistriesFromCache(cache);
  } finally {
    cache.close();
  }
}
