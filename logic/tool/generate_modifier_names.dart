// Generates lib/src/types/modifier_names.dart with typed modifier accessor
// methods for ModifierProvider.
//
// Run from the logic/ directory:
//   dart run tool/generate_modifier_names.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:logic/src/data/cache.dart';

/// Convert snake_case to CamelCase.
String camelFromSnake(String snake) {
  return snake.splitMapJoin(
    RegExp('_'),
    onMatch: (m) => '',
    onNonMatch: (n) => n.capitalizeFirst(),
  );
}

String lowercaseCamelFromSnake(String snake) =>
    camelFromSnake(snake).lowerFirst();

extension CapitalizeString on String {
  String capitalizeFirst() {
    if (isEmpty) {
      return this;
    }
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  String lowerFirst() {
    if (isEmpty) {
      return this;
    }
    return '${this[0].toLowerCase()}${substring(1)}';
  }
}

/// Tracks which scope fields a modifier uses and the value types observed.
class ModifierScopeInfo {
  bool hasSkillId = false;
  bool hasActionId = false;
  bool hasItemId = false;
  bool hasCategoryId = false;
  bool hasRealmId = false;

  // Track if we've seen this modifier as a scalar (no scope)
  bool seenAsScalar = false;

  // Track if all occurrences have a particular scope field
  bool alwaysHasSkillId = true;
  bool alwaysHasActionId = true;
  bool alwaysHasItemId = true;
  bool alwaysHasCategoryId = true;
  bool alwaysHasRealmId = true;

  // Track value types - if all values are integers, we can return int
  bool _hasSeenValue = false;
  bool _alwaysInteger = true;

  /// Returns true if all observed values were integers (no decimals).
  bool get alwaysInteger => _hasSeenValue && _alwaysInteger;

  int occurrenceCount = 0;

  void recordOccurrence({
    bool hasSkillId = false,
    bool hasActionId = false,
    bool hasItemId = false,
    bool hasCategoryId = false,
    bool hasRealmId = false,
    bool isScalar = false,
  }) {
    occurrenceCount++;

    if (isScalar) {
      seenAsScalar = true;
      // Scalar means no scope, so all "always" flags become false
      alwaysHasSkillId = false;
      alwaysHasActionId = false;
      alwaysHasItemId = false;
      alwaysHasCategoryId = false;
      alwaysHasRealmId = false;
      return;
    }

    // Track if this scope field was ever used
    if (hasSkillId) this.hasSkillId = true;
    if (hasActionId) this.hasActionId = true;
    if (hasItemId) this.hasItemId = true;
    if (hasCategoryId) this.hasCategoryId = true;
    if (hasRealmId) this.hasRealmId = true;

    // Track if this scope field is always present
    if (!hasSkillId) alwaysHasSkillId = false;
    if (!hasActionId) alwaysHasActionId = false;
    if (!hasItemId) alwaysHasItemId = false;
    if (!hasCategoryId) alwaysHasCategoryId = false;
    if (!hasRealmId) alwaysHasRealmId = false;
  }

