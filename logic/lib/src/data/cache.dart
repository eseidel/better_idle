import 'package:http/http.dart' as http;

/// The base URL for the Melvor CDN.
const String cdnBase = 'https://cdn2-main.melvor.net';

/// The path to the demo game data file (base game items).
const String demoDataPath = 'assets/data/melvorDemo.json';

/// The path to the full game data file (expansion items).
const String fullDataPath = 'assets/data/melvorFull.json';

/// Abstract interface for fetching and caching game data from the Melvor CDN.
abstract class Cache {
  /// Ensures the demo game data file is available and returns its parsed
  /// content.
  Future<Map<String, dynamic>> ensureDemoData();

  /// Ensures the full game data file is available and returns its parsed
  /// content.
  Future<Map<String, dynamic>> ensureFullData();

  /// Closes the HTTP client.
  void close();
}

/// Exception thrown when a cache operation fails.
class CacheException implements Exception {
  CacheException(this.message);
  final String message;

  @override
  String toString() => 'CacheException: $message';
}

/// Creates an HTTP client for use by cache implementations.
http.Client createCacheClient() => http.Client();
