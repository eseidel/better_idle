/// Helpers for loading game data in tests.
///
/// This deliberately does not export `loadRegistries`. Tests must never
/// download game data - `dart test` runs every suite in its own isolate, so
/// fetching means dozens of concurrent downloads racing each other, and a lost
/// race silently drops a whole file's tests. Keeping the fetching loader out
/// of scope means a test cannot reach the network by mistake.
///
/// Populate the cache first with `dart run tool/warm_cache.dart`.
library;

export 'src/data/registries_io.dart' show loadCachedRegistries;
