import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/types/modifier_names.dart';
import 'package:meta/meta.dart';

/// Equipment bonuses aggregated from all equipped gear.
///
/// This represents the sum of all combat-relevant modifiers from equipment.
/// Values use the same units as the Melvor modifier system.
@immutable
class EquipmentBonuses extends ModifiersBase {
  const EquipmentBonuses(super.values);

  /// Calculates equipment bonuses by summing modifiers from all equipped gear.
  factory EquipmentBonuses.fromEquipment(GlobalState state) {
    final values = <String, num>{};

    void addModifier(String name, num value) {
      values[name] = (values[name] ?? 0) + value;
    }

    // Sum modifiers from all equipped gear
    for (final item in state.equipment.gearSlots.values) {
      for (final mod in item.modifiers.modifiers) {
        for (final entry in mod.entries) {
          // For combat stats, we include all entries regardless of scope
          // since equipment modifiers typically don't have skill scopes
          addModifier(mod.name, entry.value);
        }
      }
    }

    return EquipmentBonuses(values);
  }

  /// Empty equipment bonuses (no gear equipped).
  static const empty = EquipmentBonuses({});
}

/// Computed player combat stats based on skill levels and equipment.
///
/// Uses Melvor-style formulas to calculate max hit, accuracy, evasion, etc.
@immutable
class PlayerCombatStats extends Stats {
  const PlayerCombatStats._({
    required super.minHit,
    required super.maxHit,
    required super.damageReduction,
    required super.attackSpeed,
    required this.accuracy,
    required this.meleeEvasion,
    required this.rangedEvasion,
    required this.magicEvasion,
  });

  /// Computes player stats from current game state.
  factory PlayerCombatStats.fromState(GlobalState state) {
    final bonuses = EquipmentBonuses.fromEquipment(state);

    // Get skill levels
    final attackLevel = state.skillState(Skill.attack).skillLevel;
    final strengthLevel = state.skillState(Skill.strength).skillLevel;
    final defenceLevel = state.skillState(Skill.defence).skillLevel;

    // --- Max Hit Calculation ---
    // Melvor formula:
    // floor(M * (2.2 + EffectiveLevel/10 + (EffectiveLevel+17)*StrBonus/640))
    // M = 10 for normal attacks
    // For simplicity, we use effective strength level = strength level
    // (In full Melvor, attack styles add +3 to effective level)
    final effectiveStrength = strengthLevel;
    final strengthBonus = bonuses.flatMeleeStrengthBonus.toInt();

    var maxHit =
        (10 *
                (2.2 +
                    effectiveStrength / 10 +
                    (effectiveStrength + 17) * strengthBonus / 640))
            .floor();

    // Apply percentage max hit modifiers
    final maxHitPercent = bonuses.maxHit + bonuses.meleeMaxHit;
    maxHit = (maxHit * (1 + maxHitPercent / 100)).floor();

    // Apply flat max hit modifiers
    maxHit += bonuses.flatMaxHit.toInt();

    // Clamp to reasonable bounds
    maxHit = maxHit.clamp(1, 99999);

    // --- Min Hit Calculation ---
    // Start at 1, apply flat modifiers
    var minHit = 1 + bonuses.flatMinHit.toInt();

    // minHitBasedOnMaxHit is a percentage of max hit added to min hit
    final minHitPercent = bonuses.minHitBasedOnMaxHit;
    if (minHitPercent > 0) {
      minHit += (maxHit * minHitPercent / 100).floor();
    }
    minHit = minHit.clamp(1, maxHit);

    // --- Attack Speed ---
    // Base attack speed is 4 seconds for unarmed
    // Equipment can modify this via attackInterval (percentage) and
    // flatAttackInterval (milliseconds)
    var attackSpeedMs = 4000.0;

    // Apply percentage modifier first
    final intervalPercent = bonuses.attackInterval;
    attackSpeedMs *= 1 + intervalPercent / 100;

    // Apply flat modifier (in milliseconds)
    attackSpeedMs += bonuses.flatAttackInterval.toDouble();

    // Convert to seconds, clamp to reasonable bounds
    final attackSpeed = (attackSpeedMs / 1000).clamp(2.0, 10.0);

    // --- Damage Reduction ---
    // In Melvor, this comes from the "resistance" modifier
    // Each point = 1% damage reduction, capped at 95%
    final resistance = bonuses.resistance + bonuses.flatResistance;
    final damageReduction = (resistance / 100).clamp(0.0, 0.95);

    // --- Accuracy Rating ---
    // Formula: floor((EffectiveLevel + 9) * (BaseAccuracyBonus + 64) * (1 + Mod/100))
    final effectiveAttack = attackLevel;
    // Equipment accuracy bonuses (stab, slash, block attacks)
    // For simplicity, we sum all attack bonuses
    final baseAccuracyBonus =
        bonuses.flatStabAttackBonus +
        bonuses.flatSlashAttackBonus +
        bonuses.flatBlockAttackBonus;
    final accuracyModifier = bonuses.meleeAccuracyRating;

    final accuracy =
        ((effectiveAttack + 9) *
                (baseAccuracyBonus + 64) *
                (1 + accuracyModifier / 100))
            .floor();

    // --- Evasion Ratings ---
    // Melee evasion: floor((EffDefence + 9) * (DefenceBonus + 64) * (1 + Mod/100))
    final effectiveDefence = defenceLevel;
    final meleeDefenceBonus = bonuses.flatMeleeDefenceBonus;
    final meleeEvasionMod = bonuses.meleeEvasion;
    final meleeEvasion =
        ((effectiveDefence + 9) *
                (meleeDefenceBonus + 64) *
                (1 + meleeEvasionMod / 100))
            .floor();

    // Ranged evasion
    final rangedDefenceBonus = bonuses.flatRangedDefenceBonus;
    final rangedEvasionMod = bonuses.rangedEvasion;
    final rangedEvasion =
        ((effectiveDefence + 9) *
                (rangedDefenceBonus + 64) *
                (1 + rangedEvasionMod / 100))
            .floor();

    // Magic evasion uses 30% Defence + 70% Magic level
    // Since we don't have magic level yet, use defence only
    final magicDefenceBonus = bonuses.flatMagicDefenceBonus;
    final magicEvasionMod = bonuses.magicEvasion;
    final effectiveMagicDefence = effectiveDefence; // Simplified
    final magicEvasion =
        ((effectiveMagicDefence + 9) *
                (magicDefenceBonus + 64) *
                (1 + magicEvasionMod / 100))
            .floor();

    return PlayerCombatStats._(
      minHit: minHit,
      maxHit: maxHit,
      damageReduction: damageReduction,
      attackSpeed: attackSpeed,
      accuracy: accuracy,
      meleeEvasion: meleeEvasion,
      rangedEvasion: rangedEvasion,
      magicEvasion: magicEvasion,
    );
  }

