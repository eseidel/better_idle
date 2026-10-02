import 'dart:async';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:ui/src/services/game_persist.dart';
import 'package:ui/src/services/logger.dart';

/// UI choices (sort orders and the like) remembered across screens and app
/// restarts.
///
/// These are not game state, so they live outside the save slots and are
/// shared between them.
class UiPreferences {
  UiPreferences({GamePersist? persist})
    : _persist = persist ?? createGamePersist('melvor_ui_preferences');

  final GamePersist _persist;
  Map<String, Object?> _values = {};

  /// Loads saved preferences. Until this completes every getter returns
  /// null, so callers fall back to their defaults.
  Future<void> load() async {
    try {
      final json = await _persist.loadJson();
      if (json is Map<String, dynamic>) _values = Map.of(json);
    } on Object catch (e, stackTrace) {
      logger.err('Failed to load UI preferences: $e\n$stackTrace');
    }
  }

  /// Returns the [values] entry saved under [key], or null if none is saved
  /// (or the saved name no longer matches a value).
  T? getEnum<T extends Enum>(String key, List<T> values) {
    final name = _values[key];
    return name is String ? values.asNameMap()[name] : null;
  }

  /// Saves [value] under [key].
  void setEnum(String key, Enum value) {
    _values[key] = value.name;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await _persist.saveJson(_values);
    } on Object catch (e, stackTrace) {
      logger.err('Failed to save UI preferences: $e\n$stackTrace');
    }
  }
}

final ScopedRef<UiPreferences> uiPreferencesRef = create(UiPreferences.new);
UiPreferences get uiPreferences => read(uiPreferencesRef);
