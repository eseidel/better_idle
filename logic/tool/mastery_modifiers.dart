// Mastery Modifier Analysis Tool
//
// Parses masteryLevelBonuses from all skills in the JSON data and shows
// which modifier types are used across all mastery bonuses.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:logic/src/data/cache.dart';

/// Parses modifier_names.dart to get all known modifier names.
Future<Set<String>> parseKnownModifiers() async {
  final file = File('lib/src/types/modifier_names.dart');
  if (!file.existsSync()) {
    print('Warning: modifier_names.dart not found.');
    return {};
  }

  final content = await file.readAsString();
  final modifiers = <String>{};

  // Match getter definitions like: num get modifierName =>
  final getterPattern = RegExp(r'num get (\w+) =>');
  for (final match in getterPattern.allMatches(content)) {
    final name = match.group(1);
    if (name != null) {
      modifiers.add(name);
    }
  }

  return modifiers;
}

/// Scans the codebase to find which modifiers are actually used.
///
/// Looks for patterns like `modifiers.modifierName` in Dart files,
/// filtered against the known modifier names from modifier_names.dart.
Future<Set<String>> findImplementedModifiers(Set<String> knownModifiers) async {
  final implemented = <String>{};
  final libDir = Directory('lib');

  if (!libDir.existsSync()) {
    print('Warning: lib/ directory not found, cannot scan for usage.');
    return implemented;
  }

  // Regular expression to match modifiers.someModifierName
  // Captures the modifier name after the dot
  final modifierUsagePattern = RegExp(r'modifiers\.([a-zA-Z_][a-zA-Z0-9_]*)');

  await for (final entity in libDir.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Skip the generated modifier_names.dart file itself
    if (entity.path.endsWith('modifier_names.dart')) continue;

    final content = await entity.readAsString();
    final matches = modifierUsagePattern.allMatches(content);

    for (final match in matches) {
      final modifierName = match.group(1);
      // Only count it if it's a known modifier name from the data
      if (modifierName != null && knownModifiers.contains(modifierName)) {
        implemented.add(modifierName);
      }
    }
  }

  return implemented;
}

/// Info about a modifier found in mastery bonuses.
class MasteryModifierInfo {
  int totalOccurrences = 0;
  final Set<String> skills = {};
  num? minValue;
  num? maxValue;
  final Set<String> scopePatterns = {};

  void record(String skill, num value, String? scopePattern) {
    totalOccurrences++;
    skills.add(skill);
    minValue = minValue == null
        ? value
        : (value < minValue! ? value : minValue);
    maxValue = maxValue == null
        ? value
        : (value > maxValue! ? value : maxValue);
    if (scopePattern != null) {
      scopePatterns.add(scopePattern);
    }
  }
}

/// Extracts skill name from a MelvorId string.
String extractSkillName(String id) {
  // e.g., "melvorD:Woodcutting" -> "Woodcutting"
  final parts = id.split(':');
  return parts.length > 1 ? parts[1] : id;
}

/// Builds a scope pattern string from a modifier entry.
String? buildScopePattern(Map<String, dynamic> entry) {
  final keys = <String>[];
  if (entry.containsKey('skillID')) keys.add('skillID');
  if (entry.containsKey('actionID')) keys.add('actionID');
  if (entry.containsKey('realmID')) keys.add('realmID');
  if (entry.containsKey('categoryID')) keys.add('categoryID');
  if (entry.containsKey('itemID')) keys.add('itemID');
  if (entry.containsKey('currencyID')) keys.add('currencyID');
  if (entry.containsKey('damageTypeID')) keys.add('damageTypeID');
  if (entry.containsKey('effectGroupID')) keys.add('effectGroupID');
  return keys.isEmpty ? null : keys.join('+');
}

/// Parse mastery bonuses from skill data.
void parseMasteryBonuses(
  Map<String, dynamic> skillData,
  String skillId,
  Map<String, MasteryModifierInfo> modifierInfo,
) {
  final bonuses = skillData['masteryLevelBonuses'] as List<dynamic>?;
  if (bonuses == null) return;

  final skillName = extractSkillName(skillId);

  for (final bonus in bonuses) {
    if (bonus is! Map<String, dynamic>) continue;

    final modifiers = bonus['modifiers'] as Map<String, dynamic>?;
    if (modifiers == null) continue;

    for (final entry in modifiers.entries) {
      final modName = entry.key;
      final info = modifierInfo.putIfAbsent(modName, MasteryModifierInfo.new);

      if (entry.value is num) {
        // Scalar modifier
        info.record(skillName, entry.value as num, null);
      } else if (entry.value is List) {
        // Array modifier
        for (final item in entry.value as List) {
          if (item is Map<String, dynamic>) {
            final value = item['value'] as num?;
            if (value != null) {
              final scopePattern = buildScopePattern(item);
              info.record(skillName, value, scopePattern);
            }
          }
        }
      }
    }
  }
}

