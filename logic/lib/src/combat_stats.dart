import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

/// Combat triangle modifiers for a specific matchup.
///
/// In Melvor Idle's Normal mode, the combat triangle provides damage and
/// damage reduction bonuses/penalties based on player vs monster combat types.
@immutable
class CombatTriangleModifiers {
  const CombatTriangleModifiers({
    required this.damageModifier,
    required this.damageReductionModifier,
  });

  /// Multiplier applied to player damage (1.0 = no change).
  /// > 1.0 means player deals more damage (advantage).
  /// < 1.0 means player deals less damage (disadvantage).
  final double damageModifier;

  /// Multiplier applied to incoming damage after player's damage reduction.
  /// > 1.0 means player takes less damage (advantage).
  /// < 1.0 means player takes more damage (disadvantage).
  ///
  /// This is applied as:
  ///   finalDamage = damage * (1 - DR * damageReductionModifier)
  /// So higher values mean the player's DR is more effective.
  final double damageReductionModifier;

  /// Neutral modifiers (no advantage or disadvantage).
  static const neutral = CombatTriangleModifiers(
    damageModifier: 1,
    damageReductionModifier: 1,
  );
}

/// Combat triangle system from Melvor Idle.
///
/// In Normal mode:
/// - Melee beats Ranged (player deals 1.10x damage, takes 0.80x damage)
/// - Ranged beats Magic (player deals 1.10x damage, takes 0.80x damage)
/// - Magic beats Melee (player deals 1.10x damage, takes 0.80x damage)
///
/// When at a disadvantage:
/// - Player deals 0.85x damage
/// - Player's damage reduction is less effective (0.75x to 0.95x)
class CombatTriangle {
  CombatTriangle._();

  /// Gets combat triangle modifiers for a player vs monster matchup.
  ///
  /// [playerCombatType] is the player's current combat style.
  /// [monsterAttackType] is the monster's attack type.
  ///
  /// Returns modifiers that affect player damage dealt and damage taken.
  static CombatTriangleModifiers getModifiers(
    CombatType playerCombatType,
    AttackType monsterAttackType,
  ) {
    final monsterCombatType = monsterAttackType.combatType;

    // Same type = neutral
    if (playerCombatType == monsterCombatType) {
      return CombatTriangleModifiers.neutral;
    }

    // Check if player has advantage (player type beats monster type)
    final hasAdvantage = switch ((playerCombatType, monsterCombatType)) {
      (CombatType.melee, CombatType.ranged) => true,
      (CombatType.ranged, CombatType.magic) => true,
      (CombatType.magic, CombatType.melee) => true,
      _ => false,
    };

    if (hasAdvantage) {
      // Player has advantage: deal more damage, take less damage
      return const CombatTriangleModifiers(
        damageModifier: 1.10,
        damageReductionModifier: 1.25,
      );
    } else {
      // Player has disadvantage: deal less damage, take more damage
      // Damage reduction modifier varies by matchup in Melvor
      final drModifier = switch ((playerCombatType, monsterCombatType)) {
        (CombatType.melee, CombatType.magic) => 0.75,
        (CombatType.ranged, CombatType.melee) => 0.95,
        (CombatType.magic, CombatType.ranged) => 0.85,
        _ => 1.0, // Shouldn't happen
      };
      return CombatTriangleModifiers(
        damageModifier: 0.85,
        damageReductionModifier: drModifier,
      );
    }
  }

  /// Applies damage modifier from combat triangle to player damage.
  static int applyDamageModifier(int damage, CombatTriangleModifiers mods) {
    return (damage * mods.damageModifier).round();
  }

