import 'package:meta/meta.dart';

/// Resolved modifiers from all sources (shop, mastery, equipment, etc.)
///
/// This is a map from modifier name to its resolved value. Values are stored
/// as raw numbers from the data - the caller is responsible for interpreting
/// them correctly (e.g., percentage points vs flat values).
///
/// Common modifier patterns:
/// - `skillInterval`: percentage points (e.g., -5 = 5% faster)
/// - `flatSkillInterval`: flat milliseconds (e.g., -200 = 0.2s faster)
/// - `skillXP`: percentage points for XP gain
@immutable
class ResolvedModifiers {
  const ResolvedModifiers([this._values = const {}]);

  /// Empty resolver result (no modifiers).
  static const empty = ResolvedModifiers();

  final Map<String, num> _values;

  /// Gets the resolved value for a modifier, or 0 if not present.
  num operator [](String name) => _values[name] ?? 0;

  /// Returns true if no modifiers are present.
  bool get isEmpty => _values.isEmpty;

  /// Returns all modifier names that have values.
  Iterable<String> get names => _values.keys;

  /// Creates a new ResolvedModifiers by combining this with another.
  /// Values for the same modifier name are summed.
  ResolvedModifiers combine(ResolvedModifiers other) {
    if (other.isEmpty) return this;
    if (isEmpty) return other;

    final combined = Map<String, num>.from(_values);
    for (final entry in other._values.entries) {
      combined[entry.key] = (combined[entry.key] ?? 0) + entry.value;
    }
    return ResolvedModifiers(combined);
  }

  @override
  String toString() => 'ResolvedModifiers($_values)';
}

/// Builder for accumulating modifier values during resolution.
class ResolvedModifiersBuilder {
  final Map<String, num> _values = {};

  /// Adds a value for a modifier. Values are accumulated (summed).
  void add(String name, num value) {
    _values[name] = (_values[name] ?? 0) + value;
  }

  /// Builds the final immutable ResolvedModifiers.
  ResolvedModifiers build() => ResolvedModifiers(Map.unmodifiable(_values));
}
