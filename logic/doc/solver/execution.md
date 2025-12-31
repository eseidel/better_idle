# Plan Execution

Plan execution applies a solver-generated plan to the actual game state, using full simulation rather than expected values.

## Plan Structure

```dart
class Plan {
  final List<PlanStep> steps;
  final int totalTicks;          // Estimated ticks
  final int interactionCount;    // Number of 0-tick steps
  final int expandedNodes;       // A* nodes expanded
  final int enqueuedNodes;       // A* nodes enqueued
  final int expectedDeaths;      // For thieving plans

  Duration get totalDuration;    // Human-readable time
  Plan compress();               // Merge consecutive waits
  String prettyPrint({...});     // Debug output
}
```

## Step Types

### InteractionStep

A 0-tick state change:

```dart
class InteractionStep extends PlanStep {
  final Interaction interaction;
}

// Interactions:
// - SwitchActivity(actionId)
// - BuyShopItem(purchaseId)
// - SellItems(policy)
```

### WaitStep

Advance time until a condition is met:

```dart
class WaitStep extends PlanStep {
  final int deltaTicks;   // Estimated ticks
  final WaitFor waitFor;  // Stop condition
}
```

### MacroStep

Execute a macro (training sequence):

```dart
class MacroStep extends PlanStep {
  final MacroCandidate macro;
  final int deltaTicks;   // Estimated ticks
  final WaitFor waitFor;  // Composite stop condition
}
```

## executePlan() Function

```dart
ExecutionResult executePlan(
  GlobalState state,
  Plan plan,
  {Random? random}
)
```

### Execution Loop

```dart
for (final step in plan.steps) {
  switch (step) {
    case InteractionStep(:final interaction):
      // Apply immediately (0 ticks)
      state = interaction.apply(state);

    case WaitStep(:final waitFor, :final plannedTicks):
      // Run simulation until condition met
      final result = consumeUntil(state, waitFor, random);
      state = result.state;
      actualTicks += result.ticks;
      plannedTicks += step.plannedTicks;

    case MacroStep(:final macro):
      // Execute macro with adaptive waiting
      state = executeMacro(state, macro, random);
  }
}
```

## Wait Conditions

### WaitForSkillXp

Wait until skill XP reaches target:

```dart
class WaitForSkillXp extends WaitFor {
  final Skill skill;
  final int targetXp;

  bool isSatisfied(GlobalState state) =>
    state.skillState(skill).xp >= targetXp;
}
```

### WaitForInventoryValue

Wait until GP + inventory value reaches target:

```dart
class WaitForInventoryValue extends WaitFor {
  final int targetValue;

  bool isSatisfied(GlobalState state) =>
    state.gp + state.inventory.sellValue >= targetValue;
}
```

### WaitForInventoryFull

Wait until inventory is full:

```dart
class WaitForInventoryFull extends WaitFor {
  bool isSatisfied(GlobalState state) =>
    state.inventory.isFull;
}
```

### WaitForInputsDepleted

For consuming skills, wait until inputs run out:

```dart
class WaitForInputsDepleted extends WaitFor {
  final ActionId actionId;

  bool isSatisfied(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    return !state.canStartAction(action);
  }
}
```

### WaitForAnyOf

Composite: stop when any condition is met:

```dart
class WaitForAnyOf extends WaitFor {
  final List<WaitFor> conditions;

  bool isSatisfied(GlobalState state) =>
    conditions.any((c) => c.isSatisfied(state));
}
```

## Execution Result

```dart
class PlanExecutionResult {
  final GlobalState finalState;
  final int plannedTicks;    // What solver estimated
  final int actualTicks;     // What actually happened
  final int totalDeaths;     // Deaths during execution
  final List<ReplanBoundary> boundariesHit;  // Boundaries encountered

  int get ticksDelta => actualTicks - plannedTicks;
  bool get hasUnexpectedBoundaries;
  List<ReplanBoundary> get unexpectedBoundaries;
  List<ReplanBoundary> get expectedBoundaries;
}
```

### ReplanBoundary

Indicates when execution hit a point requiring replanning:

```dart
sealed class ReplanBoundary {
  bool get isExpected;  // Expected during normal flow
}

class InputsDepleted extends ReplanBoundary { ... }
class WaitConditionSatisfied extends ReplanBoundary { ... }
class GoalReached extends ReplanBoundary { ... }
// etc.
```

## Planning vs Execution Difference

| Aspect | Planning (solve) | Execution |
|--------|------------------|-----------|
| Time model | Expected values | Full simulation |
| Randomness | None (expected) | Actual RNG |
| Deaths | Expected count | Actual count |
| Speed | O(1) advance | O(ticks) simulation |

### Why the Difference?

- **Planning**: Needs to be fast, explore many alternatives
- **Execution**: Needs to be accurate, happens once

### Typical Delta

The delta between planned and actual ticks is usually small:
- Positive delta: Took longer (bad luck, more deaths)
- Negative delta: Took less time (good luck)

For non-random actions (woodcutting, etc.), delta should be ~0.

## Plan Compression

`plan.compress()` merges consecutive wait steps:

```dart
// Before:
[Wait(100), Wait(50), Wait(75)]

// After:
[Wait(225)]
```

This makes plans more readable and slightly faster to execute.

## Deterministic Execution

For testing, use a seeded random:

```dart
final result = executePlan(
  state,
  plan,
  random: Random(42),  // Deterministic
);
```

This ensures reproducible results.

## Death Handling

For thieving plans, deaths are expected:

```dart
// During planning
plan.expectedDeaths = deathRate * totalTicks

// During execution
if (player.hp <= 0) {
  totalDeaths++;
  state = state.respawn();  // Reset HP, minor penalty
}
```

The solver accounts for death overhead in rate calculations.

## Pretty Printing

```dart
plan.prettyPrint(actions: registries.actions)
```

Output:
```
1. Switch to Cut Oak Logs
2. Wait 1500 ticks (until Woodcutting 25)
3. Switch to Cut Willow Logs
4. Wait 3000 ticks (until Woodcutting 37)
5. Buy Iron Axe
6. Wait 2000 ticks (until goal)
Total: 6500 ticks, 3 interactions
```