  /// Applies damage reduction with combat triangle modifier.
  ///
  /// The combat triangle affects how effective the player's damage reduction
  /// is. With advantage (modifier > 1.0), DR is more effective.
  /// With disadvantage (modifier < 1.0), DR is less effective.
  static int applyDamageReduction(
    int damage,
    double baseDamageReduction,
    CombatTriangleModifiers mods,
  ) {
    // Effective DR = base DR * modifier, capped at 95%
    final effectiveDR = (baseDamageReduction * mods.damageReductionModifier)
        .clamp(0.0, 0.95);
    return (damage * (1 - effectiveDR)).round();
  }
}

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
    final magicLevel = state.skillState(Skill.magic).skillLevel;

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
        // Magic uses magic level for max hit calculation
        maxHitLevel = magicLevel;
        maxHitBonus = bonuses.flatMagicMaxHit.toInt();
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
    // Start at 1, apply flat modifiers.
    // Note: flatMinHit and flatMagicMinHit are scaled by 10 during parsing.
    var minHit = 1 + bonuses.flatMinHit.toInt();

    // Add style-specific flat min hit modifiers
    switch (attackStyle.combatType) {
      case CombatType.magic:
        minHit += bonuses.flatMagicMinHit.toInt();
      case CombatType.melee:
      case CombatType.ranged:
        // No style-specific flat min hit modifiers for melee/ranged
        break;
    }

    // minHitBasedOnMaxHit is a percentage of max hit added to min hit.
    // Also check for style-specific variants (currently only magic has one).
    var minHitPercent = bonuses.minHitBasedOnMaxHit;
    switch (attackStyle.combatType) {
      case CombatType.magic:
        minHitPercent += bonuses.magicMinHitBasedOnMaxHit;
      case CombatType.melee:
      case CombatType.ranged:
        // No style-specific minHitBasedOnMaxHit modifiers for melee/ranged
        break;
    }
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
        // Magic uses magic level for accuracy calculation
        accuracyLevel = magicLevel;
        accuracyBonus = bonuses.flatMagicAttackBonus;
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

    // Magic evasion uses 30% Defence + 70% Magic level per Melvor formula
    final effectiveMagicDefence = ((defenceLevel * 0.3) + (magicLevel * 0.7))
        .floor();
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
/// Hitpoints XP is always granted: 0.133 XP per damage (1.3% per damage).
/// Combat style XP depends on the selected [AttackStyle]:
///
/// Melee styles:
/// - Stab: 0.04 XP per damage (4%) to Attack
/// - Slash: 0.04 XP per damage (4%) to Strength
/// - Block: 0.04 XP per damage (4%) to Defence
/// - Controlled: ~0.0133 XP per damage to Attack, Strength, and Defence each
///
/// Ranged styles:
/// - Accurate: 0.04 XP per damage (4%) to Ranged
/// - Rapid: 0.04 XP per damage (4%) to Ranged
/// - Longrange: 0.02 XP per damage (2%) to Ranged and Defence each
@immutable
class CombatXpGrant {
  const CombatXpGrant(this.xpGrants);

  /// Creates XP grants based on damage dealt and attack style.
  ///
  /// Uses Melvor Idle formulas:
  /// - Hitpoints: 0.133 XP per damage (1.3%)
  /// - Single skill style: 0.04 XP per damage (4%)
  /// - Hybrid style: 0.02 XP per damage per skill (2%)
  ///
  /// Minimum 1 XP is granted per skill when any damage is dealt.
  factory CombatXpGrant.fromDamage(int damage, AttackStyle style) {
    if (damage <= 0) {
      return const CombatXpGrant({});
    }
    // Minimum 1 XP per skill when damage is dealt
    final hitpointsXp = (damage * 0.133).floor().clamp(1, damage);
    // Single skill: 4% = 0.04 per damage
    final singleSkillXp = (damage * 0.04).floor().clamp(1, damage);
    // Hybrid: 2% = 0.02 per damage per skill
    final hybridXp = (damage * 0.02).floor().clamp(1, damage);

    return switch (style) {
      // Melee styles
      AttackStyle.stab => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.attack: singleSkillXp,
      }),
      AttackStyle.slash => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.strength: singleSkillXp,
      }),
      AttackStyle.block => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.defence: singleSkillXp,
      }),
      // Ranged styles
      AttackStyle.accurate || AttackStyle.rapid => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.ranged: singleSkillXp,
      }),
      // Longrange splits XP between Ranged and Defence // cspell:ignore longrange
      AttackStyle.longRange => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.ranged: hybridXp,
        Skill.defence: hybridXp,
      }),
      // Magic styles
      AttackStyle.standard => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.magic: singleSkillXp,
      }),
      // Defensive splits XP between Magic and Defence
      AttackStyle.defensive => CombatXpGrant({
        Skill.hitpoints: hitpointsXp,
        Skill.magic: hybridXp,
        Skill.defence: hybridXp,
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
