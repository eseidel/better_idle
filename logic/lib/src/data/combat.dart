import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:meta/meta.dart';

/// Combat stats for a player or monster.
@immutable
class Stats {
  const Stats({
    required this.minHit,
    required this.maxHit,
    required this.damageReduction,
    required this.attackSpeed,
  });

  /// Minimum damage dealt per attack.
  final int minHit;

  /// Maximum damage dealt per attack.
  final int maxHit;

  /// Percentage of damage reduced (0.0 to 1.0).
  final double damageReduction;

  /// Seconds between attacks.
  final double attackSpeed;

  /// Roll a random damage value between minHit and maxHit (inclusive).
  int rollDamage(Random random) {
    if (minHit == maxHit) return minHit;
    return minHit + random.nextInt((maxHit - minHit) + 1);
  }
}

/// A combat action for fighting a specific monster.
/// Unlike skill actions, combat doesn't complete after a duration - attacks
/// happen on timers and the action continues until stopped or player dies.
@immutable
class CombatAction extends Action {
  const CombatAction({
    required super.name,
    required this.combatLevel,
    required this.maxHp,
    required this.stats,
    required this.minGpDrop,
    required this.maxGpDrop,
  }) : super(skill: Skill.attack);

  final int combatLevel;
  final int maxHp;
  final Stats stats;
  final int minGpDrop;
  final int maxGpDrop;

  /// Roll a random GP drop between minGpDrop and maxGpDrop (inclusive).
  int rollGpDrop(Random random) {
    if (minGpDrop == maxGpDrop) return minGpDrop;
    return minGpDrop + random.nextInt((maxGpDrop - minGpDrop) + 1);
  }
}

const combatActions = <CombatAction>[
  CombatAction(
    name: 'Plant',
    combatLevel: 1,
    maxHp: 20,
    stats: Stats(minHit: 0, maxHit: 11, damageReduction: 0, attackSpeed: 2.4),
    minGpDrop: 1,
    maxGpDrop: 5,
  ),
];

/// Look up a CombatAction by name.
CombatAction combatActionByName(String name) {
  return combatActions.firstWhere((action) => action.name == name);
}
