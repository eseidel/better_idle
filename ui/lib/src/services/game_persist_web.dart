import 'dart:convert';

import 'package:web/web.dart' as web;

/// Creates a platform-specific persist instance for the given [name].
GamePersist createGamePersist(String name) => GamePersist._(name);

/// Web persistence using localStorage.
class GamePersist {
  GamePersist._(this._name);

  final String _name;

  String get _key => 'game_persist_$_name';

  Future<Object?> loadJson() async {
    final value = web.window.localStorage.getItem(_key);
    if (value == null) return null;
    return jsonDecode(value);
  }

  Future<void> saveJson(Object? json) async {
    web.window.localStorage.setItem(_key, jsonEncode(json));
  }

  Future<void> delete() async {
    web.window.localStorage.removeItem(_key);
  }
}
