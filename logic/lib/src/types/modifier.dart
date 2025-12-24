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
// All modifiers inside `masteryLevelBonuses` are **templates**. The scope
// keys (skillID, actionID) in these modifiers are placeholder examples from
// the data, not actual filters. At evaluation time, these get substituted
// with the actual action being evaluated.
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
// The "Raw_Shrimp" here is just an example action used as a placeholder.
// At runtime, when you have level 50 mastery in catching Lobsters, the game
// applies this bonus to Lobsters, not Shrimp.
//
// The `autoScopeToAction` field (default: true) controls this behavior.
// When false, the modifier applies globally without action substitution
// (e.g., Firemaking's level 99 bonus gives +0.25% Mastery XP to all skills).
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
/// Note: In `masteryLevelBonuses`, all scopes are template placeholders,
/// not filters. See file header comment for details.
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

  /// Checks if this scope applies to the given skill.
  ///
  /// Returns true if:
  /// - This scope is global (all fields null)
  /// - [autoScopeToAction] is false (global modifier, no filtering)
  /// - [skillId] matches (or is null, meaning applies to all skills)
  ///
  /// For mastery bonuses with [autoScopeToAction] = true (default), the
  /// actionID in the scope is a template placeholder and is ignored.
  /// For [autoScopeToAction] = false, the modifier applies globally.
  bool appliesToSkill(MelvorId skillId, {bool autoScopeToAction = true}) {
    if (isGlobal) return true;
    if (!autoScopeToAction) return true; // Global modifier, no filtering
    // Check if skillId matches (null skillId means applies to all skills)
    return this.skillId == null || this.skillId == skillId;
  }

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

  /// Checks if this entry applies to the given skill.
  ///
  /// Returns true if scope is null (global) or if scope applies to the skill.
  bool appliesToSkill(MelvorId skillId, {bool autoScopeToAction = true}) {
    return scope?.appliesToSkill(
          skillId,
          autoScopeToAction: autoScopeToAction,
        ) ??
        true;
  }

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

  /// Get modifier by name, or null if not found.
  ModifierData? byName(String name) {
    for (final mod in modifiers) {
      if (mod.name == name) return mod;
    }
    return null;
  }

  /// Get total value for a modifier scoped to a specific skill.
  /// Returns the sum of all matching entries.
  int skillIntervalForSkill(MelvorId skillId) {
    final mod = byName('skillInterval');
    if (mod == null) return 0;
    var total = 0;
    for (final entry in mod.entries) {
      if (entry.scope?.skillId == skillId) {
        total += entry.value.toInt();
      }
    }
    return total;
  }

  /// Returns true if this set has any skill interval modifiers for the skill.
  bool hasSkillIntervalFor(MelvorId skillId) {
    final mod = byName('skillInterval');
    if (mod == null) return false;
    return mod.entries.any((e) => e.scope?.skillId == skillId);
  }

  /// Returns all skill IDs that have skill interval modifiers.
  List<MelvorId> get skillIntervalSkillIds {
    final mod = byName('skillInterval');
    if (mod == null) return [];
    return mod.entries
        .map((e) => e.scope?.skillId)
        .whereType<MelvorId>()
        .toList();
  }

  /// Returns the total skill interval value across all skills.
  int get totalSkillInterval {
    final mod = byName('skillInterval');
    if (mod == null) return 0;
    return mod.entries.fold<int>(0, (sum, e) => sum + e.value.toInt());
  }

  @override
  List<Object?> get props => [modifiers];
}
