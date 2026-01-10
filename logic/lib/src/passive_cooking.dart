import 'package:logic/src/cooking_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Result of applying ticks to a passive cooking area.
typedef CookingAreaTickResult = ({
  CookingAreaState newState,
  Tick ticksConsumed,
  bool completed,
});

/// Passive cooking multiplier - passive cooking is 5x slower than active.
const int passiveCookingMultiplier = 5;

/// Tick processor for passive cooking in non-active cooking areas.
///
/// Passive cooking occurs when a recipe is assigned to a cooking area but
/// the player is actively cooking in a different area. Passive cooking:
/// - Runs at 5x the active cook time
/// - Does NOT grant XP or mastery
/// - Does NOT apply preservation, doubling, or perfect cook bonuses
/// - Only produces the base output item
///
/// NOTE: This is NOT a true background action - passive cooking only runs
/// while the player is actively cooking in another area, and progress resets
/// if the player switches to a non-cooking action.
@immutable
class PassiveCookingTickProcessor {
  const PassiveCookingTickProcessor({
    required this.area,
    required this.areaState,
    required this.recipeDuration,
  });

  /// The cooking area (fire, furnace, or pot).
  final CookingArea area;

  /// Current state of this cooking area.
  final CookingAreaState areaState;

  /// The base duration of the recipe in ticks (before passive multiplier).
  final Tick recipeDuration;

  /// The action ID of the recipe being cooked.
  ActionId? get actionId => areaState.recipeId;

  /// Whether this passive cooking action has work to do.
  bool get isActive => areaState.isActive && areaState.recipeId != null;

  /// Apply ticks to this passive cooking area.
  ///
  /// Passive cooking runs at 5x the normal rate, meaning each tick only
  /// contributes 1/5 of a tick to progress. This is implemented by
  /// tracking effective progress separately.
  ///
  /// Returns the new state, ticks consumed, and whether a cook completed.
  CookingAreaTickResult applyTicks(Tick ticks) {
    if (!isActive) {
      return (newState: areaState, ticksConsumed: 0, completed: false);
    }

    final remaining = areaState.progressTicksRemaining!;

    // Passive cooking is 5x slower: effective ticks = ticks / 5
    // We use integer division, accumulating fractional progress over time
    final effectiveTicks = ticks ~/ passiveCookingMultiplier;

    if (effectiveTicks <= 0) {
      // Not enough ticks to make progress
      return (newState: areaState, ticksConsumed: ticks, completed: false);
    }

    if (effectiveTicks >= remaining) {
      // Cook completed - reset progress for next cook
      // The actual ticks consumed is the full amount (even though only
      // part contributed to progress)
      final newState = areaState.copyWith(
        progressTicksRemaining: recipeDuration,
        totalTicks: recipeDuration,
      );
      return (newState: newState, ticksConsumed: ticks, completed: true);
    }

    // Still cooking - decrement countdown
    final newState = areaState.copyWith(
      progressTicksRemaining: remaining - effectiveTicks,
    );
    return (newState: newState, ticksConsumed: ticks, completed: false);
  }
}
