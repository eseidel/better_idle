# Solver System

The Better Idle solver is an A* pathfinding system that finds optimal plans to reach game goals. It answers the question: "What sequence of actions gets me to my goal in minimum time?"

## Quick Start

```bash
# Solve for 100 GP (default)
dart run bin/solver.dart

# Solve for specific GP amount
dart run bin/solver.dart 500

# Solve for skill level
dart run bin/solver.dart -s                    # Firemaking 30
dart run bin/solver.dart -m "Woodcutting=50"   # Any skill

# Multiple skills
dart run bin/solver.dart -m "Woodcutting=50,Firemaking=50"

# With diagnostics
dart run bin/solver.dart -d 1000
```

## Documentation

- [Architecture Overview](architecture.md) - High-level system design
- [Goals](goals.md) - Goal types and how they work
- [Rate Estimation](rates.md) - How action rates are calculated
- [Candidate Enumeration](candidates.md) - How the solver decides what to try
- [A* Search](astar.md) - The core search algorithm
- [Macros](macros.md) - Macro-level planning for efficiency
- [Plan Execution](execution.md) - How plans are executed

## Key Concepts

### The Problem

Given a game state (inventory, skills, equipment), find the sequence of interactions (switch action, buy upgrade, sell items) and wait periods that reaches a goal in minimum ticks.

### The Solution

1. **Rate Estimation**: Calculate expected items/XP/GP per tick for each action
2. **Candidate Enumeration**: Identify promising actions and upgrades to try
3. **A* Search**: Explore the state space, using heuristics to prioritize
4. **Macro Expansion**: Jump forward through long training periods
5. **Plan Output**: Return a sequence of steps to execute

### Why A*?

The game has a huge state space (inventory items, skill levels, equipment, etc.), but:
- Actions have predictable expected values
- Most states are dominated by better alternatives
- Macro-level jumps reduce branching dramatically

A* with dominance pruning and macro expansion efficiently finds optimal solutions.

## Key Design Principles

### 1. Flows vs Value

Rate estimation (`estimateRates`) produces **flows** (items/tick, XP/tick), not value. The `ValueModel` layer converts flows to scalar values based on the goal.

### 2. Watch ≠ Action

**Key invariant**: Watch lists affect only waiting, never imply we should take an action.

An upgrade being "watched" (for affordability timing) does NOT mean we should buy it. Only upgrades in `Candidates.buyUpgrades` are actionable.

### 3. Policy Consistency

`SellPolicy` is computed once per segment via `SellPolicySpec` and used consistently across:
- `WatchSet` (for `effectiveCredits` calculation)
- `enumerateCandidates` (for sell candidate emission)
- Boundary handling (when buying after `UpgradeAffordableBoundary`)

### 4. Goal-Scoped Bucketing

State buckets track only what's relevant to the goal:
- GP goal: all skills, coarse GP bucket
- Skill goal: only target skill
- Thieving goal: HP and mastery levels

## Core Types

### SolverResult

```dart
sealed class SolverResult {
  final SolverProfile? profile;
}

class SolverSuccess extends SolverResult {
  final Plan plan;
  final GlobalState terminalState;
}

class SolverFailed extends SolverResult {
  final SolverFailure failure;
}
```

### Plan

```dart
class Plan {
  final List<PlanStep> steps;
  final int totalTicks;
  final int interactionCount;
  final int expandedNodes;
  final int enqueuedNodes;
  final int expectedDeaths;
  final List<SegmentMarker> segmentMarkers;
}
```

### PlanStep

```dart
sealed class PlanStep { }
class InteractionStep extends PlanStep { ... }
class WaitStep extends PlanStep { ... }
class MacroStep extends PlanStep { ... }
```

## Performance

Default limits:
- Max expanded nodes: 200,000
- Max queue size: 500,000

Typical metrics:
- Expanded nodes: 100-10,000
- Branching factor: 3-8
- Nodes/second: 1,000-10,000

## Files

| File | Purpose |
|------|---------|
| `solver.dart` | A* search, node expansion, heuristics |
| `goal.dart` | Goal definitions |
| `enumerate_candidates.dart` | Candidate generation |
| `estimate_rates.dart` | Rate calculations |
| `value_model.dart` | Rates → scalar value |
| `plan.dart` | Plan representation and segments |
| `interaction.dart` | 0-tick mutations, sell policies |
| `wait_for.dart` | Wait conditions |
| `macro_candidate.dart` | Macro definitions |
| `watch_set.dart` | Segment boundary detection |
| `replan_boundary.dart` | Execution boundary types |
