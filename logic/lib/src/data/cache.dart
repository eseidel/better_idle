import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

final defaultCacheDir = Directory('.cache');

/// Fetches and caches game data from the Melvor CDN.
class Cache {
  /// Creates a new cache instance.
  ///
  /// The [cacheDir] is where cached files will be stored.
  /// An optional [client] can be provided for testing.
  Cache({required this.cacheDir, http.Client? client})
    : _client = client ?? http.Client();

  /// The base URL for the Melvor CDN.
  static const String cdnBase = 'https://cdn2-main.melvor.net';

  /// The path to the demo game data file (base game items).
  static const String demoDataPath = 'assets/data/melvorDemo.json';

  /// The path to the full game data file (expansion items).
  static const String fullDataPath = 'assets/data/melvorFull.json';

  /// The directory where cached files are stored.
  final Directory cacheDir;

  final http.Client _client;

  /// Ensures a data file is cached and returns its parsed content.
  Future<Map<String, dynamic>> _ensureDataFile(String dataPath) async {
    final file = await ensureAsset(dataPath);
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Ensures the demo game data file is cached and returns its parsed content.
  Future<Map<String, dynamic>> ensureDemoData() async {
    return _ensureDataFile(demoDataPath);
  }

  /// Ensures the full game data file is cached and returns its parsed content.
  Future<Map<String, dynamic>> ensureFullData() async {
    return _ensureDataFile(fullDataPath);
  }

  /// Ensures an asset is cached and returns the cached file.
  ///
  /// The [assetPath] should be relative to the CDN base URL,
  /// e.g., 'assets/data/melvorFull.json' or 'assets/media/skills/woodcutting.png'.
  ///
  /// If the file is already cached, returns immediately.
  /// Otherwise, fetches from the CDN and caches it.
  Future<File> ensureAsset(String assetPath) async {
    final cacheFile = File(path.join(cacheDir.path, assetPath));

    // Check cache first.
    if (cacheFile.existsSync()) {
      return cacheFile;
    }

    // Fetch from CDN.
    final url = Uri.parse('$cdnBase/$assetPath');
    final response = await _client.get(url);

    if (response.statusCode != 200) {
      throw CacheException(
        'Failed to fetch $assetPath: HTTP ${response.statusCode}',
      );
    }

    // Cache the response.
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsBytes(response.bodyBytes);

    return cacheFile;
  }

  /// Closes the HTTP client.
  void close() {
    _client.close();
  }
}

/// Exception thrown when a cache operation fails.
class CacheException implements Exception {
  CacheException(this.message);
  final String message;

  @override
  String toString() => 'CacheException: $message';
}