  /// Record a value to track its type.
  void recordValue(num value) {
    _hasSeenValue = true;
    // Check if the value has a fractional part
    if (value != value.toInt()) {
      _alwaysInteger = false;
    }
  }
}

void main() async {
  final cache = Cache(cacheDir: defaultCacheDir);

  try {
    print('Loading JSON data files...');
    final demoData = await cache.ensureDemoData();
    final fullData = await cache.ensureFullData();

    // Collect modifier scope information
    final modifierScopes = <String, ModifierScopeInfo>{};
    collectModifierScopes(demoData, modifierScopes);
    collectModifierScopes(fullData, modifierScopes);

    print('Found ${modifierScopes.length} unique modifier names.');

    // Print some stats
    var alwaysItemScoped = 0;
    var alwaysSkillScoped = 0;
    var globalOnly = 0;
    for (final entry in modifierScopes.entries) {
      final info = entry.value;
      if (info.alwaysHasItemId && !info.seenAsScalar) alwaysItemScoped++;
      if (info.alwaysHasSkillId &&
          !info.alwaysHasItemId &&
          !info.seenAsScalar) {
        alwaysSkillScoped++;
      }
      if (info.seenAsScalar &&
          !info.hasSkillId &&
          !info.hasItemId &&
          !info.hasActionId) {
        globalOnly++;
      }
    }
    print('  - Always item-scoped: $alwaysItemScoped');
    print('  - Always skill-scoped (not item): $alwaysSkillScoped');
    print('  - Global only: $globalOnly');

    // Generate the Dart file
    final output = generateDartFile(modifierScopes);

    // Write to lib/src/types/modifier_names.dart
    final outputFile = File('lib/src/types/modifier_names.dart');
    await outputFile.writeAsString(output);

    // Then run dart format on the file
    await Process.run('dart', ['format', outputFile.path]);

    print('Generated: ${outputFile.path}');
  } finally {
    cache.close();
  }
}

/// Recursively collects modifier scope information from a JSON structure.
void collectModifierScopes(
  dynamic json,
  Map<String, ModifierScopeInfo> scopes,
) {
  if (json is Map<String, dynamic>) {
    // Check for modifiers at this level
    final modifiers = json['modifiers'];
    if (modifiers is Map<String, dynamic>) {
      collectModifierScopesFromMap(modifiers, scopes);
    }

    // Also check enemyModifiers and playerModifiers
    final enemyModifiers = json['enemyModifiers'];
    if (enemyModifiers is Map<String, dynamic>) {
      collectModifierScopesFromMap(enemyModifiers, scopes);
    }

    final playerModifiers = json['playerModifiers'];
    if (playerModifiers is Map<String, dynamic>) {
      collectModifierScopesFromMap(playerModifiers, scopes);
    }

    // Recurse into all values
    for (final value in json.values) {
      collectModifierScopes(value, scopes);
    }
  } else if (json is List) {
    for (final item in json) {
      collectModifierScopes(item, scopes);
    }
  }
}

/// Collects modifier scope info from a modifiers map.
void collectModifierScopesFromMap(
  Map<String, dynamic> map,
  Map<String, ModifierScopeInfo> scopes,
) {
  for (final entry in map.entries) {
    final key = entry.key;
    final value = entry.value;

    // Skip special "add" key which contains nested modifiers
    if (key == 'add') {
      if (value is Map<String, dynamic>) {
        collectModifierScopesFromMap(value, scopes);
      }
      continue;
    }

    final info = scopes.putIfAbsent(key, ModifierScopeInfo.new);

    if (value is num) {
      // Scalar modifier - no scope
      info
        ..recordOccurrence(isScalar: true)
        ..recordValue(value);
    } else if (value is List) {
      // Array of scoped entries
      for (final item in value) {
        if (item is Map<String, dynamic>) {
          info.recordOccurrence(
            hasSkillId: item.containsKey('skillID'),
            hasActionId: item.containsKey('actionID'),
            hasItemId: item.containsKey('itemID'),
            hasCategoryId: item.containsKey('categoryID'),
            hasRealmId: item.containsKey('realmID'),
          );
          // Record the value type
          final entryValue = item['value'];
          if (entryValue is num) {
            info.recordValue(entryValue);
          }
        }
      }
    }
  }
}

/// Custom modifier names for equipment stats.
/// These are mapped from equipmentStats keys in EquipmentStats._statToModifier.
/// They don't appear in Melvor JSON but are used for uniform modifier access.
const customEquipmentStatModifiers = [
  'equipmentAttackSpeed',
  'flatStabAttackBonus',
  'flatSlashAttackBonus',
  'flatBlockAttackBonus',
  'flatMeleeStrengthBonus',
  'flatRangedStrengthBonus',
  'flatRangedAttackBonus',
  'flatMagicAttackBonus',
  'flatMeleeDefenceBonus',
  'flatRangedDefenceBonus',
  'flatMagicDefenceBonus',
  'flatResistance',
];

/// Generates the Dart file content with modifier accessor mixin.
String generateDartFile(Map<String, ModifierScopeInfo> scopes) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT')
    ..writeln('//')
    ..writeln('// Generated by: dart run tool/generate_modifier_names.dart')
    ..writeln('//')
    ..writeln('// This file contains:')
    ..writeln('// - ModifierAccessors: typed methods for ModifierProvider')
    ..writeln()
    ..writeln("import 'package:logic/src/data/melvor_id.dart';")
    ..writeln("import 'package:meta/meta.dart';")
    ..writeln()
    // Generate ModifierAccessors mixin for ModifierProvider
    ..writeln('/// Mixin providing typed modifier accessor methods.')
    ..writeln('///')
    ..writeln('/// Generated from Melvor Idle JSON data. Each method wraps')
    ..writeln(
      '/// the internal getModifier() call with appropriate scope parameters.',
    )
    ..writeln('///')
    ..writeln('/// Scope parameters are marked required when the modifier')
    ..writeln('/// always uses that scope field in the source data.')
    ..writeln('mixin ModifierAccessors {')
    ..writeln(
      '  /// Internal method to get a modifier value by name and scope.',
    )
    ..writeln(
      '  /// Implemented by ModifierProvider - walks all modifier sources.',
    )
    ..writeln('  @protected')
    ..writeln('  num getModifier(')
    ..writeln('    String name, {')
    ..writeln('    MelvorId? skillId,')
    ..writeln('    MelvorId? actionId,')
    ..writeln('    MelvorId? itemId,')
    ..writeln('    MelvorId? categoryId,')
    ..writeln('  });')
    ..writeln();

