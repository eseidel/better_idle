import 'dart:convert';

import 'package:ccov/codecov_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CodecovApi', () {
    late List<Uri> requested;

    CodecovApi apiReturning(Object body, {int status = 200}) {
      requested = [];
      return CodecovApi(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response(jsonEncode(body), status);
        }),
      );
    }

    test('fetchSummary requests the repo endpoint and decodes the body', () {
      final api = apiReturning({'name': 'better_idle'});
      expect(api.fetchSummary(), completion({'name': 'better_idle'}));
    });

    test('fetchReport requests the report endpoint', () async {
      final api = apiReturning({'totals': <String, dynamic>{}});
      await api.fetchReport();
      expect(
        requested.single.toString(),
        'https://api.codecov.io/api/v2/github/eseidel/repos/better_idle/report/',
      );
    });

    test('fetchSummary throws on a non-200 response', () {
      final api = apiReturning(<String, dynamic>{}, status: 404);
      expect(api.fetchSummary(), throwsA(isA<Exception>()));
    });

    test('fetchReport throws on a non-200 response', () {
      final api = apiReturning(<String, dynamic>{}, status: 500);
      expect(api.fetchReport(), throwsA(isA<Exception>()));
    });
  });
}
