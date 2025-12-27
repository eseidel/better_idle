import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Ticks required to regenerate HP (10 seconds = 100 ticks).
final int hpRegenTickInterval = ticksFromDuration(const Duration(seconds: 10));

/// Represents the player's health state.
/// Note: HealthState doesn't know the player's max HP (which depends on
/// Hitpoints skill level). Use GlobalState.playerHp and GlobalState.maxPlayerHp
/// to get the actual current and max HP values.
@immutable
class HealthState {
  const HealthState({required this.lostHp, this.hpRegenTicksRemaining = 0});

  const HealthState.full() : lostHp = 0, hpRegenTicksRemaining = 0;

  static HealthState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return HealthState.fromJson(json as Map<String, dynamic>);
  }

  factory HealthState.fromJson(Map<String, dynamic> json) {
    return HealthState(
      lostHp: json['lostHp'] as int? ?? 0,
      hpRegenTicksRemaining: json['hpRegenTicksRemaining'] as int? ?? 0,
    );
  }

  /// How much HP the player has lost (0 means full health).
  final int lostHp;

  /// Ticks remaining until next HP regen tick (0 means not actively regenerating).
  final int hpRegenTicksRemaining;

  /// Whether the player is at full health.
  bool get isFullHealth => lostHp <= 0;

  /// Returns a new HealthState with HP reduced by the given amount.
  /// Starts the regen timer if not already running.
  HealthState takeDamage(int damage) {
    final newLostHp = lostHp + damage;
    // Start regen timer if we're now injured and timer isn't running
    final newRegenTicks = (newLostHp > 0 && hpRegenTicksRemaining == 0)
        ? hpRegenTickInterval
        : hpRegenTicksRemaining;
    return HealthState(lostHp: newLostHp, hpRegenTicksRemaining: newRegenTicks);
  }

  /// Returns a new HealthState with HP healed by the given amount.
  /// Won't heal beyond full HP (lostHp won't go below 0).
  /// Stops regen timer if fully healed.
  HealthState heal(int amount) {
    final newLostHp = (lostHp - amount).clamp(0, lostHp);
    // Stop regen timer if fully healed
    final newRegenTicks = newLostHp <= 0 ? 0 : hpRegenTicksRemaining;
    return HealthState(lostHp: newLostHp, hpRegenTicksRemaining: newRegenTicks);
  }

  Map<String, dynamic> toJson() {
    return {'lostHp': lostHp, 'hpRegenTicksRemaining': hpRegenTicksRemaining};
  }
}
