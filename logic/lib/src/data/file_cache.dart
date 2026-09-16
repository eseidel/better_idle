import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:logic/src/data/cache.dart';
import 'package:path/path.dart' as path;

export 'package:logic/src/data/cache.dart';

final defaultCacheDir = Directory('.cache');

/// Returns a suffix unique to this writer, so parallel test suites racing to
/// populate the same cache entry never share a temp file.
String _tempSuffix() =>
    '$pid-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

final _random = Random();

/// Native file-system-based implementation of [Cache].
///
/// Fetches game data from the Melvor CDN and caches it on disk.
class FileCache implements Cache {
  /// Creates a cache that fetches missing assets from the CDN.
  ///
  /// The [cacheDir] is where cached files will be stored.
  /// An optional [client] can be provided for testing.
  FileCache({required this.cacheDir, http.Client? client})
    : _client = client ?? http.Client(),
      _offline = false;

  /// Creates a cache that serves only what is already on disk, throwing if an
  /// asset is missing.
  ///
  /// Tests use this. `dart test` runs every suite in its own isolate and each
  /// one loads the registries, so letting tests fetch means dozens of
  /// concurrent downloads racing each other: a run either passes, or loses a
  /// whole file's tests to a dropped connection while still reporting a
  /// mostly-green summary. Refusing outright turns "sometimes broken" into a
  /// single deterministic error that names the fix.
  ///
  /// This is a separate constructor rather than a flag so that callers cannot
  /// reach the network by forgetting an argument.
  FileCache.offline({required this.cacheDir})
    : _client = http.Client(),
      _offline = true;

  /// The directory where cached files are stored.
  final Directory cacheDir;

  final bool _offline;

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

  /// Fetches [url], retrying transient network failures with backoff.
  ///
  /// `dart test` runs suites in parallel and each one populates the cache on
  /// a cold start, so a single run can open dozens of concurrent connections
  /// for the same files. Without a retry a reset connection fails that
  /// suite's setUpAll, which silently drops every test in the file.
  Future<http.Response> _fetchWithRetry(Uri url, String assetPath) async {
    const maxAttempts = 4;
    var delay = const Duration(milliseconds: 250);

    for (var attempt = 1; ; attempt++) {
      final lastAttempt = attempt == maxAttempts;
      try {
        final response = await _client.get(url);
        if (response.statusCode == 200) return response;
        // 4xx will not change on a retry; only 5xx is worth repeating.
        if (lastAttempt || response.statusCode < 500) {
          throw CacheException(
            'Failed to fetch $assetPath: HTTP ${response.statusCode}',
          );
        }
      } on IOException {
        if (lastAttempt) rethrow;
      } on http.ClientException {
        if (lastAttempt) rethrow;
      }

      await Future<void>.delayed(delay);
      delay *= 2;
    }
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

    if (_offline) {
      throw CacheException(
        'Asset cache is cold: ${cacheFile.path} is missing.\n'
        'Tests never download game data, so they cannot flake on the '
        'network.\nPopulate the cache first:\n\n'
        '    dart run tool/warm_cache.dart\n',
      );
    }

    // Fetch from CDN.
    final url = Uri.parse('$cdnBase/$assetPath');
    final response = await _fetchWithRetry(url, assetPath);

    // Cache the response by writing to a unique temp file and renaming it
    // into place. `dart test` runs suites in parallel, and each one populates
    // the cache on a cold start; a plain write is not atomic, so a concurrent
    // reader can see the file exist (above) while it is still partially
    // written and fail to parse it. rename(2) is atomic, so readers see
    // either no file or a complete one.
    await cacheFile.parent.create(recursive: true);
    final temp = File('${cacheFile.path}.${_tempSuffix()}');
    try {
      await temp.writeAsBytes(response.bodyBytes);
      await temp.rename(cacheFile.path);
    } on Object {
      if (temp.existsSync()) temp.deleteSync();
      rethrow;
    }

    return cacheFile;
  }

  @override
  void close() {
    _client.close();
  }
}
