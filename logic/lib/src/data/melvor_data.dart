/// Parsed representation of the Melvor game data.
///
/// Combines data from multiple JSON files (demo + full game).
class MelvorData {
  /// Creates a MelvorData from multiple parsed JSON data files.
  ///
  /// Items from later files override items from earlier files with the same name.
  MelvorData(List<Map<String, dynamic>> dataFiles) {
    for (final json in dataFiles) {
      _addItemsFromJson(json);
    }
  }

  /// Creates a MelvorData from a single parsed JSON file.
  MelvorData.single(Map<String, dynamic> json) : this([json]);

  final Map<String, Map<String, dynamic>> _itemsByName = {};

  void _addItemsFromJson(Map<String, dynamic> json) {
    final items = json['data']?['items'] as List<dynamic>? ?? [];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final name = item['name'] as String?;
        if (name != null) {
          _itemsByName[name] = item;
        }
      }
    }
  }

  /// Returns the item data for the given name, or null if not found.
  Map<String, dynamic>? lookupItem(String name) => _itemsByName[name];

  /// Returns all item names in the data.
  Iterable<String> get itemNames => _itemsByName.keys;

  /// Returns the number of items in the data.
  int get itemCount => _itemsByName.length;
}
