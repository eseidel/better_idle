import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// The type of insertion for a display order entry.
enum DisplayOrderInsertType {
  /// Insert at the start of the order (base ordering).
  start,

  /// Insert after a specific item.
  after;

  /// Parses the insert type from a JSON string.
  static DisplayOrderInsertType fromString(String s) {
    return switch (s) {
      'Start' => start,
      'After' => after,
      _ => throw ArgumentError('Unknown insertAt type: $s'),
    };
  }
}

/// A single display order directive from the game data.
///
/// Used for bank item sorting, building display order, and other ordered lists.
@immutable
class DisplayOrderEntry {
  const DisplayOrderEntry({
    required this.insertAt,
    required this.ids,
    this.afterId,
  });

  factory DisplayOrderEntry.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final afterIdJson = json['afterID'] as String?;
    return DisplayOrderEntry(
      insertAt: DisplayOrderInsertType.fromString(json['insertAt'] as String),
      afterId: afterIdJson != null
          ? MelvorId.fromJsonWithNamespace(
              afterIdJson,
              defaultNamespace: namespace,
            )
          : null,
      ids: (json['ids'] as List<dynamic>)
          .map(
            (id) => MelvorId.fromJsonWithNamespace(
              id as String,
              defaultNamespace: namespace,
            ),
          )
          .toList(),
    );
  }

  /// The type of insertion (start or after).
  final DisplayOrderInsertType insertAt;

  /// The item ID to insert after (only for [DisplayOrderInsertType.after]).
  final MelvorId? afterId;

  /// The item IDs to insert.
  final List<MelvorId> ids;
}

/// Computes the final display order from a list of order entries.
///
/// Algorithm:
/// 1. Process "Start" entries first - these form the base order
/// 2. Process "After" entries - insert items after their reference item
/// 3. If afterId is not found, items are appended to the end
List<MelvorId> computeDisplayOrder(List<DisplayOrderEntry> entries) {
  final result = <MelvorId>[];

  // Process "Start" entries first
  for (final entry in entries) {
    if (entry.insertAt == DisplayOrderInsertType.start) {
      result.addAll(entry.ids);
    }
  }

  // Process "After" entries in order
  for (final entry in entries) {
    if (entry.insertAt == DisplayOrderInsertType.after) {
      final afterId = entry.afterId!;
      final index = result.indexOf(afterId);
      if (index != -1) {
        // Insert after the found item
        result.insertAll(index + 1, entry.ids);
      } else {
        // afterId not found - append to end (fallback)
        result.addAll(entry.ids);
      }
    }
  }

  return result;
}

/// Builds a lookup map from ID to sort index for O(1) lookups.
Map<MelvorId, int> buildDisplayOrderIndex(List<MelvorId> displayOrder) {
  return {for (var i = 0; i < displayOrder.length; i++) displayOrder[i]: i};
}
