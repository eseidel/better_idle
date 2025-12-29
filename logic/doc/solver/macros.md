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
  skill: Skill.woodcutting,
  primaryStop: StopAtGoal(50),
  watchedStops: [
    StopWhenUpgradeAffordable(ironAxeId),
    StopAtNextBoundary(),
  ],
)
```

**Expansion**:
1. Find best unlocked action for the skill
2. Switch to that action
3. Build composite `WaitForAnyOf` from stop rules
4. Estimate ticks until soonest stop
5. Advance state using expected values

### TrainConsumingSkillUntil

Train a consuming skill (Firemaking, Cooking) with producer-consumer modeling.

```dart
TrainConsumingSkillUntil(
  skill: Skill.firemaking,
  primaryStop: StopAtGoal(30),
  watchedStops: [
    StopWhenInputsDepleted(burnNormalLogsId),
  ],
)
```

**Expansion**:
1. Find best consumer and producer pair
2. Model coupled produce/consume cycle
3. Calculate sustainable XP rate
4. Project both skill XP gains
5. Track inventory for input management

## Stop Rules

Stop rules define when macro execution should pause:

### StopAtNextBoundary

Stop when a new action unlocks (typically at skill level boundaries).

```dart
// For Woodcutting 35: next boundary is 37 (Maple unlocks)
StopAtNextBoundary()
```

### StopAtGoal

Stop when the goal level/XP is reached.

```dart
StopAtGoal(50)  // Stop at level 50
```

### StopWhenUpgradeAffordable

Stop when enough GP to buy an upgrade.

```dart
StopWhenUpgradeAffordable(ironAxeId)
```

### StopWhenInputsDepleted

For consuming skills, stop when inputs run out.

```dart
StopWhenInputsDepleted(burnOakLogsId)
```

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
  final Macro macro;
}
```

During execution, macros run full simulation:

```dart
// In executePlan()
case MacroStep(:final macro):
  state = executeWithAdaptiveWait(state, macro);
```

## Stop Trigger Diagnostics

The solver profiles which stop conditions triggered:

```
Macro stop triggers:
  StopAtNextBoundary: 15
  StopWhenUpgradeAffordable: 8
  StopAtGoal: 3
```

This helps identify planning bottlenecks.