void main() async {
  final cache = Cache(cacheDir: defaultCacheDir);

  try {
    print('Loading JSON data files...\n');
    final demoData = await cache.ensureDemoData();
    final fullData = await cache.ensureFullData();

    final modifierInfo = <String, MasteryModifierInfo>{};

    // Process skillData from both files
    // Structure: root > 'data' > 'skillData' > [skill] > 'data' > bonuses
    for (final root in [demoData, fullData]) {
      final dataMap = root['data'] as Map<String, dynamic>?;
      if (dataMap == null) continue;

      final skillData = dataMap['skillData'] as List<dynamic>?;
      if (skillData == null) continue;

      for (final skill in skillData) {
        if (skill is! Map<String, dynamic>) continue;
        final skillId = skill['skillID'] as String?;
        if (skillId == null) continue;

        // Mastery bonuses are nested under skill > data
        final skillNested = skill['data'] as Map<String, dynamic>?;
        if (skillNested == null) continue;

        parseMasteryBonuses(skillNested, skillId, modifierInfo);
      }
    }

    // Sort modifiers by total occurrences (descending)
    final sortedModifiers = modifierInfo.entries.toList()
      ..sort(
        (a, b) => b.value.totalOccurrences.compareTo(a.value.totalOccurrences),
      );

    // Get all known modifier names from modifier_names.dart
    final knownModifiers = await parseKnownModifiers();
    print('Found ${knownModifiers.length} known modifier names.\n');

    // Scan the codebase to find which modifiers are actually used
    print('Scanning codebase for modifier usage...\n');
    final implementedModifiers = await findImplementedModifiers(knownModifiers);

    print('=== MASTERY MODIFIERS ANALYSIS ===\n');
    print('Total unique modifier types: ${modifierInfo.length}');
    print('Implemented: ${implementedModifiers.length}');
    final missing =
        modifierInfo.length -
        implementedModifiers.intersection(modifierInfo.keys.toSet()).length;
    print('Missing: $missing');

    print('\n--- IMPLEMENTED ---\n');
    for (final entry in sortedModifiers) {
      if (!implementedModifiers.contains(entry.key)) continue;
      _printModifier(entry.key, entry.value);
    }

    print('\n--- NOT YET IMPLEMENTED ---\n');
    for (final entry in sortedModifiers) {
      if (implementedModifiers.contains(entry.key)) continue;
      _printModifier(entry.key, entry.value);
    }

    // Write JSON report
    final report = <String, dynamic>{
      'summary': {
        'totalModifierTypes': modifierInfo.length,
        'implemented': implementedModifiers.toList(),
        'missing': modifierInfo.keys
            .where((k) => !implementedModifiers.contains(k))
            .toList(),
      },
      'modifiers': {
        for (final entry in sortedModifiers)
          entry.key: {
            'occurrences': entry.value.totalOccurrences,
            'skills': entry.value.skills.toList()..sort(),
            'valueRange': {
              'min': entry.value.minValue,
              'max': entry.value.maxValue,
            },
            'scopePatterns': entry.value.scopePatterns.toList()..sort(),
            'implemented': implementedModifiers.contains(entry.key),
          },
      },
    };

    final file = File('mastery_modifiers_report.json');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(report));
    print('\nJSON report written to: mastery_modifiers_report.json');
  } finally {
    cache.close();
  }
}

void _printModifier(String name, MasteryModifierInfo info) {
  final hasRange = info.minValue != null && info.maxValue != null;
  final valueRange = hasRange ? '[${info.minValue}..${info.maxValue}]' : '';
  print('$name: ${info.totalOccurrences} occurrences $valueRange');
  print('  Skills: ${info.skills.toList()..sort()}');
  if (info.scopePatterns.isNotEmpty) {
    print('  Scope patterns: ${info.scopePatterns.toList()..sort()}');
  }
  print('');
}
