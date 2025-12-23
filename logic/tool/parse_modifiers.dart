// Modifier System Parser
//
// This tool parses all modifiers from the Melvor Idle JSON data files and
// generates statistics about their structure and usage.
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

import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/cache.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

// ============================================================================
// Core Types
// ============================================================================

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

// ============================================================================
// JSON Tree Walker & Statistics
// ============================================================================

/// Represents the source location of a modifier.
class ModifierSource {
  ModifierSource(this.category, this.id, this.name);
  final String category;
  final String? id;
  final String? name;

  @override
  String toString() => '[$category:${id ?? name ?? 'unknown'}]';
}

/// Statistics about parsed modifiers.
class ModifierStats {
  final Map<String, ModifierNameStats> byName = {};
  final List<ParseFailure> failures = [];
  int totalInstances = 0;
  int successCount = 0;
}

/// Statistics for a single modifier name.
class ModifierNameStats {
  int scalarCount = 0;
  int arrayCount = 0;
  final Set<String> scopePatterns = {};
  num? minValue;
  num? maxValue;

  void recordValue(num value) {
    minValue = minValue == null
        ? value
        : (value < minValue! ? value : minValue);
    maxValue = maxValue == null
        ? value
        : (value > maxValue! ? value : maxValue);
  }
}

/// A parse failure record.
class ParseFailure {
  ParseFailure(this.source, this.name, this.error, this.value);
  final ModifierSource source;
  final String name;
  final String error;
  final dynamic value;
}

/// Parses modifiers from a Map and updates stats.
void parseModifiersMap(
  Map<String, dynamic> modifiers,
  String namespace,
  ModifierStats stats,
  ModifierSource source,
) {
  for (final entry in modifiers.entries) {
    // Handle special "add" key which contains nested modifiers
    if (entry.key == 'add' && entry.value is Map<String, dynamic>) {
      parseModifiersMap(
        entry.value as Map<String, dynamic>,
        namespace,
        stats,
        source,
      );
      continue;
    }

    stats.totalInstances++;
    try {
      final modifier = ModifierData.fromJson(
        entry.key,
        entry.value,
        namespace: namespace,
      );
      stats.successCount++;

      // Update stats for this modifier name
      final nameStats = stats.byName.putIfAbsent(
        entry.key,
        () => ModifierNameStats(),
      );

      if (modifier.isScalar) {
        nameStats.scalarCount++;
        nameStats.recordValue(modifier.entries.first.value);
      } else {
        nameStats.arrayCount++;
        for (final e in modifier.entries) {
          nameStats.recordValue(e.value);
          if (e.scope != null) {
            nameStats.scopePatterns.add(e.scope.toString());
          }
        }
      }
    } catch (e) {
      stats.failures.add(
        ParseFailure(source, entry.key, e.toString(), entry.value),
      );
    }
  }
}

/// Walks the JSON tree and extracts all modifiers.
void walkJson(
  dynamic json,
  String namespace,
  ModifierStats stats, {
  ModifierSource? currentSource,
}) {
  if (json is Map<String, dynamic>) {
    // Check for modifiers at this level
    final modifiers = json['modifiers'];
    if (modifiers is Map<String, dynamic>) {
      // Try to identify the source
      final source =
          currentSource ??
          ModifierSource(
            'unknown',
            json['id'] as String?,
            json['name'] as String?,
          );

      parseModifiersMap(modifiers, namespace, stats, source);
    }

    // Also check enemyModifiers (used in summoning, game modes)
    final enemyModifiers = json['enemyModifiers'];
    if (enemyModifiers is Map<String, dynamic>) {
      final source =
          currentSource ??
          ModifierSource(
            'enemyModifiers',
            json['id'] as String?,
            json['name'] as String?,
          );
      parseModifiersMap(enemyModifiers, namespace, stats, source);
    }

    // Check playerModifiers (used in game modes)
    final playerModifiers = json['playerModifiers'];
    if (playerModifiers is Map<String, dynamic>) {
      final source =
          currentSource ??
          ModifierSource(
            'playerModifiers',
            json['id'] as String?,
            json['name'] as String?,
          );
      parseModifiersMap(playerModifiers, namespace, stats, source);
    }

    // Recurse into known collection fields
    for (final key in json.keys) {
      final value = json[key];
      if (value is List) {
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            final itemId = item['id'] as String?;
            final itemName = item['name'] as String?;
            walkJson(
              item,
              namespace,
              stats,
              currentSource: ModifierSource(key, itemId, itemName),
            );
          }
        }
      } else if (value is Map<String, dynamic> && key != 'modifiers') {
        walkJson(value, namespace, stats, currentSource: currentSource);
      }
    }
  } else if (json is List) {
    for (final item in json) {
      walkJson(item, namespace, stats, currentSource: currentSource);
    }
  }
}

