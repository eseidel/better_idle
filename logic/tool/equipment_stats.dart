// Equipment Stats Analysis Tool
//
// Parses equipmentStats from all items in the JSON data and shows
// which stat types are used and which are implemented.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:logic/src/data/file_cache.dart';

/// Parses EquipmentStats class to get all known stat keys.
Future<Set<String>> parseKnownStats() async {
  final file = File('lib/src/data/items.dart');
  if (!file.existsSync()) {
    print('Warning: items.dart not found.');
    return {};
  }

  final content = await file.readAsString();
  final stats = <String>{};

  // Match the _statToModifier map entries like: 'stabAttackBonus': 'flat...',
  final mapPattern = RegExp(r"'(\w+)':\s*'");
  for (final match in mapPattern.allMatches(content)) {
    final name = match.group(1);
    if (name != null) {
      stats.add(name);
    }
  }

  return stats;
}

/// Info about an equipment stat found in items.
class EquipmentStatInfo {
  int totalOccurrences = 0;
  final Set<String> itemTypes = {};
  int? minValue;
  int? maxValue;

  void record(String itemType, int value) {
    totalOccurrences++;
    itemTypes.add(itemType);
    minValue = minValue == null
        ? value
        : (value < minValue! ? value : minValue);
    maxValue = maxValue == null
        ? value
        : (value > maxValue! ? value : maxValue);
  }
}

/// Parses equipment stats from an item.
void parseItemEquipmentStats(
  Map<String, dynamic> item,
  Map<String, EquipmentStatInfo> statInfo,
) {
  final stats = item['equipmentStats'] as List<dynamic>?;
  if (stats == null || stats.isEmpty) return;

  final itemType = item['itemType'] as String? ?? 'Unknown';

  for (final stat in stats) {
    if (stat is! Map<String, dynamic>) continue;

    final key = stat['key'] as String?;
    final value = stat['value'] as num?;
    if (key == null || value == null) continue;

    statInfo
        .putIfAbsent(key, EquipmentStatInfo.new)
        .record(itemType, value.toInt());
  }
}

void main() async {
  final cache = FileCache(cacheDir: defaultCacheDir);

  try {
    print('Loading JSON data files...\n');
    final demoData = await cache.ensureDemoData();
    final fullData = await cache.ensureFullData();

    final statInfo = <String, EquipmentStatInfo>{};

    // Process items from both files
    for (final root in [demoData, fullData]) {
      final dataMap = root['data'] as Map<String, dynamic>?;
      if (dataMap == null) continue;

      final items = dataMap['items'] as List<dynamic>?;
      if (items == null) continue;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        parseItemEquipmentStats(item, statInfo);
      }
    }

    // Sort stats by total occurrences (descending)
    final sortedStats = statInfo.entries.toList()
      ..sort(
        (a, b) => b.value.totalOccurrences.compareTo(a.value.totalOccurrences),
      );

    // Get all known stat keys from EquipmentStats class
    final knownStats = await parseKnownStats();
    print('Found ${knownStats.length} known stat keys in EquipmentStats.\n');

    print('=== EQUIPMENT STATS ANALYSIS ===\n');
    print('Total unique stat types: ${statInfo.length}');
    print(
      'Implemented: ${knownStats.intersection(statInfo.keys.toSet()).length}',
    );
    final missing =
        statInfo.length - knownStats.intersection(statInfo.keys.toSet()).length;
    print('Missing: $missing');

    print('\n--- IMPLEMENTED ---\n');
    for (final entry in sortedStats) {
      if (!knownStats.contains(entry.key)) continue;
      _printStat(entry.key, entry.value);
    }

    print('\n--- NOT YET IMPLEMENTED ---\n');
    for (final entry in sortedStats) {
      if (knownStats.contains(entry.key)) continue;
      _printStat(entry.key, entry.value);
    }

    // Write JSON report
    final report = <String, dynamic>{
      'summary': {
        'totalStatTypes': statInfo.length,
        'implemented': knownStats.intersection(statInfo.keys.toSet()).toList(),
        'missing': statInfo.keys.where((k) => !knownStats.contains(k)).toList(),
      },
      'stats': {
        for (final entry in sortedStats)
          entry.key: {
            'occurrences': entry.value.totalOccurrences,
            'itemTypes': entry.value.itemTypes.toList()..sort(),
            'valueRange': {
              'min': entry.value.minValue,
              'max': entry.value.maxValue,
            },
            'implemented': knownStats.contains(entry.key),
          },
      },
    };

    final file = File('equipment_stats_report.json');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(report));
    print('\nJSON report written to: equipment_stats_report.json');
  } finally {
    cache.close();
  }
}

void _printStat(String name, EquipmentStatInfo info) {
  final hasRange = info.minValue != null && info.maxValue != null;
  final valueRange = hasRange ? '[${info.minValue}..${info.maxValue}]' : '';
  print('$name: ${info.totalOccurrences} occurrences $valueRange');
  print('  Item types: ${info.itemTypes.toList()..sort()}');
  print('');
}
