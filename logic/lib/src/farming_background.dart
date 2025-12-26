import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/plot_state.dart';
import 'package:logic/src/tick.dart';

/// Result of applying ticks to a farming plot.
typedef FarmingPlotTickResult = ({
  PlotState newState,
  Tick ticksConsumed,
  bool completed,
});

/// Background action for farming plot growth.
///
/// Unlike other skills, farming doesn't use BackgroundTickConsumer since plots
/// grow independently with their own state (not stored in ActionState).
class FarmingPlotGrowth {
  FarmingPlotGrowth(this.plotId, this.cropId, this.plotState, this.currentTick);

  final MelvorId plotId;
  final ActionId cropId;
  final PlotState plotState;
  final Tick currentTick;

  /// Whether this plot needs processing (is actively growing).
  bool get isActive => plotState.isGrowing;

  /// Apply ticks to this plot and return the updated state.
  FarmingPlotTickResult applyTicks(Tick ticks) {
    if (!plotState.isGrowing) {
      return (newState: plotState, ticksConsumed: 0, completed: false);
    }

    final plantedAt = plotState.plantedAtTick;
    if (plantedAt == null) {
      // Should not happen if isGrowing is true
      return (newState: plotState, ticksConsumed: 0, completed: false);
    }

    // Calculate total elapsed ticks from when planted
    final elapsedTicks = currentTick - plantedAt + ticks;
    final growthRequired = plotState.growthTicksRequired;

    if (elapsedTicks >= growthRequired) {
      // Crop is ready to harvest
      final newState = plotState.copyWith(isReadyToHarvest: true);
      return (newState: newState, ticksConsumed: ticks, completed: true);
    }

    // Still growing
    return (newState: plotState, ticksConsumed: ticks, completed: false);
  }
}
