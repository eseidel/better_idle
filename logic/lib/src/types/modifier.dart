import 'package:meta/meta.dart';

/// A modifier that can adjust a value with both percentage and flat adjustments.
/// Percentage adjustments are applied first, then flat adjustments.
@immutable
class Modifier {
  const Modifier({this.percent = 0.0, this.flat = 0.0});

  /// Percentage modifier as a decimal (e.g., -0.05 = 5% reduction).
  final double percent;

  /// Flat modifier in the same units as the value being modified.
  /// For duration modifiers, this is in ticks.
  final double flat;

  /// Returns true if this modifier has no effect.
  bool get isEmpty => percent == 0.0 && flat == 0.0;

  /// Combines this modifier with another by adding their components.
  Modifier combine(Modifier other) {
    return Modifier(percent: percent + other.percent, flat: flat + other.flat);
  }

  /// Combines multiple modifiers into a single modifier.
  static Modifier combineAll(Iterable<Modifier> modifiers) {
    var result = const Modifier();
    for (final modifier in modifiers) {
      result = result.combine(modifier);
    }
    return result;
  }

  /// Applies this modifier to an integer value.
  /// First applies percentage adjustment, then flat adjustment.
  /// Result is rounded and clamped to at least 1.
  // TODO(eseidel): Require a specified clamp range.
  int applyToInt(int value) {
    // Apply percentage first
    var result = value * (1.0 + percent);
    // Then apply flat
    result += flat;
    // Round and ensure minimum of 1
    return result.round().clamp(1, double.maxFinite.toInt());
  }
}
