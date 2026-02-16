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
