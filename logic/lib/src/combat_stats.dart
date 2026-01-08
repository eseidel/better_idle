import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Computes accuracy or evasion rating using Melvor formula.
///
/// Formula: floor((effectiveLevel + 9) * (bonus + 64) * (1 + modifier/100))
int _computeAccuracyOrEvasion({
  required int effectiveLevel,
  required num bonus,
  required num modifier,
}) {
  return ((effectiveLevel + 9) * (bonus + 64) * (1 + modifier / 100)).floor();
}

/// Computes base max hit using Melvor formula.
///
/// Formula: floor(10 * (2.2 + effectiveLevel/10 + (effectiveLevel+17)*bonus/640))
int _computeBaseMaxHit({required int effectiveLevel, required int bonus}) {
  return (10 *
          (2.2 + effectiveLevel / 10 + (effectiveLevel + 17) * bonus / 640))
      .floor();
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
    // Resolve all combat-relevant modifiers (equipment, shop purchases, etc.)
    final bonuses = state.resolveCombatModifiers();
    final attackStyle = state.attackStyle;

    // Get skill levels
    final attackLevel = state.skillState(Skill.attack).skillLevel;
    final strengthLevel = state.skillState(Skill.strength).skillLevel;
    final defenceLevel = state.skillState(Skill.defence).skillLevel;
    final rangedLevel = state.skillState(Skill.ranged).skillLevel;

    // --- Max Hit Calculation ---
    // Melvor formula:
    // floor(M * (2.2 + EffectiveLevel/10 + (EffectiveLevel+17)*StrBonus/640))
    // M = 10 for normal attacks
    //
    // Each combat type uses different skill levels and bonuses.
    // Attack styles can add +3 to effective level (accurate for ranged).
    final int maxHitLevel;
    final int maxHitBonus;
    final num maxHitPercent;

    switch (attackStyle.combatType) {
      case CombatType.melee:
        maxHitLevel = strengthLevel;
        maxHitBonus = bonuses.flatMeleeStrengthBonus.toInt();
        maxHitPercent = bonuses.maxHit + bonuses.meleeMaxHit;
      case CombatType.ranged:
        // Accurate style gives +3 effective level
        maxHitLevel =
            rangedLevel + (attackStyle == AttackStyle.accurate ? 3 : 0);
        maxHitBonus = bonuses.flatRangedStrengthBonus.toInt();
        maxHitPercent = bonuses.maxHit + bonuses.rangedMaxHit;
      case CombatType.magic:
        // TODO(eseidel): Implement magic max hit with magic level
        maxHitLevel = 1;
        maxHitBonus = 0;
        maxHitPercent = bonuses.maxHit + bonuses.magicMaxHit;
    }

    var maxHit = _computeBaseMaxHit(
      effectiveLevel: maxHitLevel,
      bonus: maxHitBonus,
    );
    // Apply percentage max hit modifiers
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
    // Base attack speed comes from weapon (equipmentAttackSpeed) or 4000ms
    // if unarmed. Equipment can modify this via attackInterval (percentage)
    // and flatAttackInterval (milliseconds).
    final weaponSpeed = bonuses.equipmentAttackSpeed;
    var attackSpeedMs = (weaponSpeed > 0 ? weaponSpeed : 4000).toDouble();

    // Apply percentage modifier first
    final intervalPercent = bonuses.attackInterval;
    attackSpeedMs *= 1 + intervalPercent / 100;

    // Rapid ranged style reduces attack speed by 20% (faster attacks)
    if (attackStyle == AttackStyle.rapid) {
      attackSpeedMs *= 0.8;
    }

    // Apply flat modifier (in milliseconds)
    attackSpeedMs += bonuses.flatAttackInterval.toDouble();

    // Convert to seconds, clamp to reasonable bounds
    final attackSpeed = (attackSpeedMs / 1000).clamp(0.5, 10.0);

    // --- Damage Reduction ---
    // In Melvor, this comes from the "resistance" modifier
    // Each point = 1% damage reduction, capped at 95%
    final resistance = bonuses.resistance + bonuses.flatResistance;
    final damageReduction = (resistance / 100).clamp(0.0, 0.95);

    // --- Accuracy Rating ---
    // Formula: floor((EffectiveLevel + 9) * (BaseAccuracyBonus + 64) * (1 + Mod/100))
    final int accuracyLevel;
    final num accuracyBonus;
    final num accuracyModifier;

    switch (attackStyle.combatType) {
      case CombatType.melee:
        accuracyLevel = attackLevel;
        // Equipment accuracy bonuses (stab, slash, block attacks)
        // TODO(eseidel): Summing all bonuses here is wrong!
        // https://wiki.melvoridle.com/w/Combat#Accuracy_Rating
        accuracyBonus =
            bonuses.flatStabAttackBonus +
            bonuses.flatSlashAttackBonus +
            bonuses.flatBlockAttackBonus;
        accuracyModifier = bonuses.meleeAccuracyRating;
      case CombatType.ranged:
        // Accurate style gives +3 effective level for accuracy
        accuracyLevel =
            rangedLevel + (attackStyle == AttackStyle.accurate ? 3 : 0);
        accuracyBonus = bonuses.flatRangedAttackBonus;
        accuracyModifier = bonuses.rangedAccuracyRating;
      case CombatType.magic:
        // TODO(eseidel): Implement magic accuracy with magic level
        accuracyLevel = 1;
        accuracyBonus = 0; // TODO(eseidel): Add flatMagicAttackBonus
        accuracyModifier = bonuses.magicAccuracyRating;
    }

    final accuracy = _computeAccuracyOrEvasion(
      effectiveLevel: accuracyLevel,
      bonus: accuracyBonus,
      modifier: accuracyModifier,
    );

    // --- Evasion Ratings ---
    // Formula: floor((EffLevel + 9) * (Bonus + 64) * (1 + Mod/100))
    final effectiveDefence = defenceLevel;

    final meleeEvasion = _computeAccuracyOrEvasion(
      effectiveLevel: effectiveDefence,
      bonus: bonuses.flatMeleeDefenceBonus,
      modifier: bonuses.meleeEvasion,
    );

    final rangedEvasion = _computeAccuracyOrEvasion(
      effectiveLevel: effectiveDefence,
      bonus: bonuses.flatRangedDefenceBonus,
      modifier: bonuses.rangedEvasion,
    );

    // Magic evasion uses 30% Defence + 70% Magic level
    // Since we don't have magic level yet, use defence only
    // TODO(eseidel): Add magic level and use it here
    final effectiveMagicDefence = effectiveDefence; // Simplified
    final magicEvasion = _computeAccuracyOrEvasion(
      effectiveLevel: effectiveMagicDefence,
      bonus: bonuses.flatMagicDefenceBonus,
      modifier: bonuses.magicEvasion,
    );

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

/// XP grants from combat damage.
///
/// Hitpoints XP is always granted: floor(damage * 1.33) per hit.
/// Combat style XP depends on the selected [AttackStyle]:
///
/// Melee styles:
/// - Stab: 4 XP per damage to Attack
/// - Slash: 4 XP per damage to Strength
/// - Block: 4 XP per damage to Defence
/// - Controlled: ~1.33 XP per damage to Attack, Strength, and Defence
///
/// Ranged styles:
/// - Accurate: 4 XP per damage to Ranged
/// - Rapid: 4 XP per damage to Ranged
/// - Longrange: 2 XP per damage to Ranged and Defence each
@immutable
class CombatXpGrant {
  const CombatXpGrant(this.xpGrants);

  /// Creates XP grants based on damage dealt and attack style.
  ///
  /// Uses Melvor Idle formulas:
  /// - Hitpoints: floor(damage * 1.33)
  /// - Combat skill: damage * 4 (distributed based on style)
  factory CombatXpGrant.fromDamage(int damage, AttackStyle style) {
    final hitpointsXp = (damage * 1.33).floor();
    final combatXp = damage * 4;

    return switch (style) {
      // Melee styles
      AttackStyle.stab => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.attack: combatXp,
      }),
      AttackStyle.slash => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.strength: combatXp,
      }),
      AttackStyle.block => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.defence: combatXp,
      }),
      AttackStyle.controlled => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.attack: (combatXp / 3).floor(),
        Skill.strength: (combatXp / 3).floor(),
        Skill.defence: (combatXp / 3).floor(),
      }),
      // Ranged styles
      AttackStyle.accurate || AttackStyle.rapid => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.ranged: combatXp,
      }),
      // Longrange splits XP between Ranged and Defence // cspell:ignore longrange
      AttackStyle.longRange => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.ranged: (combatXp / 2).floor(),
        Skill.defence: (combatXp / 2).floor(),
      }),
    };
  }

  /// Map of skill to XP amount to grant.
  final Map<Skill, int> xpGrants;

  /// Returns true if no XP would be granted.
  bool get isEmpty => xpGrants.isEmpty;

  /// Total XP across all skills.
  int get totalXp => xpGrants.values.fold(0, (a, b) => a + b);
}
