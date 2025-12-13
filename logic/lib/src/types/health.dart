import 'package:meta/meta.dart';

/// Maximum player HP.
const int maxPlayerHp = 100;

/// Represents the player's health state.
@immutable
class HealthState {
  const HealthState({required this.lostHp});

  const HealthState.full() : lostHp = 0;

  factory HealthState.fromJson(Map<String, dynamic> json) {
    // Support reading old 'playerHp' format for backwards compatibility
    if (json.containsKey('lostHp')) {
      return HealthState(lostHp: json['lostHp'] as int);
    }
    // Legacy format: convert playerHp to lostHp
    final playerHp = json['playerHp'] as int? ?? maxPlayerHp;
    return HealthState(lostHp: maxPlayerHp - playerHp);
  }

  /// How much HP the player has lost (0 means full health).
  final int lostHp;

  /// Current HP of the player (derived from lostHp).
  int get currentHp => (maxPlayerHp - lostHp).clamp(0, maxPlayerHp);

  /// Whether the player is at full health.
  bool get isFullHealth => lostHp <= 0;

  /// Whether the player is dead.
  bool get isDead => currentHp <= 0;

  /// Returns a new HealthState with HP reduced by the given amount.
  HealthState takeDamage(int damage) {
    return HealthState(lostHp: lostHp + damage);
  }

  /// Returns a new HealthState with HP healed by the given amount.
  /// Won't heal beyond max HP (lostHp won't go below 0).
  HealthState heal(int amount) {
    return HealthState(lostHp: (lostHp - amount).clamp(0, maxPlayerHp));
  }

  /// Resets to full health.
  HealthState reset() => const HealthState.full();

  HealthState copyWith({int? lostHp}) {
    return HealthState(lostHp: lostHp ?? this.lostHp);
  }

  Map<String, dynamic> toJson() {
    return {'lostHp': lostHp};
  }
}
