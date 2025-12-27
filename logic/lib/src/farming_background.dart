import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/plot_state.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Result of applying ticks to a farming plot.
typedef FarmingPlotTickResult = ({
  PlotState newState,
  Tick ticksConsumed,
  bool completed,
});

/// Background action for farming plot growth.
///
/// Uses countdown pattern like mining respawn: growthTicksRemaining decrements
/// toward zero as ticks are consumed.
@immutable
class FarmingPlotGrowth {
  FarmingPlotGrowth(this.plotId, this.cropId, this.plotState);

  final MelvorId plotId;
  final ActionId cropId;
  final PlotState plotState;

  /// Whether this plot needs processing (is actively growing).
  bool get isActive => plotState.isGrowing;

  /// Apply ticks to this plot and return the updated state.
  /// Follows countdown pattern: decrement growthTicksRemaining until it reaches 0.
  FarmingPlotTickResult applyTicks(Tick ticks) {
    if (!plotState.isGrowing) {
      return (newState: plotState, ticksConsumed: 0, completed: false);
    }

    final remaining = plotState.growthTicksRemaining!;

    if (ticks >= remaining) {
      // Crop is ready to harvest - set to 0 to mark as ready
      final newState = plotState.copyWith(growthTicksRemaining: 0);
      return (newState: newState, ticksConsumed: ticks, completed: true);
    }

    // Still growing - decrement countdown
    final newState = plotState.copyWith(
      growthTicksRemaining: remaining - ticks,
    );
    return (newState: newState, ticksConsumed: ticks, completed: false);
  }
}
