import 'package:logic/src/data/action_id.dart';
import 'package:meta/meta.dart';

/// State for a single obstacle slot in an agility course.
@immutable
class AgilitySlotState {
  const AgilitySlotState({this.obstacleId, this.purchaseCount = 0});

  const AgilitySlotState.empty() : this();

  factory AgilitySlotState.fromJson(Map<String, dynamic> json) {
    return AgilitySlotState(
      obstacleId: ActionId.maybeFromJson(json['obstacleId']),
      purchaseCount: json['purchaseCount'] as int? ?? 0,
    );
  }

  /// The obstacle built in this slot (null if empty).
  final ActionId? obstacleId;

  /// Number of times an obstacle has been built in this slot.
  /// Each purchase reduces cost by 4%, up to 10 purchases (40% max discount).
  final int purchaseCount;

  /// Returns true if no obstacle is built in this slot.
  bool get isEmpty => obstacleId == null;

  /// Returns true if an obstacle is built in this slot.
  bool get hasObstacle => obstacleId != null;

  /// Returns the cost discount multiplier (0.0 to 0.4).
  /// Each purchase reduces cost by 4%, max 10 purchases.
  double get costDiscount {
    const discountPerPurchase = 0.04;
    const maxPurchases = 10;
    return discountPerPurchase * purchaseCount.clamp(0, maxPurchases);
  }

  AgilitySlotState copyWith({ActionId? obstacleId, int? purchaseCount}) {
    return AgilitySlotState(
      obstacleId: obstacleId ?? this.obstacleId,
      purchaseCount: purchaseCount ?? this.purchaseCount,
    );
  }

  /// Creates a copy with an obstacle built.
  AgilitySlotState withObstacle(ActionId obstacle) {
    return AgilitySlotState(
      obstacleId: obstacle,
      purchaseCount: purchaseCount + 1,
    );
  }

  /// Creates a copy with the obstacle destroyed (keeps purchase count).
  AgilitySlotState destroyed() {
    return AgilitySlotState(purchaseCount: purchaseCount);
  }

  Map<String, dynamic> toJson() {
    return {
      if (obstacleId != null) 'obstacleId': obstacleId!.toJson(),
      if (purchaseCount > 0) 'purchaseCount': purchaseCount,
    };
  }
}

/// State for an agility course, tracking built obstacles in each slot.
///
/// Each slot can have one obstacle built. Building costs resources and
/// unlocks the obstacle's passive modifiers. Running the course completes
/// all built obstacles in sequence.
@immutable
class AgilityState {
  const AgilityState({this.slots = const {}, this.currentObstacleIndex = 0});

  const AgilityState.empty() : this();

  factory AgilityState.fromJson(Map<String, dynamic> json) {
    final slotsJson = json['slots'] as Map<String, dynamic>? ?? {};
    final slots = <int, AgilitySlotState>{};
    for (final entry in slotsJson.entries) {
      final slotIndex = int.parse(entry.key);
      slots[slotIndex] = AgilitySlotState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return AgilityState(
      slots: slots,
      currentObstacleIndex: json['currentObstacleIndex'] as int? ?? 0,
    );
  }

  /// Deserializes an [AgilityState] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static AgilityState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return AgilityState.fromJson(json as Map<String, dynamic>);
  }

  /// State for each obstacle slot, keyed by slot index (0-9 for standard).
  final Map<int, AgilitySlotState> slots;

  /// Index of the obstacle currently being run (0-based).
  /// Reset to 0 when course stops or restarts.
  final int currentObstacleIndex;

  /// Returns the state for a specific slot.
  AgilitySlotState slotState(int slotIndex) {
    return slots[slotIndex] ?? const AgilitySlotState.empty();
  }

  /// Returns true if the specified slot has an obstacle built.
  bool hasObstacle(int slotIndex) {
    return slots[slotIndex]?.hasObstacle ?? false;
  }

  /// Returns the obstacle ID built in the specified slot, or null.
  ActionId? obstacleInSlot(int slotIndex) {
    return slots[slotIndex]?.obstacleId;
  }

  /// Returns a list of all built obstacle IDs in slot order.
  List<ActionId> get builtObstacles {
    final result = <ActionId>[];
    // Iterate through slots in order (0, 1, 2, ...)
    final sortedSlots = slots.keys.toList()..sort();
    for (final slotIndex in sortedSlots) {
      final obstacle = slots[slotIndex]?.obstacleId;
      if (obstacle != null) {
        result.add(obstacle);
      }
    }
    return result;
  }

  /// Returns the number of built obstacles in the course.
  int get builtObstacleCount {
    return slots.values.where((s) => s.hasObstacle).length;
  }

  /// Returns true if no obstacles are built.
  bool get isEmpty => builtObstacleCount == 0;

  /// Returns true if at least one obstacle is built.
  bool get hasAnyObstacle => builtObstacleCount > 0;

  AgilityState copyWith({
    Map<int, AgilitySlotState>? slots,
    int? currentObstacleIndex,
  }) {
    return AgilityState(
      slots: slots ?? this.slots,
      currentObstacleIndex: currentObstacleIndex ?? this.currentObstacleIndex,
    );
  }

  /// Returns a copy with an obstacle built in the specified slot.
  AgilityState withObstacle(int slotIndex, ActionId obstacleId) {
    final currentSlot = slotState(slotIndex);
    final newSlots = Map<int, AgilitySlotState>.from(slots);
    newSlots[slotIndex] = currentSlot.withObstacle(obstacleId);
    return copyWith(slots: newSlots);
  }

  /// Returns a copy with the obstacle in the specified slot destroyed.
  AgilityState withObstacleDestroyed(int slotIndex) {
    final currentSlot = slotState(slotIndex);
    if (currentSlot.isEmpty) return this;
    final newSlots = Map<int, AgilitySlotState>.from(slots);
    newSlots[slotIndex] = currentSlot.destroyed();
    return copyWith(slots: newSlots);
  }

  /// Returns a copy with progress reset to the beginning.
  AgilityState withProgressReset() {
    return copyWith(currentObstacleIndex: 0);
  }

  /// Returns a copy with progress moved to the next obstacle.
  /// Wraps to 0 if at the end of the course.
  AgilityState withNextObstacle() {
    final count = builtObstacleCount;
    if (count == 0) return this;
    final nextIndex = (currentObstacleIndex + 1) % count;
    return copyWith(currentObstacleIndex: nextIndex);
  }

  Map<String, dynamic> toJson() {
    final slotsJson = <String, dynamic>{};
    for (final entry in slots.entries) {
      final slotJson = entry.value.toJson();
      if (slotJson.isNotEmpty) {
        slotsJson[entry.key.toString()] = slotJson;
      }
    }
    return {
      if (slotsJson.isNotEmpty) 'slots': slotsJson,
      if (currentObstacleIndex != 0)
        'currentObstacleIndex': currentObstacleIndex,
    };
  }
}
