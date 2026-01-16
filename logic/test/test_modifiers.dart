/// Test-specific shim for ResolvedModifiers.
///
/// This provides backward compatibility for tests that were written against
/// the old ResolvedModifiers API. New tests should use ModifierProvider
/// directly via state.createModifierProvider().
library;

import 'package:logic/logic.dart';

/// A simple wrapper that implements the old ResolvedModifiers-like interface
/// for tests that need to pass explicit modifier values.
///
/// Usage:
/// ```dart
/// final modifiers = TestModifiers({'skillXP': 20, 'skillInterval': -5});
/// final xp = xpPerAction(state, action, modifiers);
/// ```
class TestModifiers with ModifierAccessors {
  const TestModifiers([this._values = const {}]);

  /// Creates an empty modifier set (all values return 0).
  static const empty = TestModifiers();

  final Map<String, num> _values;

  bool get isEmpty => _values.isEmpty;

  @override
  num getModifier(
    String name, {
    MelvorId? skillId,
    MelvorId? actionId,
    MelvorId? itemId,
    MelvorId? categoryId,
  }) {
    return _values[name] ?? 0;
  }
}
