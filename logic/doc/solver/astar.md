# A* Search Algorithm

The solver uses A* search to find the minimum-tick plan to reach a goal.

## Algorithm Overview

```
1. Initialize open set with start node
2. While open set not empty:
   a. Pop node with lowest f(n) = g(n) + h(n)
   b. If goal reached, reconstruct and return plan
   c. Enumerate candidates
   d. Generate edges (interactions + wait)
   e. For each neighbor:
      - Check dominance (skip if dominated)
      - Compute heuristic
      - Add to open set
3. Return failure if goal not reachable
```

## Node Representation

```dart
class SolverNode {
  final GlobalState state;       // Current game state
  final int ticks;               // g(n): ticks elapsed so far
  final int interactions;        // Number of 0-tick actions
  final SolverNode? parent;      // For path reconstruction
  final PlanStep? step;          // How we got here
  final int? heuristic;          // h(n): estimated remaining ticks
}
```

## Priority Queue

Nodes are ordered by f(n) = g(n) + h(n):

```dart
f(node) = node.ticks + node.heuristic
```

Tie-breaker: prefer lower g(n) (actual progress over estimates)

```dart
// If f(a) == f(b), prefer node with lower ticks
// This favors proven progress over optimistic estimates
```

## Heuristic Function

```dart
h(state) = ceil(remaining / bestUnlockedRate)
```

### Properties

- **Admissible**: Never overestimates remaining time
- **Goal-aware**: Uses goal's progress metric
- **Rate-aware**: Uses best rate among unlocked actions

### For Skill Goals

```dart
remaining = targetXp - currentXp
bestRate = maxXpPerTick among unlocked actions for that skill
h = remaining / bestRate
```

### For Multi-Skill Goals

```dart
h = sum of h(subgoal) for each unfinished subgoal
```

### For Consuming Skills

Account for producer throughput:

```dart
sustainableRate = consumerXp / (producerTime + consumerTime)
h = remaining / sustainableRate
```

## Edge Generation

Each node generates two types of edges:

### 1. Interaction Edges (0-tick)

```dart
for candidate in candidates.switchToActivities:
  yield SwitchActivity(candidate)

for upgrade in candidates.buyUpgrades:
  if affordable(upgrade, state):
    yield BuyShopItem(upgrade)

if candidates.sellPolicy != null:
  yield SellItems(candidates.sellPolicy)
```

### 2. Wait Edge (N-tick)

```dart
dt = nextDecisionDelta(state, candidates.watch, goal)
newState = advance(state, dt)
yield WaitStep(dt, waitFor)
```

## Decision Delta Calculation

`nextDecisionDelta()` computes the soonest "interesting" time:

```dart
dt = min(
  timeUntilGoal,
  timeUntilUpgradeAffordable,
  timeUntilActionUnlocks,
  timeUntilInventoryFull,
  timeUntilInputsDepleted,
  timeUntilNextLevel,
  timeUntilNextMasteryBoundary,
)
```

**Key invariant**: dt=0 only if immediate interaction is available

## Dominance Pruning

States are pruned if dominated by another state with:
- Same or fewer ticks AND
- Same or more progress

### Pareto Frontier

For each bucket key, maintain a Pareto frontier of (ticks, progress) points:

```dart
// New point (t, p) is dominated if any existing point (t', p') has:
// t' <= t AND p' >= p

// When adding a point, remove any points it dominates
```

This dramatically reduces the state space.

## State Bucketing

States are grouped by structural features (not exact values):

```dart
bucketKey = hash(
  activeAction,
  goldBucket(gp),         // 50 GP intervals
  skillLevels[relevantSkills],
  toolTiers,
  hpBucket(hp),           // For thieving
  masteryBucket(mastery), // For thieving
  inventoryBucket,        // For consuming skills
)
```

### Goal-Scoped Bucketing

Only track skills relevant to the goal:
- GP goal: all skills (coarse GP bucket)
- Skill goal: only target skill
- Multi-skill goal: only target skills

## Caching

### Rate Cache

```dart
rateCache[stateKey] = bestUnlockedRate

// Key includes:
// - Skill levels (affect unlocks)
// - Tool tiers (affect durations)
```

### Candidate Cache

```dart
candidateCache[stateKey] = candidates

// Disabled during diagnostics to get accurate profiling
```

## Algorithm Performance

Typical metrics:
- Expanded nodes: 100-10,000
- Branching factor: 3-8
- Nodes/second: 1,000-10,000

### Performance Factors

**Good**:
- Macro expansion (reduces branching)
- Dominance pruning (eliminates suboptimal states)
- Tight heuristics (focuses search)

**Bad**:
- Many viable alternatives (high branching)
- Weak heuristics (explores too much)
- Consuming skills (complex producer-consumer modeling)

## solve() Function

```dart
SolverResult solve(
  GlobalState initialState,
  Goal goal,
  {bool collectDiagnostics = false}
)
```

### Returns

```dart
sealed class SolverResult {}

class SolverSuccess extends SolverResult {
  final Plan plan;
  final SolverProfile? profile;
}

class SolverFailed extends SolverResult {
  final SolverFailure failure;
  final SolverProfile? profile;
}
```

### Failure Modes

- `nodeLimit`: Expanded too many nodes
- `emptyQueue`: No path to goal exists
- `zeroRate`: Can't make progress (stuck state)
