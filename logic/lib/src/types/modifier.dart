// Modifier System
//
// This module parses modifiers from the Melvor Idle JSON data files.
//
// ## Modifier Value Formats
//
// Modifiers come in two formats:
//
// 1. **Scalar**: A single numeric value that applies globally.
//    ```json
//    "modifiers": { "skillXP": 5 }
//    ```
//    This means +5% XP to ALL skills.
//
// 2. **Array**: A list of scoped values, each with a filter and value.
//    ```json
//    "modifiers": {
//      "skillInterval": [
//        { "skillID": "melvorD:Fishing", "value": -15 }
//      ]
//    }
//    ```
//    This means -15% action time for Fishing only.
//
// Some modifiers (like skillXP) can appear in EITHER format depending on
// context - scalar when applying globally, array when scoped to specific
// skills.
//
// ## Scope Keys
//
// Array entries use these keys to filter where the modifier applies:
//
// - `skillID` - Target skill (e.g., "melvorD:Fishing")
// - `actionID` - Specific action within a skill (e.g., "melvorD:Raw_Shrimp")
// - `realmID` - Game realm (base game vs expansion)
// - `categoryID` / `subcategoryID` - Item or action categories
// - `itemID` - Specific item
// - `currencyID` - Currency type (GP, Slayer Coins, etc.)
// - `damageTypeID` - Damage type for combat
// - `effectGroupID` - Effect type (burn, poison, etc.)
//
// Multiple scope keys can combine to create more specific filters:
// ```json
// { "skillID": "melvorD:Mining", "actionID": "melvorD:Iron_Ore", "value": 5 }
// ```
//
// ## Special Case: masteryLevelBonuses
//
// Inside `masteryLevelBonuses`, the `actionID` is NOT a filter - it's a
// **template placeholder**. These define bonuses that apply at certain
// mastery levels, and the actionID gets substituted with whatever action
// they are being evaluated for.
//
// For example, in Fishing's masteryLevelBonuses:
// ```json
// {
//   "modifiers": {
//     "fishingMasteryDoublingChance": [
//       { "actionID": "melvorD:Raw_Shrimp", "value": 0.4 }
//     ]
//   },
//   "level": 1,
//   "levelScalingSlope": 1,
//   "levelScalingMax": 99
// }
// ```
// The "Raw_Shrimp" here is just the first fishing action used as an example.
// At runtime, when you have level 50 mastery in catching Lobsters, the game
// applies this bonus to Lobsters, not Shrimp.
//
// The `actionID`-only scope pattern appears EXCLUSIVELY in masteryLevelBonuses.
// Everywhere else, actionID is combined with skillID (or other keys) to form
// an actual filter.
//
// ## Special Keys
//
// - `add`: Contains nested modifiers to be added (used in modifications).
//   These are recursively parsed as additional modifiers.
//
// - `enemyModifiers` / `playerModifiers`: Alternative modifier containers
//   used in game modes and summoning familiars.

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A modifier scope identifies what the modifier applies to.
///
/// Can contain multiple scope keys (skillID, actionID, etc.) that act as
/// filters - the modifier only applies when all specified conditions match.
///
/// Note: In `masteryLevelBonuses`, an actionID-only scope is a template
/// placeholder, not a filter. See file header comment for details.
@immutable
class ModifierScope extends Equatable {
  const ModifierScope({
    this.skillId,
    this.actionId,
    this.realmId,
    this.categoryId,
    this.subcategoryId,
    this.itemId,
    this.currencyId,
    this.damageTypeId,
    this.effectGroupId,
  });

  factory ModifierScope.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    MelvorId? parseId(String key) {
      final value = json[key] as String?;
      if (value == null) return null;
      return MelvorId.fromJsonWithNamespace(value, defaultNamespace: namespace);
    }

