# Rate Estimation

Rate estimation calculates the expected output per tick for each action. This is the foundation for comparing actions and computing heuristics.

## The Rates Structure

```dart
class Rates {
  final double directGpPerTick;           // Coins from actions (thieving)
  final Map<MelvorId, double> itemFlowsPerTick;  // Items produced
  final Map<MelvorId, double> itemsConsumedPerTick;  // Inputs consumed
  final Map<Skill, double> xpPerTickBySkill;  // XP by skill
  final double masteryXpPerTick;          // Mastery XP
  final double hpLossPerTick;             // HP damage (thieving)
  final double itemTypesPerTick;          // For inventory estimation
  final ActionId? actionId;               // Action these rates are for
}
```

## Design Principle: Flows, Not Value

`estimateRates` is a **mechanical model** returning **expected flows per tick**:
- Direct GP per tick (coins from thieving)
- Items per tick (including drops from tables)
- XP per tick (skill and mastery)
- HP loss per tick (for hazard modeling)

It must NOT encode "sell everything" or any goal policy. Conversion of items → value belongs to `ValueModel`.

Drops are represented in `itemFlowsPerTick` rather than immediately turned into GP. This allows different `ValueModel`s to value items differently.

## Calculation Flow

```
Action
  |
  +-- Base duration (ticks per action)
  |
  +-- Modifiers (upgrades, skill bonuses)
  |
  v
Effective duration
  |
  v
Outputs per action / duration = items/tick
  |
  v
Drop tables (action + skill + global)
  |
  v
Doubling modifiers (from resolveModifiers)
  |
  v
Final Rates
```

## Key Concepts

### Base vs Effective Duration

Actions have a base duration, modified by:
- Tool upgrades (e.g., bronze axe -> iron axe)
- Shop duration modifiers

```dart
final baseExpectedTicks = ticksFromDuration(action.meanDuration).toDouble();
final percentModifier = state.shopDurationModifierForSkill(action.skill);
final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);
```

### Item Flows

Items come from:
1. **Action outputs**: Guaranteed items per action
2. **Action drops**: Random drops from the action's drop table
3. **Skill drops**: Random drops based on skill level
4. **Global drops**: Universal random drops

All drops are computed via `allDropsForAction` which combines all sources.

### Drop Handling

```dart
// allDropsForAction includes:
// - Action outputs (via rewardsForSelection -> rewardsAtLevel)
// - Skill-level drops (e.g., Bobby's Pocket for thieving)
// - Global drops (e.g., gems)
final dropsForAction = registries.drops.allDropsForAction(action, selection);

// Get doubling chance from modifiers
final modifiers = state.resolveModifiers(action);
final doublingChance = (modifiers.skillItemDoublingChance / 100.0).clamp(0.0, 1.0);

final itemFlowsPerAction = expectedItemsForDrops(dropsForAction, doublingChance: doublingChance);
```

### Consuming Skills

For skills like Firemaking that consume inputs:

```dart
// Inputs consumed per tick
final inputs = action.inputsForRecipe(selection);
final itemsConsumedPerTick = <MelvorId, double>{};
for (final entry in inputs.entries) {
  itemsConsumedPerTick[entry.key] = entry.value / expectedTicks;
}
```

### Thieving Special Case

Thieving has success/failure mechanics with stun time:

```dart
final stealth = calculateStealth(thievingLevel, mastery);
final successChance = ((100 + stealth) / (100 + action.perception)).clamp(0.0, 1.0);
final failureChance = 1.0 - successChance;

// Expected gold per attempt (only on success)
final expectedThievingGold = successChance * (1 + action.maxGold) / 2;

// Expected damage per attempt (only on failure)
final expectedDamagePerAttempt = failureChance * (1 + action.maxHit) / 2;

// Effective ticks = action duration + (failure chance * stun)
final effectiveTicks = expectedTicks + failureChance * stunnedDurationTicks;

final directGpPerTick = expectedThievingGold / effectiveTicks;
final hpLossPerTick = expectedDamagePerAttempt / effectiveTicks;

// XP and item drops only on success
final expectedXpPerAction = successChance * action.xp;
final xpPerTick = expectedXpPerAction / effectiveTicks;
```

## estimateRates() Functions

```dart
/// Estimates rates for the currently active action
Rates estimateRates(GlobalState state)

/// Estimates rates for a specific action (regardless of active action)
Rates estimateRatesForAction(GlobalState state, ActionId actionId)
```

### Returns

`Rates` object with all flow rates normalized to per-tick values. Returns `Rates.empty` if no action is active or action is not a `SkillAction`.

### Example

For "Cut Oak Logs" with a 30-tick duration:
- Base XP: 37.5 per action
- Logs: 1 per action
- With iron axe: 27-tick duration

```dart
rates.xpPerTickBySkill[Skill.woodcutting] = 37.5 / 27  // ~1.39 XP/tick
rates.itemFlowsPerTick[oakLogsId] = 1 / 27  // ~0.037 logs/tick
```

## Utility Functions

### Death Cycle Modeling

```dart
/// Computes ticks until death for thieving
int? ticksUntilDeath(GlobalState state, Rates rates)

/// Adjusts rates to account for death cycle overhead
Rates deathCycleAdjustedRates(GlobalState state, Rates rates, {int restartOverheadTicks = 0})
```

### Level-Up Timing

```dart
/// Computes ticks until next skill level
int? ticksUntilNextSkillLevel(GlobalState state, Rates rates)

/// Computes ticks until next mastery level
int? ticksUntilNextMasteryLevel(GlobalState state, Rates rates)
```

## Rate Caching

Rates only depend on:
- Action ID
- Skill levels (affect unlocks)
- Tool tiers (affect durations/yield)

The solver caches `bestUnlockedRate` by state key to avoid recomputation.

## Value Model Layer

Rates are converted to scalar values by `ValueModel`:

```dart
abstract class ValueModel {
  double valuePerTick(GlobalState state, Rates rates);
  double itemValue(GlobalState state, MelvorId itemId);
}

class SellEverythingForGpValueModel extends ValueModel {
  double valuePerTick(GlobalState state, Rates rates) {
    var value = rates.directGpPerTick;
    // Add value from items produced
    for (final entry in rates.itemFlowsPerTick.entries) {
      value += entry.value * itemValue(state, entry.key);
    }
    // Subtract value from items consumed (opportunity cost)
    for (final entry in rates.itemsConsumedPerTick.entries) {
      value -= entry.value * itemValue(state, entry.key);
    }
    return value;
  }

  double itemValue(GlobalState state, MelvorId itemId) {
    return state.registries.items.byId(itemId).sellsFor.toDouble();
  }
}

/// Stub for future shadow-pricing implementation
class ShadowPriceValueModel extends ValueModel { ... }

// Default instance used throughout solver
const defaultValueModel = SellEverythingForGpValueModel();
```

This separation keeps rate calculation mechanical while valuation is goal-dependent.
