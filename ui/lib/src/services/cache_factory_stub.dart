import 'package:logic/web_cache.dart';
import 'package:ui/src/services/cache_services.dart';

/// Creates [CacheServices] for web platforms.
Future<CacheServices> createCacheServices() async {
  final cache = WebCache();
  return CacheServices(
    cache: cache,
    wrapChild: (child) => child,
    dispose: cache.close,
  );
}
