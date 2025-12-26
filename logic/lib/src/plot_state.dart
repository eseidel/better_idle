import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'data/action_id.dart';

/// State for an individual farming plot.
@immutable
class PlotState {
  const PlotState({
    this.cropId,
    this.plantedAtTick,
    this.growthTicksRequired = 0,
    this.compostApplied = 0,
    this.isReadyToHarvest = false,
  });

  const PlotState.empty() : this();

  factory PlotState.fromJson(Map<String, dynamic> json) {
    final cropIdJson = json['cropId'] as String?;
    return PlotState(
      cropId: cropIdJson != null ? ActionId.fromJson(cropIdJson) : null,
      plantedAtTick: json['plantedAtTick'] as int?,
      growthTicksRequired: json['growthTicksRequired'] as int? ?? 0,
      compostApplied: json['compostApplied'] as int? ?? 0,
      isReadyToHarvest: json['isReadyToHarvest'] as bool? ?? false,
    );
  }

  /// The crop planted in this plot (null if empty).
  final ActionId? cropId;

  /// When the crop was planted (null if empty).
  final Tick? plantedAtTick;

  /// Total growth time required in ticks.
  final Tick growthTicksRequired;

  /// Compost value applied (0-80, each 10 = +10% harvest).
  final int compostApplied;

  /// Whether the crop is ready to harvest.
  final bool isReadyToHarvest;

  /// Returns true if this plot is empty.
  bool get isEmpty => cropId == null;

  /// Returns true if this plot has a crop growing.
  bool get isGrowing => cropId != null && !isReadyToHarvest;

  PlotState copyWith({
    ActionId? cropId,
    Tick? plantedAtTick,
    Tick? growthTicksRequired,
    int? compostApplied,
    bool? isReadyToHarvest,
  }) {
    return PlotState(
      cropId: cropId ?? this.cropId,
      plantedAtTick: plantedAtTick ?? this.plantedAtTick,
      growthTicksRequired: growthTicksRequired ?? this.growthTicksRequired,
      compostApplied: compostApplied ?? this.compostApplied,
      isReadyToHarvest: isReadyToHarvest ?? this.isReadyToHarvest,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cropId != null) 'cropId': cropId!.toJson(),
      if (plantedAtTick != null) 'plantedAtTick': plantedAtTick,
      'growthTicksRequired': growthTicksRequired,
      'compostApplied': compostApplied,
      'isReadyToHarvest': isReadyToHarvest,
    };
  }

  @override
  String toString() =>
      'PlotState(cropId: $cropId, isReadyToHarvest: $isReadyToHarvest)';
}
