import 'package:logic/src/data/items.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// The result of opening one or more openable items.
@immutable
class OpenResult {
  const OpenResult({
    required this.openedCount,
    required this.drops,
    this.error,
  });

  /// How many items were successfully opened.
  final int openedCount;

  /// The combined drops from all opened items.
  /// Maps item to total count received.
  final Map<Item, int> drops;

  /// Error message if opening stopped early (e.g., 'Inventory full').
  /// Null if all requested items were opened successfully.
  final String? error;

  /// Whether any items were successfully opened.
  bool get hasDrops => openedCount > 0;

  /// Adds a drop to the result, returning a new OpenResult.
  OpenResult addDrop(ItemStack drop) {
    final newDrops = Map<Item, int>.from(drops);
    newDrops[drop.item] = (newDrops[drop.item] ?? 0) + drop.count;
    return OpenResult(
      openedCount: openedCount + 1,
      drops: newDrops,
      error: error,
    );
  }

  /// Returns a new OpenResult with the given error.
  OpenResult withError(String message) {
    return OpenResult(openedCount: openedCount, drops: drops, error: message);
  }
}
