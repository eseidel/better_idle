import 'package:logic/file_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui/src/services/cache_services.dart';
import 'package:ui/src/services/image_cache_service.dart';

/// Creates [CacheServices] for native platforms using the file system.
Future<CacheServices> createCacheServices() async {
  final cacheDir = await getApplicationCacheDirectory();
  final cache = FileCache(cacheDir: cacheDir);
  final imageService = ImageCacheService(cache);
  return CacheServices(
    cache: cache,
    wrapChild: (child) =>
        ImageCacheServiceProvider(service: imageService, child: child),
    dispose: imageService.dispose,
  );
}
