import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'data/action_id.dart';

/// State for an individual farming plot.
@immutable
class PlotState {
  const PlotState({
    this.cropId,
    this.growthTicksRemaining,
    this.compostApplied = 0,
  });

  const PlotState.empty() : this();

  factory PlotState.fromJson(Map<String, dynamic> json) {
    final cropIdJson = json['cropId'] as String?;
    return PlotState(
      cropId: cropIdJson != null ? ActionId.fromJson(cropIdJson) : null,
      growthTicksRemaining: json['growthTicksRemaining'] as int?,
      compostApplied: json['compostApplied'] as int? ?? 0,
    );
  }

  /// The crop planted in this plot (null if empty).
  final ActionId? cropId;

  /// Ticks remaining until crop is ready to harvest (null if empty or ready).
  /// Follows the countdown pattern used by mining respawn, stunned, etc.
  final Tick? growthTicksRemaining;

  /// Compost value applied (0-80, each 10 = +10% harvest).
  final int compostApplied;

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
    int? compostApplied,
  }) {
    return PlotState(
      cropId: cropId ?? this.cropId,
      growthTicksRemaining: growthTicksRemaining ?? this.growthTicksRemaining,
      compostApplied: compostApplied ?? this.compostApplied,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cropId != null) 'cropId': cropId!.toJson(),
      if (growthTicksRemaining != null)
        'growthTicksRemaining': growthTicksRemaining,
      'compostApplied': compostApplied,
    };
  }

  @override
  String toString() =>
      'PlotState(cropId: $cropId, growthTicksRemaining: $growthTicksRemaining)';
}
