/// State advancement for the solver.
///
/// Provides both O(1) expected-value advancement and full simulation.
library;

import 'dart:math';

import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/actions.dart' show Skill, SkillAction;
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/types/inventory.dart';

// ---------------------------------------------------------------------------
// Debug invariant assertions
// ---------------------------------------------------------------------------

/// Asserts that the game state is valid (debug only).
///
/// Checks:
/// - GP is non-negative
/// - All inventory item counts are non-negative
/// - Player HP is non-negative
///
/// These assertions catch bugs early: if the solver or simulator produces
/// invalid states, this will fail fast with a clear error message.
void assertValidState(GlobalState state) {
  assert(state.gp >= 0, 'Negative GP: ${state.gp}');
  assert(state.playerHp >= 0, 'Negative HP: ${state.playerHp}');
  for (final stack in state.inventory.items) {
    assert(stack.count >= 0, 'Negative inventory count for ${stack.item.name}');
  }
  for (final entry in state.skillStates.entries) {
    assert(
      entry.value.xp >= 0,
      'Negative XP for ${entry.key}: ${entry.value.xp}',
    );
  }
}

/// Asserts that delta ticks are non-negative (debug only).
void assertNonNegativeDelta(int deltaTicks, String context) {
  assert(deltaTicks >= 0, 'Negative deltaTicks ($deltaTicks) in $context');
}

/// Asserts that progress is monotonic between two states (debug only).
///
/// XP should never decrease, GP can decrease (via purchases).
void assertMonotonicProgress(
  GlobalState before,
  GlobalState after,
  String context,
) {
  for (final skill in before.skillStates.keys) {
    final beforeXp = before.skillState(skill).xp;
    final afterXp = after.skillState(skill).xp;
    assert(
      afterXp >= beforeXp,
      'XP decreased for $skill ($beforeXp -> $afterXp) in $context',
    );
  }
}

/// Result of advancing expected state.
typedef AdvanceResult = ({GlobalState state, int deaths});

/// Checks if an activity can be modeled with expected-value rates.
/// Returns true for non-combat skill activities (including consuming actions).
bool isRateModelable(GlobalState state) {
  final activeAction = state.activeAction;
  if (activeAction == null) return false;

  final action = state.registries.actions.byId(activeAction.id);

  // Only skill actions (non-combat) are rate-modelable
  if (action is! SkillAction) return false;

  return true;
}