  /// Player's accuracy rating for hit chance calculation.
  final int accuracy;

  /// Player's melee evasion rating.
  final int meleeEvasion;

  /// Player's ranged evasion rating.
  final int rangedEvasion;

  /// Player's magic evasion rating.
  final int magicEvasion;

  /// Gets the evasion rating for a specific attack type.
  int evasionForAttackType(AttackType attackType) {
    return switch (attackType) {
      AttackType.melee => meleeEvasion,
      AttackType.ranged => rangedEvasion,
      AttackType.magic => magicEvasion,
      AttackType.random => meleeEvasion, // Default to melee for random
    };
  }
}

/// Monster combat stats with accuracy and evasion.
@immutable
class MonsterCombatStats extends Stats {
  const MonsterCombatStats._({
    required super.minHit,
    required super.maxHit,
    required super.damageReduction,
    required super.attackSpeed,
    required this.accuracy,
    required this.meleeEvasion,
    required this.rangedEvasion,
    required this.magicEvasion,
  });

  /// Computes monster stats from a combat action.
  factory MonsterCombatStats.fromAction(CombatAction action) {
    final baseStats = action.stats;
    final levels = action.levels;

    // --- Monster Accuracy ---
    // Simplified: uses attack level for melee, ranged level for ranged, etc.
    final effectiveLevel = switch (action.attackType) {
      AttackType.melee => levels.attack,
      AttackType.ranged => levels.ranged,
      AttackType.magic => levels.magic,
      AttackType.random => [
        levels.attack,
        levels.ranged,
        levels.magic,
      ].reduce((a, b) => a > b ? a : b),
    };

    // Accuracy = (EffectiveLevel + 9) * 64 (no equipment bonus)
    final accuracy = (effectiveLevel + 9) * 64;

    // --- Monster Evasion ---
    // Uses defence level for all evasion types
    final defenceLevel = levels.defense;
    final baseEvasion = (defenceLevel + 9) * 64;

    return MonsterCombatStats._(
      minHit: baseStats.minHit,
      maxHit: baseStats.maxHit,
      damageReduction: baseStats.damageReduction,
      attackSpeed: baseStats.attackSpeed,
      accuracy: accuracy,
      meleeEvasion: baseEvasion,
      rangedEvasion: baseEvasion,
      magicEvasion: baseEvasion,
    );
  }

  /// Monster's accuracy rating.
  final int accuracy;

  /// Monster's melee evasion rating.
  final int meleeEvasion;

  /// Monster's ranged evasion rating.
  final int rangedEvasion;

  /// Monster's magic evasion rating.
  final int magicEvasion;
}

/// Utility class for combat calculations.
class CombatCalculator {
  CombatCalculator._();

  /// Calculates hit chance based on accuracy vs evasion.
  ///
  /// Returns a value from 0.0 to 1.0 representing the probability of hitting.
  ///
  /// Melvor formula:
  /// - If accuracy > evasion: 0.5 + (accuracy - evasion) / (2 * accuracy)
  /// - If accuracy <= evasion: 0.5 * accuracy / evasion
  static double calculateHitChance(int accuracy, int evasion) {
    if (accuracy <= 0) return 0;
    if (evasion <= 0) return 1;

    if (accuracy > evasion) {
      return 0.5 + (accuracy - evasion) / (2 * accuracy);
    }
    return 0.5 * accuracy / evasion;
  }

  /// Rolls whether an attack hits based on hit chance.
  static bool rollHit(Random random, double hitChance) {
    return random.nextDouble() < hitChance;
  }

  /// Calculates player hit chance against a monster.
  static double playerHitChance(
    PlayerCombatStats player,
    MonsterCombatStats monster,
    AttackType monsterDefenceType,
  ) {
    final evasion = switch (monsterDefenceType) {
      AttackType.melee => monster.meleeEvasion,
      AttackType.ranged => monster.rangedEvasion,
      AttackType.magic => monster.magicEvasion,
      AttackType.random => monster.meleeEvasion, // Default to melee
    };
    return calculateHitChance(player.accuracy, evasion);
  }

  /// Calculates monster hit chance against the player.
  static double monsterHitChance(
    MonsterCombatStats monster,
    PlayerCombatStats player,
    AttackType monsterAttackType,
  ) {
    final evasion = player.evasionForAttackType(monsterAttackType);
    return calculateHitChance(monster.accuracy, evasion);
  }
}

/// Computes the effective player stats for combat.
///
/// This is the main entry point for getting player combat stats.
/// It replaces the old hardcoded `playerStats()` function.
PlayerCombatStats computePlayerStats(GlobalState state) {
  return PlayerCombatStats.fromState(state);
}