// ============================================================================
// Main
// ============================================================================

void main() async {
  final cache = Cache(cacheDir: defaultCacheDir);

  try {
    print('Loading JSON data files...\n');
    final demoData = await cache.ensureDemoData();
    final fullData = await cache.ensureFullData();

    final stats = ModifierStats();

    // Walk both files
    final demoNamespace = demoData['namespace'] as String? ?? 'melvorD';
    final fullNamespace = fullData['namespace'] as String? ?? 'melvorF';

    walkJson(demoData, demoNamespace, stats);
    walkJson(fullData, fullNamespace, stats);

    // Print console summary
    printConsoleSummary(stats);

    // Write JSON report
    await writeJsonReport(stats);

    print('\nJSON report written to: modifier_report.json');
  } finally {
    cache.close();
  }
}

void printConsoleSummary(ModifierStats stats) {
  print('=== MODIFIER PARSING REPORT ===\n');
  print('Files: melvorDemo.json, melvorFull.json');
  print('Total modifier instances: ${stats.totalInstances}');
  print('Unique modifier names: ${stats.byName.length}');
  print(
    'Successfully parsed: ${stats.successCount} '
    '(${(stats.successCount / stats.totalInstances * 100).toStringAsFixed(1)}%)',
  );
  print('Parse failures: ${stats.failures.length}');

  print('\n=== BY MODIFIER NAME ===');
  final sortedNames = stats.byName.keys.toList()..sort();
  for (final name in sortedNames) {
    final s = stats.byName[name]!;
    final total = s.scalarCount + s.arrayCount;
    final parts = <String>[];
    if (s.scalarCount > 0) parts.add('${s.scalarCount} scalar');
    if (s.arrayCount > 0) parts.add('${s.arrayCount} array');
    final valueRange = s.minValue != null && s.maxValue != null
        ? ' [${s.minValue}..${s.maxValue}]'
        : '';
    print('  $name: $total instances (${parts.join(', ')})$valueRange');
    if (s.scopePatterns.isNotEmpty) {
      print('    Scopes: ${s.scopePatterns.join(', ')}');
    }
  }

  // Aggregate scope patterns
  print('\n=== SCOPE PATTERNS ===');
  final scopeCounts = <String, Set<String>>{};
  for (final entry in stats.byName.entries) {
    for (final pattern in entry.value.scopePatterns) {
      scopeCounts.putIfAbsent(pattern, () => {}).add(entry.key);
    }
  }
  final sortedPatterns = scopeCounts.keys.toList()
    ..sort((a, b) => scopeCounts[b]!.length.compareTo(scopeCounts[a]!.length));
  for (final pattern in sortedPatterns) {
    final modifiers = scopeCounts[pattern]!;
    print('  {$pattern}: ${modifiers.length} modifier types');
  }

  if (stats.failures.isNotEmpty) {
    print('\n=== FAILURES ===');
    for (final f in stats.failures) {
      print('  ${f.source} ${f.name}: ${f.error}');
      final valueStr = jsonEncode(f.value);
      final truncated = valueStr.length > 100
          ? '${valueStr.substring(0, 100)}...'
          : valueStr;
      print('    Value: $truncated');
    }
  }
}

Future<void> writeJsonReport(ModifierStats stats) async {
  final report = <String, dynamic>{
    'summary': {
      'total': stats.totalInstances,
      'success': stats.successCount,
      'failures': stats.failures.length,
      'uniqueNames': stats.byName.length,
    },
    'modifiers': {
      for (final entry in stats.byName.entries)
        entry.key: {
          'scalarCount': entry.value.scalarCount,
          'arrayCount': entry.value.arrayCount,
          'scopePatterns': entry.value.scopePatterns.toList()..sort(),
          'valueRange': {
            'min': entry.value.minValue,
            'max': entry.value.maxValue,
          },
        },
    },
    'failures': stats.failures
        .map(
          (f) => {
            'source': f.source.toString(),
            'name': f.name,
            'error': f.error,
          },
        )
        .toList(),
  };

  final file = File('modifier_report.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
}
