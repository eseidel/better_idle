# Macros

Macros are high-level planning primitives that allow the solver to reason about extended training periods without expanding every intermediate state.

## Why Macros?

Without macros, training Woodcutting to level 50 would require:
- Thousands of individual wait steps
- Branching at every level-up
- Massive state space expansion

With macros:
- Single "train until level 50" step
- Branches only at meaningful boundaries (new action unlocks, upgrades affordable)
- Orders of magnitude fewer nodes

## Macro Types

### TrainSkillUntil

Train a skill using the best available action until a condition is met.

```dart
TrainSkillUntil(
  Skill.woodcutting,
  StopAtGoal(Skill.woodcutting, targetXp),
  watchedStops: [
    StopWhenUpgradeAffordable(ironAxeId, cost, 'Iron Axe'),
    StopAtNextBoundary(Skill.woodcutting),
  ],
  actionId: specificActionId,  // Optional: use specific action
)
```

**Fields**:
- `skill`: The skill to train
- `primaryStop`: Main stop condition
- `watchedStops`: Additional stop conditions
- `actionId`: Optional specific action (if null, finds best)

**Expansion**:
1. Find best unlocked action for the skill (or use specified actionId)
2. Switch to that action
3. Build composite `WaitForAnyOf` from stop rules
4. Estimate ticks until soonest stop
5. Advance state using expected values

### TrainConsumingSkillUntil

Train a consuming skill (Firemaking, Cooking, Smithing) with producer-consumer modeling.

```dart
TrainConsumingSkillUntil(
  Skill.firemaking,
  StopAtGoal(Skill.firemaking, targetXp),
  watchedStops: [
    StopWhenInputsDepleted(),  // Uses active action at execution time
  ],
)
```

**Fields**:
- `consumingSkill`: The consuming skill to train
- `primaryStop`: Main stop condition
- `watchedStops`: Additional stop conditions

**Expansion**:
1. Find best consumer and producer pair
2. Model coupled produce/consume cycle
3. Calculate sustainable XP rate
4. Project both skill XP gains
5. Track inventory for input management

### AcquireItem

Acquire a specific quantity of an item via the best producing action.

```dart
AcquireItem(
  itemId: MelvorId('melvorD:Oak_Logs'),
  quantity: 100,
)
```

**Fields**:
- `itemId`: The item to acquire
- `quantity`: How many to produce

**Use case**: Building up input stock for consuming skills, or acquiring items for goals.

### EnsureStock

Ensure minimum inventory level of an item before proceeding. Different from `AcquireItem` in that it specifies an absolute target, not a delta.

```dart
EnsureStock(
  itemId: MelvorId('melvorD:Oak_Logs'),
  minTotal: 50,  // Ensure at least 50 in inventory
)
```

**Fields**:
- `itemId`: The item to stock
- `minTotal`: Minimum quantity to have in inventory

**Use case**: Pre-flight checks before consuming skills, ensuring inputs are available.

## Stop Rules (MacroStopRule)

Stop rules define when macro execution should pause. Each rule can convert itself
to a `WaitFor` condition for plan execution.

```dart
sealed class MacroStopRule {
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries);
}
```

### StopAtNextBoundary

Stop when a new action unlocks (typically at skill level boundaries).

```dart
// For Woodcutting 35: next boundary is 37 (Maple unlocks)
StopAtNextBoundary(Skill.woodcutting)
```

Converts to: `WaitForSkillXp(skill, targetXp, reason: 'Boundary L$level')`

### StopAtGoal

Stop when the goal XP is reached.

```dart
StopAtGoal(Skill.woodcutting, targetXp)  // Stop at target XP
```

Converts to: `WaitForSkillXp(skill, targetXp, reason: 'Goal reached')`

### StopWhenUpgradeAffordable

Stop when enough effective credits to buy an upgrade.

```dart
StopWhenUpgradeAffordable(ironAxeId, cost, 'Iron Axe', sellPolicy)
```

