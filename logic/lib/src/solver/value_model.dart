import 'package:logic/src/data/items.dart';
import 'package:logic/src/state.dart';
import 'package:meta/meta.dart';

import 'estimate_rates.dart';

/// Converts flows (from [Rates]) into an objective-specific scalar value.
///
/// Used by the solver for:
/// - Ranking candidate activities
/// - A* heuristic rate bounds
/// - nextDecisionDelta (time-to-goal and affordability projections)
///
/// This abstraction allows the solver to work with different policies
/// (sell everything for GP, shadow pricing, etc.) without changing the
/// core rate estimation logic.
@immutable
abstract class ValueModel {
  const ValueModel();

  /// Converts flows into a scalar "value per tick" for the objective.
  double valuePerTick(GlobalState state, Rates rates);

  /// Per-item valuation (sell price, shadow price, etc.)
  /// Used to compute expected value from item flows.
  double itemValue(GlobalState state, String itemId);
}

/// ValueModel that sells all item outputs at their shop sell price.
///
/// This is the default policy for GP-goal solving: every item produced
/// is immediately sold for its GP value.
@immutable
class SellEverythingForGpValueModel extends ValueModel {
  const SellEverythingForGpValueModel();

  @override
  double itemValue(GlobalState state, String itemId) {
    return itemRegistry.byName(itemId).sellsFor.toDouble();
  }

  @override
  double valuePerTick(GlobalState state, Rates rates) {
    var value = rates.directGpPerTick;
    for (final entry in rates.itemFlowsPerTick.entries) {
      value += entry.value * itemValue(state, entry.key);
    }
    return value;
  }
}

/// Stub ValueModel for future shadow-pricing implementation.
///
/// Currently behaves like [SellEverythingForGpValueModel], but exists
/// to prove the abstraction works and enable future enhancements.
@immutable
class ShadowPriceValueModel extends ValueModel {
  const ShadowPriceValueModel();

  @override
  double itemValue(GlobalState state, String itemId) {
    // TODO(future): Implement shadow pricing based on unlocks/recipes
    // For now, fall back to sell price
    return itemRegistry.byName(itemId).sellsFor.toDouble();
  }

  @override
  double valuePerTick(GlobalState state, Rates rates) {
    var value = rates.directGpPerTick;
    for (final entry in rates.itemFlowsPerTick.entries) {
      value += entry.value * itemValue(state, entry.key);
    }
    return value;
  }
}

/// Default value model for GP-goal solving.
const defaultValueModel = SellEverythingForGpValueModel();
