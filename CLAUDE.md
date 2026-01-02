# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Better Idle is an idle game inspired by Melvor Idle, built with Flutter for mobile. The project is split into two packages:

- **logic/** - Pure Dart game logic with no Flutter dependencies. Contains state management, actions, skills, items, combat, and tick processing.
- **ui/** - Flutter app with UI screens, Redux integration, and game loop.

## Common Commands

### Logic Package (from `logic/` directory)
```bash
dart pub get                    # Install dependencies
dart test                       # Run all tests
dart test test/state_test.dart  # Run single test file
dart run bin/simulate_day.dart  # Run simulation tool
dart analyze                    # Run analyzer
```

### UI Package (from `ui/` directory)
```bash
flutter pub get       # Install dependencies
flutter run           # Run the app
flutter analyze       # Run analyzer (uses very_good_analysis)
flutter test          # Run tests
```

## Architecture

### Game State Flow
1. **GlobalState** ([logic/lib/src/state.dart](logic/lib/src/state.dart)) - Immutable state object containing inventory, skills, active action, equipment, health, and shop state. Serialized to JSON for persistence.

2. **Actions** ([logic/lib/src/data/actions.dart](logic/lib/src/data/actions.dart)) - Two types:
   - `SkillAction` - Duration-based actions (woodcutting, fishing, mining, etc.) that consume inputs and produce outputs
   - `CombatAction` - Combat encounters with monsters

3. **Tick System** ([logic/lib/src/tick.dart](logic/lib/src/tick.dart), [logic/lib/src/consume_ticks.dart](logic/lib/src/consume_ticks.dart)) - Game time measured in ticks (100ms each). `consumeTicks()` processes foreground actions and background timers (HP regen, mining respawn) in parallel.

4. **StateUpdateBuilder** - Accumulates changes during tick processing, tracks inventory changes, XP gains, and level ups for the "welcome back" dialog.

### UI State Management
- Uses **async_redux** for state management
- **GameLoop** ([ui/lib/src/logic/game_loop.dart](ui/lib/src/logic/game_loop.dart)) - Flutter Ticker that dispatches `UpdateActivityProgressAction` at 100ms intervals
- Redux actions in [ui/lib/src/logic/redux_actions.dart](ui/lib/src/logic/redux_actions.dart) wrap logic layer operations

### Key Concepts
- **Skills** - Woodcutting, Firemaking, Fishing, Cooking, Mining, Smithing, Thieving, Combat (Hitpoints, Attack)
- **Mastery** - Per-action XP that unlocks bonuses (e.g., double drops in woodcutting)
- **Inventory** - Slot-based bank with purchasable expansion
- **Equipment** - Food slots for healing during combat
- **Time Away** - Calculates progress while app was in background, shows "welcome back" summary

### Data Registries
- `actionRegistry` - All skill and combat actions
- `itemRegistry` ([logic/lib/src/data/items.dart](logic/lib/src/data/items.dart)) - All items with properties (sell value, heal amount)
- `dropsRegistry` - Drop tables combining action, skill, and global drops

### Solver System
The `logic/lib/src/solver/` directory contains an A* path-finding solver for automated goal-seeking:
- `solver.dart` - Main solver entry point
- `goal.dart` - Goal definitions (e.g., acquire item, reach level)
- `enumerate_candidates.dart` - Generates possible next actions
- Uses `estimateRates` and `ValueModel` for heuristic evaluation

Run the solver CLI: `dart run bin/solver.dart`

### Data Loading
Game data is sourced from Melvor Idle's API and cached locally:
- `MelvorId` - Strongly-typed IDs (e.g., `melvorD:Woodcutting`, `melvorD:Oak_Tree`)
- `MelvorData` - Orchestrates fetching and caching game data
- Data cached in `.cache/assets/` for offline development

### Testing Patterns
- Use `GlobalState.test()` factory for test fixtures with custom registries
- `test_helper.dart` provides common test utilities
- Most comprehensive tests are in `consume_ticks_test.dart` (covers tick processing edge cases)

## Workflow

Run `dart format .` and `dart fix --apply .` upon completion of edits.

NEVER use cat << EOF for writing content or generating reports; only use the specific Edit or Write tools to modify files"

Always create tools within the `tool` directory of the Dart project so that they can access package: imports.