    return ModifierScope(
      skillId: parseId('skillID'),
      actionId: parseId('actionID'),
      realmId: parseId('realmID'),
      categoryId: parseId('categoryID'),
      subcategoryId: parseId('subcategoryID'),
      itemId: parseId('itemID'),
      currencyId: parseId('currencyID'),
      damageTypeId: parseId('damageTypeID'),
      effectGroupId: parseId('effectGroupID'),
    );
  }

  final MelvorId? skillId;
  final MelvorId? actionId;
  final MelvorId? realmId;
  final MelvorId? categoryId;
  final MelvorId? subcategoryId;
  final MelvorId? itemId;
  final MelvorId? currencyId;
  final MelvorId? damageTypeId;
  final MelvorId? effectGroupId;

  /// True if this is an unscoped (global) modifier.
  bool get isGlobal =>
      skillId == null &&
      actionId == null &&
      realmId == null &&
      categoryId == null &&
      subcategoryId == null &&
      itemId == null &&
      currencyId == null &&
      damageTypeId == null &&
      effectGroupId == null;

  /// Returns the scope keys present in this scope, sorted alphabetically.
  List<String> get presentKeys {
    final keys = <String>[];
    if (skillId != null) keys.add('skillID');
    if (actionId != null) keys.add('actionID');
    if (realmId != null) keys.add('realmID');
    if (categoryId != null) keys.add('categoryID');
    if (subcategoryId != null) keys.add('subcategoryID');
    if (itemId != null) keys.add('itemID');
    if (currencyId != null) keys.add('currencyID');
    if (damageTypeId != null) keys.add('damageTypeID');
    if (effectGroupId != null) keys.add('effectGroupID');
    keys.sort();
    return keys;
  }

  @override
  List<Object?> get props => [
    skillId,
    actionId,
    realmId,
    categoryId,
    subcategoryId,
    itemId,
    currencyId,
    damageTypeId,
    effectGroupId,
  ];

  @override
  String toString() => presentKeys.isEmpty ? 'global' : presentKeys.join(',');
}

/// A single modifier entry with optional scope.
@immutable
class ModifierEntry extends Equatable {
  const ModifierEntry({required this.value, this.scope});

  /// The modifier value (percentage points or flat amount).
  final num value;

  /// Scope (null means global/unscoped).
  final ModifierScope? scope;

  @override
  List<Object?> get props => [value, scope];
}

/// A complete modifier with name and entries.
@immutable
class ModifierData extends Equatable {
  const ModifierData({required this.name, required this.entries});

  /// Parse a modifier from its JSON key and value.
  factory ModifierData.fromJson(
    String key,
    dynamic value, {
    required String namespace,
  }) {
    final entries = <ModifierEntry>[];

    if (value is num) {
      // Scalar value - single entry with no scope
      entries.add(ModifierEntry(value: value));
    } else if (value is List) {
      // Array of scoped values
      for (final item in value) {
        if (item is Map<String, dynamic>) {
          final entryValue = item['value'];
          if (entryValue is num) {
            final scope = ModifierScope.fromJson(item, namespace: namespace);
            entries.add(ModifierEntry(value: entryValue, scope: scope));
          } else {
            // Value field is missing or not a number
            throw FormatException(
              'Array entry missing "value" field or not a number: $item',
            );
          }
        } else {
          throw FormatException('Array entry is not an object: $item');
        }
      }
    } else {
      throw FormatException('Unexpected value type: ${value.runtimeType}');
    }

    return ModifierData(name: key, entries: entries);
  }

  /// The modifier name/key (e.g., "skillXP", "skillInterval").
  final String name;

  /// One or more entries (scalar = 1 entry, array = N entries).
  final List<ModifierEntry> entries;

  /// True if this is a scalar (single unscoped entry).
  bool get isScalar =>
      entries.length == 1 && (entries.first.scope?.isGlobal ?? true);

  /// Total value when no scope filtering (sum of all entries).
  num get totalValue => entries.fold<num>(0, (sum, e) => sum + e.value);

  @override
  List<Object?> get props => [name, entries];
}

/// A collection of modifiers (from an item, potion, game mode, etc.)
@immutable
class ModifierDataSet extends Equatable {
  const ModifierDataSet(this.modifiers);

  factory ModifierDataSet.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final modifiers = <ModifierData>[];
    for (final entry in json.entries) {
      modifiers.add(
        ModifierData.fromJson(entry.key, entry.value, namespace: namespace),
      );
    }
    return ModifierDataSet(modifiers);
  }

  final List<ModifierData> modifiers;

  @override
  List<Object?> get props => [modifiers];
}
