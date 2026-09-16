Inspired by Melvor Idle, built with Flutter for mobile. Two packages:

- **logic/** - Pure Dart game logic, no Flutter dependencies.
- **ui/** - Flutter app with async_redux state management.

## Commands

- `dart test -r failures-only` - run tests (from logic/)
- `flutter test -r failures-only` - run tests (from ui/)
- `dart run tool/warm_cache.dart` - pre-fetch Melvor data into .cache (from
  logic/). Tests read the cache and never populate it, so a cold cache fails
  every run. From ui/ use `dart run ../logic/tool/warm_cache.dart .cache`
- `dart run tool/coverage.dart` - run tests with coverage summary (from logic/)
- `dart run tool/coverage.dart --check` - same, fails if below 90%
- `dart run bin/solver.dart` - run the A* solver CLI (from logic/)
- `dart format .` and `dart fix --apply .` - run from repo root
- `dart analyze --fatal-infos` - the bar for new code. CI currently enforces
  only `--fatal-warnings`; `logic` carries 45 pre-existing infos (see #283)
- `npx cspell` - spell check, must pass

## Gotchas

- **Every workflow tracks Flutter `stable`.** Nothing is pinned, so a Flutter
  release can turn CI red with no code change - a new lint is the usual cause.
  Check which version CI used before concluding the failure is yours.
- **`ui/pubspec.lock` is checked in** (it is an app, not a library) so a newer
  SDK re-resolving it is a real change to commit, not noise.
- **`.github/workflows/shorebird_ci.yaml` is generated** by `shorebird_ci
  generate`, which drops the two hand-added cache-warming steps. They are
  marked with comments; re-add them after regenerating.

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
- Run `dart format .` from the repo root before committing. CI enforces formatting.

## Engineering Practices

When making changes to Impression, you **MUST** follow these practices:

1. **Write tests for all behavior changes**: All behavior changes require accompanying tests. Run them using `dart test` or `flutter test`.
2. **Don't Repeat Yourself (DRY)**: Do not repeat code. If you find yourself writing the same code in multiple places, refactor it into a reusable function or component.
3. **Commit and push after each logical change**: Do not stack a massive list of changes. Keep your commits atomic, well-described, and push them to remote.
4. **Reflect on changes and file GitHub issues**: As you work, you will notice technical debt, missing features, edge cases, or potential refactors. You must identify these and file GitHub issues for future work rather than ignoring them or going down a rabbit hole.