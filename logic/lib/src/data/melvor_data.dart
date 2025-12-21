import 'dart:io';

import 'cache.dart';

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
    for (final json in dataFiles) {
      _addDataFromJson(json);
    }
  }

  /// Creates a MelvorData from a single parsed JSON file.
  MelvorData.single(Map<String, dynamic> json) : this([json]);

  final List<Map<String, dynamic>> _rawDataFiles;
  final Map<String, Map<String, dynamic>> _itemsByName = {};
  final Map<String, Map<String, dynamic>> _skillDataById = {};

  /// Returns all raw data files.
  /// Used for accessing skillData and other non-item data.
  List<Map<String, dynamic>> get rawDataFiles => _rawDataFiles;

  void _addDataFromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return;

    // Parse items.
    final items = data['items'] as List<dynamic>? ?? [];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final name = item['name'] as String?;
        if (name != null) {
          _itemsByName[name] = item;
        }
      }
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

  /// Returns the item data for the given name, or null if not found.
  Map<String, dynamic>? lookupItem(String name) => _itemsByName[name];

  /// Returns all item names in the data.
  Iterable<String> get itemNames => _itemsByName.keys;

  /// Returns the number of items in the data.
  int get itemCount => _itemsByName.length;

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
