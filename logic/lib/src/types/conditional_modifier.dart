// Conditional Modifier System
//
// Conditional modifiers are modifiers that only apply when certain conditions
// are met during gameplay. For example, a necklace that provides extra defense
// only when fighting a specific type of enemy.
//
// ## Condition Types
//
// - **DamageType**: Applies when player is using a specific damage type
// - **CombatType**: Applies based on attack type match-ups (melee vs ranged)
// - **ItemCharge**: Applies when an equipped item has charges remaining
// - **Hitpoints**: Applies based on player/enemy HP threshold
// - **CombatEffectGroup**: Applies when affected by certain effects
// - **FightingSlayerTask**: Applies when fighting the assigned slayer task
// - **PotionUsed**: Applies when a specific potion is active
// - **Every**: All nested conditions must be true (logical AND)
// - **Some**: Any nested condition must be true (logical OR)
//
// ## Usage in Game Data
//
// ```json
// "conditionalModifiers": [
//   {
//     "condition": {
//       "type": "CombatType",
//       "character": "Player",
//       "thisAttackType": "melee",
//       "targetAttackType": "ranged"
//     },
//     "modifiers": {
//       "flatResistance": [{ "damageTypeID": "melvorD:Normal", "value": 1 }]
//     }
//   }
// ]
// ```

import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/state.dart' show CombatType;
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

/// The character that a condition applies to (Player or Enemy).
enum ConditionCharacter {
  player,
  enemy;

  static ConditionCharacter fromJson(String json) {
    return switch (json) {
      'Player' => ConditionCharacter.player,
      'Enemy' => ConditionCharacter.enemy,
      _ => throw FormatException('Unknown character: $json'),
    };
  }
}

/// Comparison operators used in threshold conditions.
enum ComparisonOperator {
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual,
  equal;

  static ComparisonOperator fromJson(String json) {
    return switch (json) {
      '<' => ComparisonOperator.lessThan,
      '<=' => ComparisonOperator.lessThanOrEqual,
      '>' => ComparisonOperator.greaterThan,
      '>=' => ComparisonOperator.greaterThanOrEqual,
      '==' => ComparisonOperator.equal,
      _ => throw FormatException('Unknown operator: $json'),
    };
  }

  /// Evaluate this operator with the given values.
  bool evaluate(num actual, num threshold) {
    return switch (this) {
      ComparisonOperator.lessThan => actual < threshold,
      ComparisonOperator.lessThanOrEqual => actual <= threshold,
      ComparisonOperator.greaterThan => actual > threshold,
      ComparisonOperator.greaterThanOrEqual => actual >= threshold,
      ComparisonOperator.equal => actual == threshold,
    };
  }
}

/// Base class for all modifier conditions.
///
/// Conditions are evaluated at runtime to determine if a conditional modifier
/// should be active.
@immutable
sealed class ModifierCondition {
  const ModifierCondition();

  /// Parse a condition from JSON.
  factory ModifierCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final type = json['type'] as String;

    return switch (type) {
      'DamageType' => DamageTypeCondition.fromJson(json, namespace: namespace),
      'CombatType' => CombatTypeCondition.fromJson(json, namespace: namespace),
      'ItemCharge' => ItemChargeCondition.fromJson(json, namespace: namespace),
      'BankItem' => BankItemCondition.fromJson(json, namespace: namespace),
      'Hitpoints' => HitpointsCondition.fromJson(json, namespace: namespace),
      'CombatEffectGroup' => CombatEffectGroupCondition.fromJson(
        json,
        namespace: namespace,
      ),
      'FightingSlayerTask' => const FightingSlayerTaskCondition(),
      'PotionUsed' => PotionUsedCondition.fromJson(json, namespace: namespace),
      'Every' => EveryCondition.fromJson(json, namespace: namespace),
      'Some' => SomeCondition.fromJson(json, namespace: namespace),
      _ => throw FormatException('Unknown condition type: $type'),
    };
  }
}

/// Condition that checks if the player is using a specific damage type.
///
/// Example: Sand Treaders provide -100ms attack interval when using Normal
/// damage type.
@immutable
class DamageTypeCondition extends ModifierCondition {
  const DamageTypeCondition({
    required this.character,
    required this.damageType,
  });

