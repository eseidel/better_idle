import 'package:flutter_test/flutter_test.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:ui/src/services/game_persist.dart';
import 'package:ui/src/services/logger.dart';
import 'package:ui/src/services/ui_preferences.dart';

enum _Sort { first, second }

/// In-memory [GamePersist] standing in for disk or localStorage.
class _FakePersist implements GamePersist {
  Object? saved;

  @override
  Future<Object?> loadJson() async => saved;

  @override
  Future<void> saveJson(Object? json) async => saved = json;

  @override
  Future<void> delete() async => saved = null;
}

void main() {
  test('remembers a choice across instances', () async {
    final persist = _FakePersist();
    UiPreferences(persist: persist).setEnum('sort', _Sort.second);
    await pumpEventQueue();

    final restored = UiPreferences(persist: persist);
    expect(restored.getEnum('sort', _Sort.values), isNull);
    await restored.load();
    expect(restored.getEnum('sort', _Sort.values), _Sort.second);
  });

  test('ignores saved names that are no longer enum values', () async {
    final persist = _FakePersist()..saved = {'sort': 'removed'};
    final preferences = UiPreferences(persist: persist);
    await preferences.load();
    expect(preferences.getEnum('sort', _Sort.values), isNull);
  });

  test('falls back to defaults when the saved data is unreadable', () async {
    final persist = _FakePersist()..saved = 'not a map';
    final preferences = UiPreferences(persist: persist);
    await runScoped(preferences.load, values: {loggerRef});
    expect(preferences.getEnum('sort', _Sort.values), isNull);
  });
}
