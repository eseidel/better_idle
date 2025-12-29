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
| `solver.dart` | A* search algorithm, node expansion, heuristics |
| `goal.dart` | Goal definitions (GP, skill level, multi-skill) |
| `enumerate_candidates.dart` | Generates candidate actions/upgrades/macros |
| `estimate_rates.dart` | Calculates expected rates per tick |
| `value_model.dart` | Converts rates to scalar values |
| `plan.dart` | Plan representation and compression |
| `execute_plan.dart` | Plan execution against real game state |
| `interaction.dart` | 0-tick state mutations |
| `wait_for.dart` | Wait conditions for macro boundaries |
| `macro.dart` | Macro definitions and expansion |
| `solver_profile.dart` | Diagnostics and profiling |

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
sealed class Interaction {
  GlobalState apply(GlobalState state);
}

class SwitchActivity extends Interaction { ... }
class BuyShopItem extends Interaction { ... }
class SellItems extends Interaction { ... }
```

### WaitFor

Condition for stopping a wait:
```dart
sealed class WaitFor {
  bool isSatisfied(GlobalState state);
  int estimateTicks(GlobalState state, Rates rates);
}

class WaitForSkillXp extends WaitFor { ... }
class WaitForInventoryValue extends WaitFor { ... }
class WaitForAnyOf extends WaitFor { ... }
```

### Macro

High-level training directive:
```dart
sealed class Macro {
  String describe(ActionRegistry actions);
}

class TrainSkillUntil extends Macro {
  final Skill skill;
  final StopRule primaryStop;
  final List<StopRule> watchedStops;
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
