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
