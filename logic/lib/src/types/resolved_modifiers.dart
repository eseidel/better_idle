import 'package:logic/src/types/modifier_old.dart';
import 'package:meta/meta.dart';

/// Resolved skill interval modifiers from mastery bonuses.
///
/// Contains both flat (milliseconds) and percentage modifiers that affect
/// action duration. Use [toModifierOld] to convert to the legacy format
/// for application in [GlobalState.rollDurationWithModifiers].
@immutable
class ResolvedModifiers {
  const ResolvedModifiers({
    this.flatSkillIntervalMs = 0,
    this.skillIntervalPercent = 0.0,
  });

  /// Empty resolver result (no modifiers).
  static const empty = ResolvedModifiers();

  /// Flat skill interval modifier in milliseconds.
  /// Negative values reduce duration (e.g., -200 = 0.2s faster).
  final int flatSkillIntervalMs;

  /// Percentage skill interval modifier as a decimal.
  /// Negative values reduce duration (e.g., -0.05 = 5% faster).
  final double skillIntervalPercent;

  /// True if no modifiers are present.
  bool get isEmpty => flatSkillIntervalMs == 0 && skillIntervalPercent == 0.0;

  /// Converts to [ModifierOld] for use in duration calculations.
  /// Flat milliseconds are converted to ticks (100ms = 1 tick).
  ModifierOld toModifierOld() {
    final flatTicks = flatSkillIntervalMs / 100.0;
    return ModifierOld(percent: skillIntervalPercent, flat: flatTicks);
  }
}
