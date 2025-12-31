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
}
```

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
Doubling modifiers (mastery, skill)
  |
  v
Final Rates
```

## Key Concepts

### Base vs Effective Duration

Actions have a base duration, modified by:
- Tool upgrades (e.g., bronze axe -> iron axe)
- Skill masteries
- Global modifiers

```dart
effectiveDuration = baseDuration * durationMultiplier
```

### Item Flows

Items come from:
1. **Action outputs**: Guaranteed items per action
2. **Action drops**: Random drops from the action's drop table
3. **Skill drops**: Random drops based on skill level
4. **Global drops**: Universal random drops

### Consuming Skills

For skills like Firemaking that consume inputs:

```dart
// Find best producer for the input
producerRate = producer.itemsPerTick

// Consumer requires inputs
consumerInputsPerTick = consumer.inputsRequired / consumer.duration

// Sustainable rate = min(produce rate, consume rate)
// But more complex: need to account for coupled cycle time
cycleTime = (inputsNeeded / producerRate) + consumeDuration
sustainableXpPerTick = consumeXp / cycleTime
```

### Thieving Special Case

Thieving has success/failure mechanics:

```dart
successChance = baseChance + skillBonus

// On failure: stunned for N ticks, take damage
expectedTicksPerAttempt =
  successChance * baseDuration +
  (1 - successChance) * (baseDuration + stunDuration)

expectedGpPerAttempt = successChance * gpAmount
gpPerTick = expectedGpPerAttempt / expectedTicksPerAttempt

// HP modeling for death cycles
hpLossPerTick = expectedDamage / expectedTicksPerAttempt
```

## estimateRates() Functions

```dart
/// Estimates rates for the currently active action
Rates estimateRates(GlobalState state)

/// Estimates rates for a specific action (regardless of active action)
Rates estimateRatesForAction(GlobalState state, ActionId actionId)
```

### Parameters

- **state**: Current game state (skill levels, equipment, active action)
  - Registries are accessed via `state.registries`
- **actionId**: (For `estimateRatesForAction`) The specific action to estimate

### Returns

`Rates` object with all flow rates normalized to per-tick values.

### Example

For "Cut Oak Logs" with a 30-tick duration:
- Base XP: 37.5 per action
- Logs: 1 per action
- With iron axe: 27-tick duration

```dart
rates.xpPerTickBySkill[Skill.woodcutting] = 37.5 / 27  // ~1.39 XP/tick
rates.itemFlowsPerTick[oakLogsId] = 1 / 27  // ~0.037 logs/tick
```

## Rate Caching

Rates only depend on:
- Action ID
- Skill levels
- Tool tiers

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

// Default instance used throughout solver
const defaultValueModel = SellEverythingForGpValueModel();
```

This separation keeps rate calculation mechanical while valuation is goal-dependent.