  factory DamageTypeCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return DamageTypeCondition(
      character: ConditionCharacter.fromJson(json['character'] as String),
      damageType: MelvorId.fromJsonWithNamespace(
        json['damageType'] as String,
        defaultNamespace: namespace,
      ),
    );
  }

  /// The character this condition applies to.
  final ConditionCharacter character;

  /// The damage type that must be used.
  final MelvorId damageType;
}

/// Condition that checks attack type match-ups (melee vs ranged, etc.).
///
/// Example: Gold Sapphire Necklace provides +1 resistance when using melee
/// against ranged enemies.
@immutable
class CombatTypeCondition extends ModifierCondition {
  const CombatTypeCondition({
    required this.character,
    this.thisAttackType,
    this.targetAttackType,
  });

  factory CombatTypeCondition.fromJson(
    Map<String, dynamic> json, {
    // Unused but kept for API consistency with other fromJson methods.
    // ignore: avoid_unused_constructor_parameters
    required String namespace,
  }) {
    return CombatTypeCondition(
      character: ConditionCharacter.fromJson(json['character'] as String),
      thisAttackType: _parseCombatType(json['thisAttackType'] as String),
      targetAttackType: _parseCombatType(json['targetAttackType'] as String),
    );
  }

  /// Parses a combat type from JSON, returning null for 'any'.
  static CombatType? _parseCombatType(String value) {
    if (value == 'any') return null;
    return CombatType.fromJson(value);
  }

  /// The character this condition applies to.
  final ConditionCharacter character;

  /// The attack type the player/this character must be using.
  /// Null means 'any' - matches all attack types.
  final CombatType? thisAttackType;

  /// The attack type the target must be using.
  /// Null means 'any' - matches all attack types.
  final CombatType? targetAttackType;
}

/// Condition that checks if an item has charges remaining.
///
/// Example: Thieving Gloves provide +75 stealth when they have charges.
@immutable
class ItemChargeCondition extends ModifierCondition {
  const ItemChargeCondition({
    required this.itemId,
    required this.operator,
    required this.value,
  });

  factory ItemChargeCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return ItemChargeCondition(
      itemId: MelvorId.fromJsonWithNamespace(
        json['itemID'] as String,
        defaultNamespace: namespace,
      ),
      operator: ComparisonOperator.fromJson(json['operator'] as String),
      value: json['value'] as int,
    );
  }

  /// The item whose charges are checked.
  final MelvorId itemId;

  /// The comparison operator.
  final ComparisonOperator operator;

  /// The value to compare against.
  final int value;
}

/// Condition that checks if an item exists in the bank with a certain count.
///
/// Example: Crown of Rhaelyx provides bonuses when Charge Stone is in bank.
@immutable
class BankItemCondition extends ModifierCondition {
  const BankItemCondition({
    required this.itemId,
    required this.operator,
    required this.value,
  });

  factory BankItemCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return BankItemCondition(
      itemId: MelvorId.fromJsonWithNamespace(
        json['itemID'] as String,
        defaultNamespace: namespace,
      ),
      operator: ComparisonOperator.fromJson(json['operator'] as String),
      value: json['value'] as int,
    );
  }

  /// The item to check for in the bank.
  final MelvorId itemId;

  /// The comparison operator.
  final ComparisonOperator operator;

  /// The value to compare the bank count against.
  final int value;
}

/// Condition that checks if hitpoints are above/below a threshold.
///
/// Example: Guardian Amulet provides +5 resistance when HP is below 50%.
@immutable
class HitpointsCondition extends ModifierCondition {
  const HitpointsCondition({
    required this.character,
    required this.operator,
    required this.value,
  });

  factory HitpointsCondition.fromJson(
    Map<String, dynamic> json, {
    // Unused but kept for API consistency with other fromJson methods.
    // ignore: avoid_unused_constructor_parameters
    required String namespace,
  }) {
    return HitpointsCondition(
      character: ConditionCharacter.fromJson(json['character'] as String),
      operator: ComparisonOperator.fromJson(json['operator'] as String),
      value: json['value'] as int,
    );
  }

  /// The character whose HP is checked.
  final ConditionCharacter character;

  /// The comparison operator.
  final ComparisonOperator operator;

  /// The HP percentage threshold (0-100).
  final int value;
}

