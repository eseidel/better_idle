import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logic/logic.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// Service for caching and loading item images from the Melvor CDN.
class ImageCacheService {
  Cache? _cache;
  final Map<String, Future<File?>> _pendingFetches = {};

  /// Initializes the cache with the app's document directory.
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/melvor_cache');
    _cache = Cache(cacheDir: cacheDir);
  }

  /// Returns the cached file for an asset path, or null if not yet cached.
  ///
  /// If the asset is not cached, starts a background fetch and returns null.
  /// Call this method again after the fetch completes to get the file.
  File? getCachedFile(String assetPath) {
    if (_cache == null) return null;

    final file = File('${_cache!.cacheDir.path}/$assetPath');
    if (file.existsSync()) {
      return file;
    }

    // Start background fetch if not already pending.
    if (!_pendingFetches.containsKey(assetPath)) {
      _pendingFetches[assetPath] = _fetchAsset(assetPath);
    }

    return null;
  }

  /// Fetches an asset and returns the cached file.
  Future<File?> _fetchAsset(String assetPath) async {
    try {
      final file = await _cache!.ensureAsset(assetPath);
      unawaited(_pendingFetches.remove(assetPath));
      return file;
    } on CacheException catch (e) {
      debugPrint('Failed to fetch asset $assetPath: $e');
      unawaited(_pendingFetches.remove(assetPath));
      return null;
    }
  }

  /// Returns a Future that completes when an asset is fetched.
  ///
  /// Returns the cached file, or null if fetch fails.
  Future<File?> ensureAsset(String assetPath) async {
    if (_cache == null) {
      await initialize();
    }

    // Check if already cached.
    final file = File('${_cache!.cacheDir.path}/$assetPath');
    if (file.existsSync()) {
      return file;
    }

    // Check if fetch is already pending.
    if (_pendingFetches.containsKey(assetPath)) {
      return _pendingFetches[assetPath];
    }

    // Start fetch.
    final future = _fetchAsset(assetPath);
    _pendingFetches[assetPath] = future;
    return future;
  }

  /// Disposes of the cache resources.
  void dispose() {
    _cache?.close();
    _cache = null;
    _pendingFetches.clear();
  }
}

final ScopedRef<ImageCacheService> imageCacheServiceRef = create(
  ImageCacheService.new,
);

ImageCacheService get imageCacheService => read(imageCacheServiceRef);
