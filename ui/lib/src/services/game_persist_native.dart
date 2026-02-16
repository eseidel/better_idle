import 'package:async_redux/local_persist.dart';

/// Creates a platform-specific persist instance for the given [name].
GamePersist createGamePersist(String name) => GamePersist._(name);

/// Native file-system-based persistence using async_redux's LocalPersist.
class GamePersist {
  GamePersist._(String name) : _persist = LocalPersist(name);

  final LocalPersist _persist;

  Future<Object?> loadJson() async => _persist.loadJson();
  Future<void> saveJson(Object? json) async => _persist.saveJson(json);
  Future<void> delete() async => _persist.delete();
}
