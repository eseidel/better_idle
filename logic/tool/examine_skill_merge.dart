import 'package:logic/src/data/cache.dart';

/// Examines what skillData is merged between melvorDemo and melvorFull.
void main() async {
  final cache = Cache(cacheDir: defaultCacheDir);

  try {
    print('Loading demo and full data files...\n');
    final demoData = await cache.ensureDemoData();
    final fullData = await cache.ensureFullData();

    final demoSkillData = _extractSkillData(demoData);
    final fullSkillData = _extractSkillData(fullData);

    print('=== SKILL DATA OVERVIEW ===\n');
    print('Demo namespace: ${demoData['namespace']}');
    print('Full namespace: ${fullData['namespace']}\n');

    print('Skills in Demo: ${demoSkillData.keys.toList()}');
    print('Skills in Full: ${fullSkillData.keys.toList()}\n');

    // Find skills that exist in both
    final commonSkills = demoSkillData.keys
        .where((k) => fullSkillData.containsKey(k))
        .toList();
    final demoOnlySkills = demoSkillData.keys
        .where((k) => !fullSkillData.containsKey(k))
        .toList();
    final fullOnlySkills = fullSkillData.keys
        .where((k) => !demoSkillData.containsKey(k))
        .toList();

    print('Skills in BOTH: $commonSkills');
    print('Skills ONLY in Demo: $demoOnlySkills');
    print('Skills ONLY in Full: $fullOnlySkills\n');

    print('=== MERGE DETAILS FOR COMMON SKILLS ===\n');

    for (final skillId in commonSkills) {
      final demoContent = demoSkillData[skillId]!;
      final fullContent = fullSkillData[skillId]!;

      print('--- $skillId ---');
      print('Demo keys: ${demoContent.keys.toList()}');
      print('Full keys: ${fullContent.keys.toList()}');

      // Find common keys that would be merged
      final commonKeys = demoContent.keys
          .where((k) => fullContent.containsKey(k))
          .toList();

      for (final key in commonKeys) {
        final demoValue = demoContent[key];
        final fullValue = fullContent[key];

        if (demoValue is List && fullValue is List) {
          print(
            '  $key: Demo has ${demoValue.length} items, '
            'Full has ${fullValue.length} items -> MERGED (${demoValue.length + fullValue.length} total)',
          );

          // Show some example items if they have names/ids
          _showListExamples(key, demoValue, fullValue);
        } else {
          print(
            '  $key: Demo=$demoValue, Full=$fullValue -> OVERRIDDEN by Full',
          );
        }
      }

      // Keys only in full (added)
      final fullOnlyKeys = fullContent.keys
          .where((k) => !demoContent.containsKey(k))
          .toList();
      if (fullOnlyKeys.isNotEmpty) {
        print('  Keys only in Full (added): $fullOnlyKeys');
      }

      print('');
    }

    // Detailed look at specific skill
    print('=== DETAILED EXAMPLE: Woodcutting Trees ===\n');
    _showDetailedMerge(
      demoSkillData,
      fullSkillData,
      'melvorD:Woodcutting',
      'trees',
    );

    print('=== DETAILED EXAMPLE: Mining Rocks ===\n');
    _showDetailedMerge(
      demoSkillData,
      fullSkillData,
      'melvorD:Mining',
      'rockData',
    );

    print('=== DETAILED EXAMPLE: Fishing ===\n');
    _showDetailedMerge(demoSkillData, fullSkillData, 'melvorD:Fishing', 'fish');
    _showDetailedMerge(
      demoSkillData,
      fullSkillData,
      'melvorD:Fishing',
      'areas',
    );
  } finally {
    cache.close();
  }
}

Map<String, Map<String, dynamic>> _extractSkillData(Map<String, dynamic> json) {
  final result = <String, Map<String, dynamic>>{};
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) return result;

  final skillData = data['skillData'] as List<dynamic>? ?? [];
  for (final skill in skillData) {
    if (skill is Map<String, dynamic>) {
      final skillId = skill['skillID'] as String?;
      final skillContent = skill['data'] as Map<String, dynamic>?;
      if (skillId != null && skillContent != null) {
        result[skillId] = skillContent;
      }
    }
  }
  return result;
}

void _showListExamples(
  String key,
  List<dynamic> demoList,
  List<dynamic> fullList,
) {
  String getName(dynamic item) {
    if (item is Map<String, dynamic>) {
      return item['name'] as String? ??
          item['id'] as String? ??
          item.keys.first;
    }
    return item.toString();
  }

  if (demoList.isNotEmpty) {
    final demoNames = demoList.take(3).map(getName).toList();
    print('    Demo examples: $demoNames${demoList.length > 3 ? '...' : ''}');
  }
  if (fullList.isNotEmpty) {
    final fullNames = fullList.take(3).map(getName).toList();
    print('    Full examples: $fullNames${fullList.length > 3 ? '...' : ''}');
  }
}

void _showDetailedMerge(
  Map<String, Map<String, dynamic>> demoSkillData,
  Map<String, Map<String, dynamic>> fullSkillData,
  String skillId,
  String listKey,
) {
  final demoContent = demoSkillData[skillId];
  final fullContent = fullSkillData[skillId];

  if (demoContent == null && fullContent == null) {
    print('$skillId not found in either file\n');
    return;
  }

  final demoList = (demoContent?[listKey] as List<dynamic>?) ?? [];
  final fullList = (fullContent?[listKey] as List<dynamic>?) ?? [];

  print('$skillId -> $listKey:');
  print('  Demo (${demoList.length} items):');
  for (final item in demoList) {
    if (item is Map<String, dynamic>) {
      final name = item['name'] ?? item['id'] ?? 'unknown';
      final id = item['id'] ?? '';
      print('    - $name ($id)');
    }
  }

  print('  Full (${fullList.length} items):');
  for (final item in fullList) {
    if (item is Map<String, dynamic>) {
      final name = item['name'] ?? item['id'] ?? 'unknown';
      final id = item['id'] ?? '';
      print('    - $name ($id)');
    }
  }

  print('  MERGED TOTAL: ${demoList.length + fullList.length} items\n');
}
