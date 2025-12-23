// Modifier System Parser
//
// This tool parses all modifiers from the Melvor Idle JSON data files and
// generates statistics about their structure and usage.
//
// See logic/lib/src/types/modifier.dart for modifier format documentation.

import 'dart:convert';
import 'dart:io';

import 'package:logic/src/data/cache.dart';
import 'package:logic/src/types/modifier.dart';

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
