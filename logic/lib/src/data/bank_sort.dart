import 'package:logic/src/data/melvor_id.dart';

/// The type of insertion for a bank sort entry.
enum BankSortInsertType {
  /// Insert at the start of the sort order (base ordering).
  start,

  /// Insert after a specific item.
  after;

  /// Parses the insert type from a JSON string.
  static BankSortInsertType fromString(String s) {
    return switch (s) {
      'Start' => start,
      'After' => after,
      _ => throw ArgumentError('Unknown insertAt type: $s'),
    };
  }
}

/// A single bank sort order directive from the game data.
///
/// See logic/doc/bank_sort_order.md for details on the data structure.
class BankSortEntry {
  const BankSortEntry({
    required this.insertAt,
    required this.ids,
    this.afterId,
  });

  factory BankSortEntry.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final afterIdJson = json['afterID'] as String?;
    return BankSortEntry(
      insertAt: BankSortInsertType.fromString(json['insertAt'] as String),
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
  final BankSortInsertType insertAt;

  /// The item ID to insert after (only for [BankSortInsertType.after]).
  final MelvorId? afterId;

  /// The item IDs to insert.
  final List<MelvorId> ids;
}

/// Computes the final bank sort order from a list of sort entries.
///
/// Algorithm:
/// 1. Process "Start" entries first - these form the base order
/// 2. Process "After" entries - insert items after their reference item
/// 3. If afterId is not found, items are appended to the end
List<MelvorId> computeBankSortOrder(List<BankSortEntry> entries) {
  final result = <MelvorId>[];

  // Process "Start" entries first (should be exactly one from demo)
  for (final entry in entries) {
    if (entry.insertAt == BankSortInsertType.start) {
      result.addAll(entry.ids);
    }
  }

  // Process "After" entries in order
  for (final entry in entries) {
    if (entry.insertAt == BankSortInsertType.after) {
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

/// Builds a lookup map from item ID to sort index for O(1) lookups.
Map<MelvorId, int> buildBankSortIndex(List<MelvorId> sortOrder) {
  return {for (var i = 0; i < sortOrder.length; i++) sortOrder[i]: i};
}
