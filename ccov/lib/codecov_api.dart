import 'dart:convert';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://api.codecov.io/api/v2';
const _owner = 'eseidel';
const _repo = 'better_idle';
const _service = 'github';

/// Codecov API client for the better_idle repo.
class CodecovApi {
  final _client = http.Client();

  String get _repoBase => '$_baseUrl/$_service/$_owner/repos/$_repo';

  Future<Map<String, dynamic>> fetchSummary() async {
    final response = await _client.get(Uri.parse('$_repoBase/'));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch summary: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchReport() async {
    final response = await _client.get(Uri.parse('$_repoBase/report/'));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch report: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() => _client.close();
}
