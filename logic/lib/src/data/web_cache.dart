import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logic/src/data/cache.dart';

export 'package:logic/src/data/cache.dart';

/// Web implementation of [Cache].
///
/// Fetches game data from the Melvor CDN over HTTP without file-system caching.
/// The browser's built-in HTTP cache handles repeat requests.
class WebCache implements Cache {
  WebCache({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> _fetchData(String dataPath) async {
    final url = Uri.parse('$cdnBase/$dataPath');
    final response = await _client.get(url);
    if (response.statusCode != 200) {
      throw CacheException(
        'Failed to fetch $dataPath: HTTP ${response.statusCode}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> ensureDemoData() => _fetchData(demoDataPath);

  @override
  Future<Map<String, dynamic>> ensureFullData() => _fetchData(fullDataPath);

  @override
  void close() => _client.close();
}
