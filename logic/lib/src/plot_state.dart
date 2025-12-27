import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'data/action_id.dart';

/// State for an individual farming plot.
@immutable
class PlotState {
  const PlotState({
    this.cropId,
    this.growthTicksRemaining,
    this.compostItems = const [],
  });

  const PlotState.empty() : this();

  factory PlotState.fromJson(ItemRegistry items, Map<String, dynamic> json) {
    final cropIdJson = json['cropId'] as String?;
    final compostItemsJson = json['compostItems'] as List<dynamic>? ?? [];
    final compostItems = compostItemsJson
        .map((id) => items.byId(MelvorId.fromJson(id as String)))
        .toList();
    return PlotState(
      cropId: cropIdJson != null ? ActionId.fromJson(cropIdJson) : null,
      growthTicksRemaining: json['growthTicksRemaining'] as int?,
      compostItems: compostItems,
    );
  }

  /// The crop planted in this plot (null if empty).
  final ActionId? cropId;

  /// Ticks remaining until crop is ready to harvest (null if empty or ready).
  /// Follows the countdown pattern used by mining respawn, stunned, etc.
  final Tick? growthTicksRemaining;

  /// Compost items applied to this plot.
  final List<Item> compostItems;

  /// Compost value applied (0-50). Increases success chance.
  /// Base success chance is 50%, compost adds to it (e.g., 50 compost = 100%).
  int get compostApplied =>
      compostItems.fold(0, (sum, item) => sum + (item.compostValue ?? 0));

  /// Harvest bonus percentage applied (e.g., 10 for +10% harvest quantity).
  int get harvestBonusApplied =>
      compostItems.fold(0, (sum, item) => sum + (item.harvestBonus ?? 0));

  /// Returns true if this plot is empty.
  bool get isEmpty => cropId == null;

  /// Returns true if this plot has a crop growing (not empty and not ready).
  bool get isGrowing =>
      cropId != null &&
      growthTicksRemaining != null &&
      growthTicksRemaining! > 0;

  /// Returns true if this plot is ready to harvest.
  bool get isReadyToHarvest =>
      cropId != null &&
      (growthTicksRemaining == null || growthTicksRemaining == 0);

  PlotState copyWith({
    ActionId? cropId,
    Tick? growthTicksRemaining,
    List<Item>? compostItems,
  }) {
    return PlotState(
      cropId: cropId ?? this.cropId,
      growthTicksRemaining: growthTicksRemaining ?? this.growthTicksRemaining,
      compostItems: compostItems ?? this.compostItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cropId != null) 'cropId': cropId!.toJson(),
      if (growthTicksRemaining != null)
        'growthTicksRemaining': growthTicksRemaining,
      if (compostItems.isNotEmpty)
        'compostItems': compostItems.map((i) => i.id.toJson()).toList(),
    };
  }

  @override
  String toString() =>
      'PlotState(cropId: $cropId, growthTicksRemaining: $growthTicksRemaining)';
}
