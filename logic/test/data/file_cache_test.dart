import 'dart:convert';
import 'dart:io';

import 'package:logic/src/data/file_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('cache_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  group('FileCache offline', () {
    test('throws a message naming the fix when the cache is cold', () async {
      final cache = FileCache.offline(cacheDir: tempDir);
      addTearDown(cache.close);

      await expectLater(
        cache.ensureFullData(),
        throwsA(
          isA<CacheException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Asset cache is cold'),
              contains('dart run tool/warm_cache.dart'),
            ),
          ),
        ),
      );
    });

    test(
      'serves an already-cached asset without touching the network',
      () async {
        final file = File('${tempDir.path}/$fullDataPath')
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'data': <String, dynamic>{}}));
        expect(file.existsSync(), isTrue);

        final cache = FileCache.offline(cacheDir: tempDir);
        addTearDown(cache.close);

        // No client is provided, so any fetch attempt would fail rather than
        // silently succeed.
        expect(await cache.ensureFullData(), {'data': <String, dynamic>{}});
      },
    );
  });
}
