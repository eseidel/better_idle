import 'dart:io';

import 'cache.dart';
import 'items.dart';
import 'woodcutting.dart';

/// Parsed representation of the Melvor game data.
///
/// Combines data from multiple JSON files (demo + full game).
class MelvorData {
  /// Loads MelvorData from the cache, fetching from CDN if needed.
  static Future<MelvorData> load({Directory? cacheDir}) async {
    final cache = Cache(cacheDir: cacheDir ?? defaultCacheDir);
    try {
      final demoData = await cache.ensureDemoData();
      final fullData = await cache.ensureFullData();
      return MelvorData([demoData, fullData]);
    } finally {
      cache.close();
    }
  }

  /// Creates a MelvorData from multiple parsed JSON data files.
  ///
  /// Items from later files override items from earlier files with the same name.
  /// Skill data from later files is merged with earlier files by skillID.
  MelvorData(List<Map<String, dynamic>> dataFiles) : _rawDataFiles = dataFiles {
    final items = <Item>[];
    for (final json in dataFiles) {
      final namespace = json['namespace'] as String;
      _addDataFromJson(json, namespace: namespace, items: items);
    }
    _items = ItemRegistry(items);
  }

  final List<Map<String, dynamic>> _rawDataFiles;
  late final ItemRegistry _items;
  final Map<String, Map<String, dynamic>> _skillDataById = {};

  /// Returns the item registry.
  ItemRegistry get items => _items;

  /// Returns all raw data files.
  /// Used for accessing skillData and other non-item data.
  List<Map<String, dynamic>> get rawDataFiles => _rawDataFiles;

  void _addDataFromJson(
    Map<String, dynamic> json, {
    required String namespace,
    required List<Item> items,
  }) {
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return;

    // Parse items.
    final itemsJson = data['items'] as List<dynamic>? ?? [];
    for (final itemJson in itemsJson) {
      items.add(Item.fromJson(itemJson, namespace: namespace));
    }

    // Parse skill data.
    final skillData = data['skillData'] as List<dynamic>? ?? [];
    for (final skill in skillData) {
      if (skill is Map<String, dynamic>) {
        final skillId = skill['skillID'] as String?;
        if (skillId != null) {
          final skillContent = skill['data'] as Map<String, dynamic>?;
          if (skillContent != null) {
            // Merge with existing skill data if present.
            final existing = _skillDataById[skillId];
            if (existing != null) {
              _skillDataById[skillId] = _mergeSkillData(existing, skillContent);
            } else {
              _skillDataById[skillId] = Map<String, dynamic>.from(skillContent);
            }
          }
        }
      }
    }
  }

  /// Merges two skill data maps.
  ///
  /// For list values, items from [newer] are appended to [older].
  /// For other values, [newer] values override [older] values.
  Map<String, dynamic> _mergeSkillData(
    Map<String, dynamic> older,
    Map<String, dynamic> newer,
  ) {
    final result = Map<String, dynamic>.from(older);
    for (final entry in newer.entries) {
      final key = entry.key;
      final newValue = entry.value;
      final oldValue = result[key];

      if (oldValue is List && newValue is List) {
        // Append list items.
        result[key] = [...oldValue, ...newValue];
      } else {
        // Override with new value.
        result[key] = newValue;
      }
    }
    return result;
  }

  /// Returns the skill data for the given skill ID, or null if not found.
  ///
  /// Example: `lookupSkillData('melvorD:Woodcutting')` returns the woodcutting
  /// skill data containing trees, pets, rareDrops, etc.
  Map<String, dynamic>? lookupSkillData(String skillId) =>
      _skillDataById[skillId];

  /// Returns all skill IDs in the data.
  Iterable<String> get skillIds => _skillDataById.keys;

  /// Returns the number of skills in the data.
  int get skillCount => _skillDataById.length;
}

/// Extracts woodcutting trees from the skillData array in Melvor JSON.
///
/// The [namespace] parameter specifies the namespace prefix to use for IDs
/// that don't already have one (e.g., "melvorD" for demo data).
List<WoodcuttingTree> extractWoodcuttingTrees(
  Map<String, dynamic> json, {
  required String namespace,
}) {
  // The JSON structure is { "data": { "skillData": [...] } }
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) {
    return [];
  }

  final skillData = data['skillData'] as List<dynamic>?;
  if (skillData == null) {
    return [];
  }

  for (final skill in skillData) {
    if (skill is! Map<String, dynamic>) continue;

    final skillId = skill['skillID'] as String?;
    if (skillId != 'melvorD:Woodcutting') continue;

    final skillContent = skill['data'] as Map<String, dynamic>?;
    if (skillContent == null) continue;

    final trees = skillContent['trees'] as List<dynamic>?;
    if (trees == null) continue;

    return trees
        .whereType<Map<String, dynamic>>()
        .map((json) => WoodcuttingTree.fromJson(json, namespace: namespace))
        .toList();
  }

  return [];
}