  // Add custom equipment stat modifiers (no scope, global only, always int)
  for (final name in customEquipmentStatModifiers) {
    if (!scopes.containsKey(name)) {
      scopes[name] = ModifierScopeInfo()
        ..recordOccurrence(isScalar: true)
        ..recordValue(0); // Equipment stats are always integers
    }
  }

  // Generate a method for each modifier name from Melvor data
  final melvorNames = scopes.keys.toList()..sort();
  for (final name in melvorNames) {
    final info = scopes[name]!;
    final methodName = lowercaseCamelFromSnake(name);

    // Determine which parameters should be required vs optional
    // A parameter is required if the modifier ALWAYS has that scope field
    // and was never seen as a scalar
    final requireSkillId = info.alwaysHasSkillId && !info.seenAsScalar;
    final requireActionId = info.alwaysHasActionId && !info.seenAsScalar;
    final requireItemId = info.alwaysHasItemId && !info.seenAsScalar;
    final requireCategoryId = info.alwaysHasCategoryId && !info.seenAsScalar;

    // Build parameter list
    final params = <String>[];

    // Required parameters first (no default)
    if (requireSkillId) params.add('required MelvorId skillId');
    if (requireActionId) params.add('required MelvorId actionId');
    if (requireItemId) params.add('required MelvorId itemId');
    if (requireCategoryId) params.add('required MelvorId categoryId');

    // Optional parameters (nullable with no default)
    if (!requireSkillId && info.hasSkillId) params.add('MelvorId? skillId');
    if (!requireActionId && info.hasActionId) params.add('MelvorId? actionId');
    if (!requireItemId && info.hasItemId) params.add('MelvorId? itemId');
    if (!requireCategoryId && info.hasCategoryId) {
      params.add('MelvorId? categoryId');
    }

    // Build the getModifier call arguments
    final args = <String>["'$name'"];
    if (info.hasSkillId || requireSkillId) args.add('skillId: skillId');
    if (info.hasActionId || requireActionId) args.add('actionId: actionId');
    if (info.hasItemId || requireItemId) args.add('itemId: itemId');
    if (info.hasCategoryId || requireCategoryId) {
      args.add('categoryId: categoryId');
    }

    // Determine return type based on observed values
    final returnType = info.alwaysInteger ? 'int' : 'double';
    final getterCall = info.alwaysInteger
        ? 'getModifier(${args.join(', ')}).toInt()'
        : 'getModifier(${args.join(', ')}).toDouble()';

    // Generate the accessor
    if (params.isEmpty) {
      // No parameters - generate as a getter
      buffer.writeln('  $returnType get $methodName => $getterCall;');
    } else {
      // Has parameters - method with named parameters
      buffer
        ..writeln('  $returnType $methodName({${params.join(', ')}}) =>')
        ..writeln('      $getterCall;');
    }
  }

  buffer.writeln('}');

  return buffer.toString();
}
