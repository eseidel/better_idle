import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logic/src/data/cache.dart';
import 'package:path/path.dart' as path;

export 'package:logic/src/data/cache.dart';

final defaultCacheDir = Directory('.cache');

/// Native file-system-based implementation of [Cache].
///
/// Fetches game data from the Melvor CDN and caches it on disk.
class FileCache implements Cache {
  /// Creates a new cache instance.
  ///
  /// The [cacheDir] is where cached files will be stored.
  /// An optional [client] can be provided for testing.
  FileCache({required this.cacheDir, http.Client? client})
    : _client = client ?? http.Client();

  /// The directory where cached files are stored.
  final Directory cacheDir;

  final http.Client _client;

  /// Ensures a data file is cached and returns its parsed content.
  Future<Map<String, dynamic>> _ensureDataFile(String dataPath) async {
    final file = await ensureAsset(dataPath);
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> ensureDemoData() async {
    return _ensureDataFile(demoDataPath);
  }

  @override
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

  @override
  void close() {
    _client.close();
  }
}