**Fields**:
- `purchaseId`: The upgrade ID
- `cost`: GP cost of the upgrade
- `upgradeName`: Human-readable name
- `sellPolicy`: Policy for computing effective credits

Converts to: `WaitForEffectiveCredits(cost, reason: upgradeName, sellPolicy: sellPolicy)`

### StopWhenInputsDepleted

For consuming skills, stop when inputs run out. Uses the currently active action
at execution time (not a fixed action ID).

```dart
StopWhenInputsDepleted()  // Parameterless
```

Converts to: `WaitForInputsDepleted(state.activeAction.id)`

## Macro Expansion Process

```dart
GlobalState expandMacro(
  GlobalState state,
  Macro macro,
  Registries registries,
) {
  // 1. Switch to best action
  final action = findBestAction(state, macro.skill);
  state = SwitchActivity(action).apply(state);

  // 2. Build composite wait condition
  final waitFor = WaitForAnyOf([
    macro.primaryStop.toWaitFor(state),
    ...macro.watchedStops.map((s) => s.toWaitFor(state)),
  ]);

  // 3. Estimate ticks
  final rates = estimateRates(state, action, registries);
  final dt = waitFor.estimateTicks(state, rates);

  // 4. Advance state
  return advance(state, dt, rates);
}
```

## Consuming Skill Cycle Model

For Firemaking, the cycle is:
1. Cut logs (producer phase)
2. Burn logs (consumer phase)
3. Repeat

```
Time: |---produce---|---consume---|---produce---|---consume---|
Logs: 0 → 5 → 10 → 15 → 10 → 5 → 0 → 5 → 10 → 15 → 10 → ...
```

### Sustainable Rate Calculation

```dart
// Producer: makes P items in Tp ticks
// Consumer: needs I items, takes Tc ticks, gives X XP

cycleTime = (I / P) * Tp + Tc
sustainableXpPerTick = X / cycleTime

// Example: Cut oak (30 ticks) + burn oak (15 ticks, needs 1 log)
cycleTime = 30 + 15 = 45 ticks
sustainableXp = burnXp / 45
```

### Producer XP Bonus

While training a consuming skill, you also gain producer XP:

```dart
producerXpPerCycle = (I / P) * producerXpPerAction
```

This is tracked separately for multi-skill goals.

## Macro vs Direct Planning

| Aspect | Direct (Micro) | Macro |
|--------|----------------|-------|
| Granularity | Tick-by-tick | Boundary-to-boundary |
| Branching | High (every level) | Low (key points) |
| Precision | Exact | Expected value |
| Use case | Short sequences | Extended training |

## Integration with A*

Macros are treated as special edges in the A* graph:

```dart
// Generate macro candidates
for (final macro in candidates.macros) {
  final newState = expandMacro(state, macro);
  final step = MacroStep(macro);
  addNeighbor(newState, step);
}

// Macro steps are 0-tick in planning (time in the wait)
// But expand to many ticks during execution
```

## Plan Representation

In the plan, macros appear as `MacroStep`:

```dart
class MacroStep extends PlanStep {
  final MacroCandidate macro;
  final int deltaTicks;   // Estimated ticks
  final WaitFor waitFor;  // Composite WaitForAnyOf condition
}
```

During execution, macros run full simulation using the composite wait condition.

### Macro Augmentation

Macros are augmented with upgrade stops based on the watch list:

```dart
final augmentedMacros = _augmentMacrosWithUpgradeStops(
  macros,
  upgradeResult.watchedUpgrades,
  sellPolicy,
);
```

This allows macros to break early when valuable upgrades become affordable.

## Stop Trigger Diagnostics

The solver profiles which stop conditions triggered:

```
Macro stop triggers:
  StopAtNextBoundary: 15
  StopWhenUpgradeAffordable: 8
  StopAtGoal: 3
```

This helps identify planning bottlenecks.
