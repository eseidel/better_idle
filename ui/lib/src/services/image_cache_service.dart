import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logic/file_cache.dart';

/// Service for caching and loading item images from the Melvor CDN.
class ImageCacheService {
  ImageCacheService(this._cache);

  final FileCache _cache;
  final Map<String, Future<File?>> _pendingFetches = {};

  /// Returns the cached file for an asset path, or null if not yet cached.
  ///
  /// If the asset is not cached, starts a background fetch and returns null.
  /// Call this method again after the fetch completes to get the file.
  File? getCachedFile(String assetPath) {
    final file = File('${_cache.cacheDir.path}/$assetPath');
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
      final file = await _cache.ensureAsset(assetPath);
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
    // Check if already cached.
    final file = File('${_cache.cacheDir.path}/$assetPath');
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
    _cache.close();
    _pendingFetches.clear();
  }
}

/// InheritedWidget that provides [ImageCacheService] to the widget tree.
class ImageCacheServiceProvider extends InheritedWidget {
  const ImageCacheServiceProvider({
    required this.service,
    required super.child,
    super.key,
  });

  final ImageCacheService service;

  @override
  bool updateShouldNotify(ImageCacheServiceProvider oldWidget) {
    return service != oldWidget.service;
  }

  static ImageCacheService of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<ImageCacheServiceProvider>();
    assert(provider != null, 'No ImageCacheServiceProvider found in context');
    return provider!.service;
  }
}

/// Extension to access [ImageCacheService] from [BuildContext].
extension ImageCacheServiceContext on BuildContext {
  ImageCacheService get imageCacheService {
    return ImageCacheServiceProvider.of(this);
  }
}
