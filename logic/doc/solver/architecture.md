# Solver Architecture

## System Overview

```
Initial State
    |
    v
[Rate Estimation] --> estimateRates()
    |
    v
[Value Model] --> valuePerTick()
    |
    v
[Candidate Enumeration] --> enumerateCandidates()
    |
    +-- Activity candidates (top K by goal rate)
    +-- Upgrade candidates (top M by payback time)
    +-- Watch lists (future interesting events)
    +-- Macro candidates (train until boundary)
    |
    v
[A* Search] --> solve()
    |
    +-- Priority queue (f = g + h)
    +-- Dominance pruning (Pareto frontier)
    +-- State bucketing (goal-scoped deduplication)
    |
    v
[Plan Output] --> Plan
    |
    v
[Execution] --> executePlan()
```

## Core Files

| File | Purpose |
|------|---------|
| `solver.dart` | A* search algorithm, node expansion, heuristics, SolverProfile |
| `goal.dart` | Goal definitions (GP, skill level, multi-skill, segment) |
| `enumerate_candidates.dart` | Generates candidate actions/upgrades/macros |
| `estimate_rates.dart` | Calculates expected rates per tick |
| `value_model.dart` | Converts rates to scalar values |
| `plan.dart` | Plan representation, compression, segments, and execution result types |
| `interaction.dart` | 0-tick state mutations (SwitchActivity, BuyShopItem, SellItems), sell policies |
| `apply_interaction.dart` | Applies interactions to game state |
| `available_interactions.dart` | Determines which interactions are currently available |
| `wait_for.dart` | Wait conditions for plan execution |
| `macro_candidate.dart` | Macro definitions (TrainSkillUntil, TrainConsumingSkillUntil, AcquireItem, EnsureStock) |
| `next_decision_delta.dart` | Computes time until next interesting event |
| `replan_boundary.dart` | Defines when replanning is needed during execution |
| `unlock_boundaries.dart` | Tracks skill level boundaries where actions unlock |
| `candidate_cache.dart` | Caches candidate enumeration results |
| `watch_set.dart` | WatchSet for segment-based boundary detection, SegmentContext |
| `solver_profile.dart` | Profiling and diagnostics for solver runs |

## Data Flow

### 1. Rate Estimation

Given a state and action, `estimateRates()` computes:
- `directGpPerTick`: Coins from actions (thieving)
- `itemFlowsPerTick`: Items produced per tick
- `xpPerTickBySkill`: XP gained per skill
- `hpLossPerTick`: HP lost (thieving stunts)

### 2. Value Model

The `ValueModel` converts rates to a scalar value per tick:
- `SellEverythingForGpValueModel`: value = GP + items * sellPrice
- Used to compare different actions by goal progress

### 3. Candidate Enumeration

`enumerateCandidates()` returns:
- **switchToActivities**: Best actions ranked by goal rate
- **buyUpgrades**: Upgrades with good payback time
- **sellPolicy**: How to handle inventory
- **watch**: Future events to check
- **macros**: Skill training macros

### 4. A* Search

The search maintains:
- **Open set**: Priority queue ordered by f(n) = g(n) + h(n)
- **Frontier**: Pareto frontier for dominance pruning
- **Rate cache**: Avoid recomputing rates for same state

### 5. Plan Generation

When goal is reached:
- Backtrack through parent pointers
- Collect steps (interactions + waits)
- Compress consecutive waits

## Key Abstractions

### Interaction

A 0-tick state change:
```dart
sealed class Interaction extends Equatable {
  const Interaction();
}

class SwitchActivity extends Interaction {
  final ActionId actionId;
}

class BuyShopItem extends Interaction {
  final MelvorId purchaseId;
}

class SellItems extends Interaction {
  final SellPolicy policy;  // SellAllPolicy or SellExceptPolicy
}
```

### SellPolicy

Determines which items to sell vs keep:
```dart
sealed class SellPolicy extends Equatable {
  const SellPolicy();
}

class SellAllPolicy extends SellPolicy { ... }

class SellExceptPolicy extends SellPolicy {
  final Set<MelvorId> keepItems;  // Items to preserve
}
```

### SellPolicySpec

Stable policy specification for consistent behavior across a segment:
```dart
sealed class SellPolicySpec extends Equatable {
  SellPolicy instantiate(GlobalState state, Set<Skill> consumingSkills);
}

class SellAllSpec extends SellPolicySpec { ... }
class ReserveConsumingInputsSpec extends SellPolicySpec { ... }
```

### WaitFor

Condition for stopping a wait:
```dart
sealed class WaitFor extends Equatable {
  bool isSatisfied(GlobalState state);
  int progress(GlobalState state);
  int estimateTicks(GlobalState state, Rates rates);
  String describe();
  String get shortDescription;
}

class WaitForSkillXp extends WaitFor { ... }
class WaitForEffectiveCredits extends WaitFor { ... }
class WaitForMasteryXp extends WaitFor { ... }
class WaitForInventoryThreshold extends WaitFor { ... }
class WaitForInventoryFull extends WaitFor { ... }
class WaitForGoal extends WaitFor { ... }
class WaitForInputsDepleted extends WaitFor { ... }
class WaitForInputsAvailable extends WaitFor { ... }
class WaitForInventoryAtLeast extends WaitFor { ... }
class WaitForInventoryDelta extends WaitFor { ... }
class WaitForSufficientInputs extends WaitFor { ... }
class WaitForAnyOf extends WaitFor { ... }
```

### MacroCandidate

High-level training directive:
```dart
sealed class MacroCandidate {
  const MacroCandidate();
}

class TrainSkillUntil extends MacroCandidate {
  final Skill skill;
  final ActionId? actionId;  // Optional specific action
  final MacroStopRule primaryStop;
  final List<MacroStopRule> watchedStops;
}

class TrainConsumingSkillUntil extends MacroCandidate {
  final Skill consumingSkill;
  final MacroStopRule primaryStop;
  final List<MacroStopRule> watchedStops;
}

class AcquireItem extends MacroCandidate {
  final MelvorId itemId;
  final int quantity;
}

class EnsureStock extends MacroCandidate {
  final MelvorId itemId;
  final int minTotal;  // Absolute target, not delta
}
```

### WatchSet and SegmentContext

For segment-based planning:
```dart
class WatchSet {
  final Goal goal;
  final SegmentConfig config;
  final Set<MelvorId> upgradePurchaseIds;
  final Map<Skill, Set<int>> unlockLevels;
  final SellPolicy sellPolicy;

  SegmentBoundary? detectBoundary(GlobalState state, {int? elapsedTicks});
  bool isMaterial(ReplanBoundary boundary);
}

class SegmentContext {
  final Goal goal;
  final SegmentConfig config;
  final SellPolicySpec sellPolicySpec;
  final SellPolicy sellPolicy;
  final WatchSet watchSet;
}
```

## Design Principles

### 1. Separation of Concerns

- **Rates** (mechanical) vs **Values** (policy)
- **Interactions** (what) vs **Waits** (when)
- **Planning** (expected values) vs **Execution** (simulation)

### 2. Watch != Action

Watch lists define "interesting times" for replanning. Action lists define what's immediately actionable. This prevents the solver from branching on every watched event.

### 3. Goal-Scoped Bucketing

State bucketing only tracks skills/resources relevant to the current goal. This dramatically reduces the state space.

### 4. Admissible Heuristics

The heuristic never overestimates remaining time. It uses the best *unlocked* rate, accounting for producer throughput for consuming skills.

### 5. Macro-Level Planning

Instead of planning tick-by-tick, macros allow the solver to reason about extended training periods, reducing the branching factor.