/// O(1) expected-value fast-forward for rate-modelable activities.
/// Updates gold and skill XP based on expected rates without full simulation.
///
/// For thieving (activities with death risk), uses a continuous model that
/// incorporates death cycles into the effective rates. This avoids discrete
/// death events that would require activity restarts and cause solver churn.
///
/// Returns the new state and the number of expected deaths.
AdvanceResult advanceExpected(GlobalState state, int deltaTicks) {
  assertNonNegativeDelta(deltaTicks, 'advanceExpected');
  assertValidState(state);

  if (deltaTicks <= 0) return (state: state, deaths: 0);

  final rawRates = estimateRates(state);

  // For activities with death risk, use cycle-adjusted rates.
  // This models the long-run average including death/restart cycles,
  // avoiding discrete death events that would stop the activity.
  final ticksToDeath = ticksUntilDeath(state, rawRates);
  final hasDeathRisk = ticksToDeath != null && ticksToDeath > 0;

  // Use cycle-adjusted rates if there's death risk, otherwise raw rates
  final rates = hasDeathRisk
      ? deathCycleAdjustedRates(state, rawRates)
      : rawRates;

  // GP is NOT updated from item production. Items stay as items in inventory
  // until explicitly sold via SellItems interaction.
  //
  // For affordability checks during planning, use effectiveCredits(state,
  // policy) which computes: state.gp + sellableValue(inventory).
  //
  // This ensures GlobalState.gp always represents actual GP, matching
  // execution.
  final newGp = state.gp;

  // Compute expected skill XP gains
  final newSkillStates = Map<Skill, SkillState>.from(state.skillStates);
  for (final entry in rates.xpPerTickBySkill.entries) {
    final skill = entry.key;
    final xpPerTick = entry.value;
    final xpGain = (xpPerTick * deltaTicks).floor();
    if (xpGain > 0) {
      final current = state.skillState(skill);
      final newXp = current.xp + xpGain;
      newSkillStates[skill] = current.copyWith(xp: newXp);
    }
  }

  // Compute expected mastery XP gains
  var newActionStates = state.actionStates;
  if (rates.masteryXpPerTick > 0 && rates.actionId != null) {
    final masteryXpGain = (rates.masteryXpPerTick * deltaTicks).floor();
    if (masteryXpGain > 0) {
      final actionId = rates.actionId!;
      final currentActionState = state.actionState(actionId);
      final newMasteryXp = currentActionState.masteryXp + masteryXpGain;
      newActionStates = Map.from(state.actionStates);
      newActionStates[actionId] = currentActionState.copyWith(
        masteryXp: newMasteryXp,
      );
    }
  }

  // Estimate expected deaths during this period (for tracking/display)
  final expectedDeaths = hasDeathRisk ? deltaTicks ~/ ticksToDeath : 0;

  // Build currencies map with updated GP
  final newCurrencies = Map<Currency, int>.from(state.currencies);
  newCurrencies[Currency.gp] = newGp;

  // Update inventory with expected item gains
  // This is important for consuming skills where items need to be tracked
  // Skip items not in the registry (e.g., skill drops like Ash)
  var newInventory = state.inventory;
  for (final entry in rates.itemFlowsPerTick.entries) {
    final itemId = entry.key;
    final flowRate = entry.value;
    final expectedCount = (flowRate * deltaTicks).floor();
    if (expectedCount > 0) {
      final item = state.registries.items.byId(itemId);
      newInventory = newInventory.adding(ItemStack(item, count: expectedCount));
    }
  }

  // Subtract consumed items
  for (final entry in rates.itemsConsumedPerTick.entries) {
    final itemId = entry.key;
    final consumeRate = entry.value;
    final consumedCount = (consumeRate * deltaTicks).floor();
    if (consumedCount > 0) {
      final item = state.registries.items.byId(itemId);
      newInventory = newInventory.removing(
        ItemStack(item, count: consumedCount),
      );
    }
  }

  // Note: HP is not tracked in the continuous model - death cycles are
  // absorbed into the rate adjustment. Activity continues without stopping.
  final newState = state.copyWith(
    currencies: newCurrencies,
    skillStates: newSkillStates,
    actionStates: newActionStates,
    inventory: newInventory,
  );

  assertValidState(newState);
  assertMonotonicProgress(state, newState, 'advanceExpected');

  return (state: newState, deaths: expectedDeaths);
}

/// Full simulation advance using consumeTicks.
GlobalState advanceFullSim(
  GlobalState state,
  int deltaTicks, {
  required Random random,
}) {
  if (deltaTicks <= 0) return state;

  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, deltaTicks, random: random);
  return builder.build();
}

/// Advances the game state by a given number of ticks.
/// Uses O(1) expected-value advance for rate-modelable activities,
/// falls back to full simulation for combat/complex activities.
///
/// Only should be used for planning, since it will not perfectly match
/// game state (e.g. won't add inventory items)
///
/// Returns the new state and the number of expected deaths.
AdvanceResult advance(
  GlobalState state,
  int deltaTicks, {
  required Random random,
}) {
  assertNonNegativeDelta(deltaTicks, 'advance');
  assertValidState(state);

  if (deltaTicks <= 0) return (state: state, deaths: 0);

  final AdvanceResult result;
  if (isRateModelable(state)) {
    result = advanceExpected(state, deltaTicks);
  } else {
    result = (
      state: advanceFullSim(state, deltaTicks, random: random),
      deaths: 0,
    );
  }

  assertValidState(result.state);
  assertMonotonicProgress(state, result.state, 'advance');
  return result;
}

/// Advances the game state deterministically by a given number of ticks.
///
/// Always uses O(1) expected-value advance, never falls back to stochastic
/// simulation. Use this for planning/solver where deterministic state
/// projection is required.
///
/// For non-rate-modelable activities (combat), returns the state unchanged
/// with zero deaths - the caller should handle these cases explicitly.
///
/// For execution with actual randomness, use [advance] instead.
AdvanceResult advanceDeterministic(GlobalState state, int deltaTicks) {
  assertNonNegativeDelta(deltaTicks, 'advanceDeterministic');
  assertValidState(state);

  if (deltaTicks <= 0) return (state: state, deaths: 0);

  final AdvanceResult result;
  if (isRateModelable(state)) {
    result = advanceExpected(state, deltaTicks);
  } else {
    // For non-rate-modelable activities, return unchanged state.
    // The caller should handle combat/complex activities explicitly.
    result = (state: state, deaths: 0);
  }

  assertValidState(result.state);
  assertMonotonicProgress(state, result.state, 'advanceDeterministic');
  return result;
}
