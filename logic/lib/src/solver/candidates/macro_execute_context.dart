/// Context object for macro execution in the solver.
///
/// Bundles state, wait condition, and execution parameters needed to execute
/// macros. This allows MacroCandidate.execute() to take a single context
/// parameter.
library;

import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/analysis/watch_set.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';

/// Context for macro execution operations.
///
/// Provides access to execution-time utilities that macros need during
/// stochastic simulation. This bundles all parameters needed for execution.
///
/// Unlike `MacroPlanContext` which uses expected-value modeling,
/// `MacroExecuteContext` is used for actual execution with randomness.
class MacroExecuteContext {
  const MacroExecuteContext({
    required this.state,
    required this.waitFor,
    required this.random,
    this.boundaries,
    this.watchSet,
    this.segmentSellPolicy,
  });

  /// Current game state before execution.
  final GlobalState state;

  /// Composite wait condition from planning (determines when to stop).
  final WaitFor waitFor;

  /// Random number generator for stochastic simulation.
  final Random random;

  /// Skill unlock boundaries for re-evaluating stop rules.
  final Map<Skill, SkillBoundaries>? boundaries;

  /// Enables mid-macro boundary detection if provided.
  final WatchSet? watchSet;

  /// Sell policy for handling inventory full during execution.
  final SellPolicy? segmentSellPolicy;
}
