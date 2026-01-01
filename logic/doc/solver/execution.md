# Plan Execution

Plan execution applies a solver-generated plan to the actual game state, using full simulation rather than expected values.

## Plan Structure

```dart
class Plan {
  final List<PlanStep> steps;
  final int totalTicks;              // Estimated ticks
  final int interactionCount;        // Number of 0-tick steps
  final int expandedNodes;           // A* nodes expanded
  final int enqueuedNodes;           // A* nodes enqueued
  final int expectedDeaths;          // For thieving plans
  final List<SegmentMarker> segmentMarkers;  // Segment boundaries

  Duration get totalDuration;        // Human-readable time
  Plan compress();                   // Merge consecutive waits
  String prettyPrint({...});         // Debug output
}
```

### Segment Markers

Plans may contain segment markers indicating natural stopping points:

```dart
class SegmentMarker {
  final int stepIndex;         // Where this segment starts
  final SegmentBoundary boundary;  // What boundary stops this segment
  final String? description;   // Human-readable description
}
```

Segment boundaries indicate why a segment ended:
- `GoalReachedBoundary` - Goal was reached
- `UpgradeAffordableBoundary` - Upgrade became affordable
- `UnlockBoundary` - Skill level crossed an unlock
- `InputsDepletedBoundary` - Consuming action ran out of inputs
- `HorizonCapBoundary` - Segment reached max tick horizon
- `InventoryPressureBoundary` - Inventory getting full

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
PlanExecutionResult executePlan(
  GlobalState state,
  Plan plan, {
  Random? random,
  bool verbose = false,
})
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
  final String? reason;  // Human-readable description

  bool isSatisfied(GlobalState state) =>
    state.skillState(skill).xp >= targetXp;
}
```

### WaitForEffectiveCredits

Wait until GP + inventory value reaches target:

```dart
class WaitForEffectiveCredits extends WaitFor {
  final int targetValue;
  final String? reason;
  final SellPolicy sellPolicy;  // Policy for computing inventory value

  bool isSatisfied(GlobalState state) =>
    effectiveCredits(state, sellPolicy) >= targetValue;
}
```

### WaitForMasteryXp

Wait until mastery XP for an action reaches target:

```dart
class WaitForMasteryXp extends WaitFor {
  final ActionId actionId;
  final int targetXp;
}
```

### WaitForInventoryThreshold

Wait until inventory usage exceeds a percentage threshold:

```dart
class WaitForInventoryThreshold extends WaitFor {
  final double threshold;  // 0.0 to 1.0
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

### WaitForInputsAvailable

Wait until inputs become available for a consuming action:

```dart
class WaitForInputsAvailable extends WaitFor {
  final ActionId consumingActionId;
  final int minimumInputs;
}
```

### WaitForInventoryAtLeast

Wait until inventory has at least N items of a specific type:

```dart
class WaitForInventoryAtLeast extends WaitFor {
  final MelvorId itemId;
  final int minimumCount;
}
```

### WaitForGoal

Wait until a goal is satisfied:

```dart
class WaitForGoal extends WaitFor {
  final Goal goal;

  bool isSatisfied(GlobalState state) => goal.isSatisfied(state);
}
```

### WaitForAnyOf

Composite: stop when any condition is met:

```dart
class WaitForAnyOf extends WaitFor {
  final List<WaitFor> conditions;

  bool isSatisfied(GlobalState state) =>
    conditions.any((c) => c.isSatisfied(state));

  String get shortDescription;  // Describes first satisfied condition
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

class GoalReached extends ReplanBoundary { ... }
class InputsDepleted extends ReplanBoundary { ... }
class WaitConditionSatisfied extends ReplanBoundary { ... }
class InventoryFull extends ReplanBoundary { ... }
class Death extends ReplanBoundary { ... }
class UpgradeAffordableEarly extends ReplanBoundary { ... }
class UnexpectedUnlock extends ReplanBoundary { ... }
class CannotAfford extends ReplanBoundary { ... }
class ActionUnavailable extends ReplanBoundary { ... }
class NoProgressPossible extends ReplanBoundary { ... }
```

**Expected boundaries** (normal flow):
- `GoalReached` - Plan completed successfully
- `InputsDepleted` - Consuming action ran out of inputs
- `WaitConditionSatisfied` - Normal wait completion

**Unexpected boundaries** (potential bugs):
- `CannotAfford` - Couldn't afford a planned purchase
- `ActionUnavailable` - Action not available when expected
- `NoProgressPossible` - Stuck state

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
[WaitStep(100, waitFor1), WaitStep(50, waitFor2), WaitStep(75, waitFor3)]

// After (merged):
[WaitStep(225, waitFor3)]  // Uses final waitFor since that's the target
```

Compression also removes no-op switches (switching to the same activity).

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
plan.prettyPrint(maxSteps: 30, actions: registries.actions)
```

Output:
```
=== Plan ===
Total ticks: 6500 (1h 48m)
Interactions: 3
Expanded nodes: 150
Enqueued nodes: 500
Steps (6 total):
  1. Switch to Cut Oak Logs (woodcutting)
  2. Cut Oak Logs 25m 0s -> WC 25
  3. Switch to Cut Willow Logs (woodcutting)
  4. Cut Willow Logs 50m 0s -> WC 37
  5. Buy Iron Axe
  6. Cut Willow Logs 33m 20s -> Goal reached
```

## Segment-Based Execution

For online replanning, use `SegmentContext` and `WatchSet`:

```dart
// Build segment context once at segment start
final context = SegmentContext.build(state, goal, config);

// Use same sellPolicy everywhere
final sellPolicy = context.sellPolicy;

// WatchSet detects material boundaries
final boundary = context.watchSet.detectBoundary(state, elapsedTicks: ticks);
if (boundary != null) {
  // Replan at boundary
}
```

The `WatchSet` ensures both planning and execution use identical boundary logic.
