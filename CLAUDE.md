Inspired by Melvor Idle, built with Flutter for mobile. Two packages:

- **logic/** - Pure Dart game logic, no Flutter dependencies.
- **ui/** - Flutter app with async_redux state management.

## Commands

- `dart test -r failures-only` - run tests (from logic/ or ui/)
- `dart run tool/coverage.dart` - run tests with coverage summary (from logic/)
- `dart run tool/coverage.dart --check` - same, fails if below 90%
- `dart run bin/solver.dart` - run the A* solver CLI (from logic/)
- `dart format .` and `dart fix --apply .` - run from within each package (logic/ and ui/) to pick up analysis_options.yaml
- `npx cspell` - spell check, must pass

## Key Architecture

- **GlobalState** (logic/lib/src/state.dart) - immutable state, JSON-serializable
- **Tick System** (logic/lib/src/tick.dart, consume_ticks.dart) - 100ms ticks, `consumeTicks()` processes actions
- **Registries** (logic/lib/src/data/registries.dart) - central access to all game data
- **MelvorId** - strongly-typed IDs (e.g., `melvorD:Oak_Tree`), data cached in `.cache/assets/`
- **Solver** (logic/lib/src/solver/) - A* path-finding for automated goal-seeking

## Testing

- `GlobalState.test()` factory for test fixtures with custom registries
- `test_helper.dart` for common utilities

## Rules

- Create tools in the `tool` directory so they can use package: imports.
- Never support legacy paths or formats unless explicitly requested.
