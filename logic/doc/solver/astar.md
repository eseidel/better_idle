# A* Search Algorithm

The solver uses A* search to find the minimum-tick plan to reach a goal.

## Key Pipeline Invariant

**Watch lists affect only waiting, never imply we should take an action.**

An upgrade being "watched" (for affordability timing) does NOT mean we should buy it. Only upgrades in `Candidates.buyUpgrades` are actionable.

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

Uses `getBestRateForSkill()` to compute per-skill estimates.

### For Consuming Skills

Account for producer throughput to keep heuristic admissible but less optimistic:

```dart
// For each unlocked consumer, find best producer and cap rate
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

if candidates.shouldEmitSellCandidate && goal.isSellRelevant:
  yield SellItems(candidates.sellPolicy)
```

Interactions are generated via `availableInteractions()` which checks:
- Action is unlocked
- Not already on that action
- Can afford purchase
- Has inventory to sell

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
  timeUntilUpgradeAffordable,     // From watch.upgradePurchaseIds
  timeUntilActionUnlocks,         // From watch.lockedActivityIds
  timeUntilInventoryFull,         // If watch.inventory
  timeUntilInputsDepleted,        // For consuming actions
  timeUntilInputsAvailable,       // For watch.consumingActivityIds
  timeUntilNextLevel,
  timeUntilNextMasteryBoundary,
  timeUntilDeath,                 // For thieving
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
class _BucketKey {
  final String activityName;
  final Map<Skill, int> skillLevels;  // Goal-relevant only
  final int axeLevel;
  final int rodLevel;
  final int pickLevel;
  final int hpBucket;         // For thieving (if shouldTrackHp)
  final int masteryLevel;     // For thieving (if shouldTrackMastery)
  final int inventoryBucket;  // For consuming skills (if shouldTrackInventory)
}
```

Bucket sizes:
- Gold: 50 GP intervals (`_goldBucketSize`)
- HP: 10 HP intervals (`_hpBucketSize`)
- Inventory: 10 item intervals (`_inventoryBucketSize`)

### Goal-Scoped Bucketing

Only track skills relevant to the goal:
- GP goal: all skills (coarse GP bucket)
- Skill goal: only target skill
- Multi-skill goal: only target skills

## Debug Assertions

The solver includes debug-only assertions that catch bugs early:

```dart
// Check state validity (non-negative GP, HP, inventory)
_assertValidState(state);

// Check delta ticks are non-negative
_assertNonNegativeDelta(deltaTicks, context);

// Check progress is monotonic (XP never decreases)
_assertMonotonicProgress(before, after, context);
```

## Caching

### Rate Cache

```dart
class _RateCache {
  double getBestUnlockedRate(GlobalState state);
  double getBestRateForSkill(GlobalState state, Skill targetSkill);
  RateZeroReason? getZeroReason(GlobalState state);
}

// Key includes:
// - Skill levels (affect unlocks)
// - Tool tiers (affect durations)
```

### Candidate Cache

Candidates are cached per capability level in `enumerate_candidates.dart`.

## Algorithm Performance

Default limits to prevent runaway searches:
- Max expanded nodes: 200,000 (`defaultMaxExpandedNodes`)
- Max queue size: 500,000 (`defaultMaxQueueSize`)

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
  Goal goal, {
  bool collectDiagnostics = false,
  int maxExpandedNodes = defaultMaxExpandedNodes,
  int maxQueueSize = defaultMaxQueueSize,
})
```

### Returns

```dart
sealed class SolverResult {
  final SolverProfile? profile;
}

class SolverSuccess extends SolverResult {
  final Plan plan;
  final GlobalState terminalState;  // State at end of plan (from search)
}

class SolverFailed extends SolverResult {
  final SolverFailure failure;
}
```

### Failure Modes

```dart
class SolverFailure {
  final String reason;
  final int expandedNodes;
  final int enqueuedNodes;
  final int? bestCredits;  // Best progress achieved
}
```

- Node limit exceeded
- Queue size limit exceeded
- Empty queue (no path to goal exists)
- Zero rate (can't make progress - stuck state)