/// Condition that checks if affected by a combat effect group.
///
/// Example: Bonuses when affected by poison, burn, slow, etc.
@immutable
class CombatEffectGroupCondition extends ModifierCondition {
  const CombatEffectGroupCondition({
    required this.character,
    required this.groupId,
  });

  factory CombatEffectGroupCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return CombatEffectGroupCondition(
      character: ConditionCharacter.fromJson(json['character'] as String),
      groupId: MelvorId.fromJsonWithNamespace(
        json['groupID'] as String,
        defaultNamespace: namespace,
      ),
    );
  }

  /// The character that must be affected.
  final ConditionCharacter character;

  /// The effect group ID (e.g., "melvorD:PoisonDOT", "melvorD:BurnDOT").
  final MelvorId groupId;
}

/// Condition that checks if fighting the assigned slayer task.
///
/// Example: Slayer Blinding Scroll reduces monster accuracy during tasks.
@immutable
class FightingSlayerTaskCondition extends ModifierCondition {
  const FightingSlayerTaskCondition();
}

/// Condition that checks if a specific potion is being used.
///
/// Example: Bird Nest Potion provides extra bird nest drops when active.
@immutable
class PotionUsedCondition extends ModifierCondition {
  const PotionUsedCondition({required this.recipeId});

  factory PotionUsedCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return PotionUsedCondition(
      recipeId: MelvorId.fromJsonWithNamespace(
        json['recipeID'] as String,
        defaultNamespace: namespace,
      ),
    );
  }

  /// The potion recipe ID that must be active.
  final MelvorId recipeId;
}

/// Condition that requires ALL nested conditions to be true (logical AND).
///
/// Example: Knight's Defender requires both melee attack type AND normal
/// damage type.
@immutable
class EveryCondition extends ModifierCondition {
  const EveryCondition({required this.conditions});

  factory EveryCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final conditionsJson = json['conditions'] as List<dynamic>;
    final conditions = conditionsJson
        .map(
          (c) => ModifierCondition.fromJson(
            c as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();
    return EveryCondition(conditions: conditions);
  }

  /// The conditions that must all be true.
  final List<ModifierCondition> conditions;
}

/// Condition that requires ANY nested condition to be true (logical OR).
///
// cspell:ignore-next-line frostburn - Melvor game term
/// Example: Bonuses when affected by slow OR frostburn OR burn effects.
@immutable
class SomeCondition extends ModifierCondition {
  const SomeCondition({required this.conditions});

  factory SomeCondition.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final conditionsJson = json['conditions'] as List<dynamic>;
    final conditions = conditionsJson
        .map(
          (c) => ModifierCondition.fromJson(
            c as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();
    return SomeCondition(conditions: conditions);
  }

  /// The conditions where at least one must be true.
  final List<ModifierCondition> conditions;
}

/// A modifier that only applies when its condition is met.
@immutable
class ConditionalModifier {
  const ConditionalModifier({
    required this.condition,
    required this.modifiers,
    this.enemyModifiers,
    this.descriptionLang,
  });

  factory ConditionalModifier.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final conditionJson = json['condition'] as Map<String, dynamic>;
    final condition = ModifierCondition.fromJson(
      conditionJson,
      namespace: namespace,
    );

    final modifiersJson = json['modifiers'] as Map<String, dynamic>?;
    final modifiers = modifiersJson != null
        ? ModifierDataSet.fromJson(modifiersJson, namespace: namespace)
        : const ModifierDataSet([]);

    final enemyModifiersJson = json['enemyModifiers'] as Map<String, dynamic>?;
    final enemyModifiers = enemyModifiersJson != null
        ? ModifierDataSet.fromJson(enemyModifiersJson, namespace: namespace)
        : null;

    return ConditionalModifier(
      condition: condition,
      modifiers: modifiers,
      enemyModifiers: enemyModifiers,
      descriptionLang: json['descriptionLang'] as String?,
    );
  }

  /// The condition that must be met for these modifiers to apply.
  final ModifierCondition condition;

  /// The modifiers to apply when the condition is met.
  final ModifierDataSet modifiers;

  /// Enemy modifiers to apply when the condition is met.
  /// Used for conditions that affect the enemy (e.g., slayer scrolls).
  final ModifierDataSet? enemyModifiers;

  /// Localization key for the condition description.
  final String? descriptionLang;
}
