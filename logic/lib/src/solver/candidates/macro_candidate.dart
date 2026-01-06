/// Macro-level planning primitives for solver.
///
/// Macros represent "train until boundary/goal/upgrade" decisions that span
/// many ticks, reducing the solver's branching factor and state explosion.
library;

import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/next_decision_delta.dart'
    show infTicks;
import 'package:logic/src/solver/analysis/replan_boundary.dart'
    show
        InventoryFull,
        InventoryPressure,
        NoProgressPossible,
        ReplanBoundary,
        WaitConditionSatisfied;
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/build_chain.dart';
import 'package:logic/src/solver/candidates/macro_execute_context.dart';
import 'package:logic/src/solver/candidates/macro_plan_context.dart';
import 'package:logic/src/solver/core/goal.dart' show ReachSkillLevelGoal;
import 'package:logic/src/solver/execution/consume_until.dart';
import 'package:logic/src/solver/execution/prerequisites.dart'
    show
        ExecNeedsMacros,
        ExecReady,
        ExecUnknown,
        findBestActionForSkill,
        findProducerActionForItem;
import 'package:logic/src/solver/execution/state_advance.dart';
import 'package:logic/src/solver/execution/step_helpers.dart'
    show countItem, executeCoupledLoop, executeTrainSkillWithBoundaryChecks;
import 'package:logic/src/solver/interactions/apply_interaction.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart' show ticksFromDuration;

/// Debug flag for EnsureStock quantization and termination logging.
/// Set to true to trace EnsureStock behavior during solver runs.
const bool _debugEnsureStock = false;

// ---------------------------------------------------------------------------
// Provenance - tracks WHY a macro was created
// ---------------------------------------------------------------------------

/// Tracks the origin of a macro for debugging and explanation.
///
/// When macros are generated as prerequisites or batch inputs, provenance
/// tells us why they were created, enabling better debugging and the
/// "explain one expansion" feature.
sealed class MacroProvenance {
  const MacroProvenance();

  /// Human-readable description of why this macro was created.
  String describe();
}

/// Macro generated directly by candidate enumeration (top-level).
class TopLevelProvenance extends MacroProvenance {
  const TopLevelProvenance();

  @override
  String describe() => 'Top-level candidate';
}

/// Macro generated as a skill level prerequisite.
///
/// Example: "Need Mining L15 to unlock Mithril Ore for Smithing"
class SkillPrereqProvenance extends MacroProvenance {
  const SkillPrereqProvenance({
    required this.requiredSkill,
    required this.requiredLevel,
    required this.unlocksAction,
  });

  final Skill requiredSkill;
  final int requiredLevel;
  final ActionId unlocksAction;

  @override
  String describe() =>
      'Prereq: ${requiredSkill.name} L$requiredLevel unlocks $unlocksAction';
}

/// Macro generated to acquire inputs for a consuming action.
///
/// Example: "Need 50 Bronze Bars for Smithing Bronze Daggers"
class InputPrereqProvenance extends MacroProvenance {
  const InputPrereqProvenance({
    required this.forAction,
    required this.inputItem,
    required this.quantityNeeded,
  });

  final ActionId forAction;
  final MelvorId inputItem;
  final int quantityNeeded;

  @override
  String describe() =>
      'Input: ${quantityNeeded}x ${inputItem.localId} for $forAction';
}

/// Macro generated as a batched input for a craft-until-unlock phase.
///
/// Example: "Batch: 120 Copper Ore for 40 Bronze Bars to reach Smithing L10"
class BatchInputProvenance extends MacroProvenance {
  const BatchInputProvenance({
    required this.forItem,
    required this.batchSize,
    required this.targetLevel,
  });

  final MelvorId forItem;
  final int batchSize;
  final int targetLevel;

  @override
  String describe() =>
      'Batch: ${batchSize}x ${forItem.localId} for L$targetLevel unlock';
}

/// Macro generated as part of a multi-tier production chain.
///
/// Example: "Chain: Bronze Bar -> Bronze Dagger, need ores first"
class ChainProvenance extends MacroProvenance {
  const ChainProvenance({required this.parentItem, required this.childItem});

  final MelvorId parentItem;
  final MelvorId childItem;

  @override
  String describe() =>
      'Chain: ${childItem.localId} needed for ${parentItem.localId}';
}

// ---------------------------------------------------------------------------
// Macro Candidates
// ---------------------------------------------------------------------------

/// A macro-level planning action that commits to an activity for an
/// extended period.
///
/// Macros stop when ANY of their stop conditions trigger, allowing the solver
/// to react to unlock boundaries, goal completion, or upgrade affordability.
///
/// ## Two-Phase Model
///
/// Macros have two distinct phases, each with its own method:
///
/// ### Planning Phase: [plan]
/// Used during A* search to estimate costs and project state forward.
/// - Uses **expected-value modeling** (deterministic averages)
/// - Called by the solver to evaluate candidate paths
/// - Returns a [MacroPlanResult] with projected state and [WaitFor]
/// - Does NOT use randomness - uses deterministic advance/interaction functions
///
/// ### Execution Phase: [execute]
/// Used when actually executing a plan with real game simulation.
/// - Uses **stochastic simulation** (actual randomness)
/// - Called by plan execution after the solver has chosen a path
/// - Runs until the [WaitFor] condition from planning is satisfied
/// - Handles real-world concerns like inventory full, deaths, etc.
///
/// ## Why Separate Phases?
///
/// The solver needs fast, deterministic state projection to explore many
/// paths. Execution needs accurate simulation with randomness. Separating
/// these allows:
/// - Consistent A* cost estimation (plan uses averages)
/// - Realistic execution (execute uses actual RNG)
/// - Plan replay/debugging (same plan, different random outcomes)
sealed class MacroCandidate {
  const MacroCandidate({this.provenance});

  /// Why this macro was created (for debugging/explanation).
  final MacroProvenance? provenance;

  /// Unique key for deduplication purposes.
  ///
  /// Two macros with the same key are considered equivalent for planning,
  /// allowing the solver to eliminate duplicates.
  String get dedupeKey;

  /// **Planning phase**: Projects state forward using expected-value modeling.
  ///
  /// Called by the A* solver during path exploration. Uses deterministic
  /// averages (not randomness) to estimate how long this macro will take
  /// and what state will result.
  ///
  /// Returns [MacroPlanned] on success, [MacroAlreadySatisfied] if no work
  /// needed, or [MacroCannotPlan] with a reason if planning is impossible.
  MacroPlanOutcome plan(MacroPlanContext context);

  /// **Execution phase**: Runs actual stochastic simulation.
  ///
  /// Called by `MacroStep.execute()` when executing a plan that the solver has
  /// already chosen. Uses real randomness and runs until the wait condition
  /// from planning is satisfied.
  ///
  /// - [context]: Execution context containing state, wait condition, RNG,
  ///   boundaries, and policies.
  MacroExecuteResult execute(MacroExecuteContext context);

  /// Serializes this [MacroCandidate] to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes a [MacroCandidate] from a JSON-compatible map.
  static MacroCandidate fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'TrainSkillUntil' => TrainSkillUntil(
        Skill.fromName(json['skill'] as String),
        MacroStopRule.fromJson(json['primaryStop'] as Map<String, dynamic>),
        watchedStops: (json['watchedStops'] as List<dynamic>)
            .map((s) => MacroStopRule.fromJson(s as Map<String, dynamic>))
            .toList(),
        actionId: json['actionId'] != null
            ? ActionId.fromJson(json['actionId'] as String)
            : null,
      ),
      'AcquireItem' => AcquireItem(
        MelvorId.fromJson(json['itemId'] as String),
        json['quantity'] as int,
      ),
      'EnsureStock' => EnsureStock(
        MelvorId.fromJson(json['itemId'] as String),
        json['minTotal'] as int,
      ),
      'ProduceItem' => ProduceItem(
        itemId: MelvorId.fromJson(json['itemId'] as String),
        minTotal: json['minTotal'] as int,
        actionId: ActionId.fromJson(json['actionId'] as String),
        estimatedTicks: json['estimatedTicks'] as int,
      ),
      'TrainConsumingSkillUntil' => TrainConsumingSkillUntil(
        Skill.fromName(json['consumingSkill'] as String),
        MacroStopRule.fromJson(json['primaryStop'] as Map<String, dynamic>),
        watchedStops: (json['watchedStops'] as List<dynamic>)
            .map((s) => MacroStopRule.fromJson(s as Map<String, dynamic>))
            .toList(),
        actionId: json['actionId'] != null
            ? ActionId.fromJson(json['actionId'] as String)
            : null,
        consumeActionId: json['consumeActionId'] != null
            ? ActionId.fromJson(json['consumeActionId'] as String)
            : null,
        producerByInputItem: json['producerByInputItem'] != null
            ? {
                for (final entry
                    in (json['producerByInputItem'] as Map<String, dynamic>)
                        .entries)
                  MelvorId.fromJson(entry.key): ActionId.fromJson(
                    entry.value as String,
                  ),
              }
            : null,
        bufferTarget: json['bufferTarget'] as int?,
        sellPolicySpec: json['sellPolicySpec'] != null
            ? SellPolicySpec.fromJson(
                json['sellPolicySpec'] as Map<String, dynamic>,
              )
            : null,
        maxRecoveryAttempts: json['maxRecoveryAttempts'] as int? ?? 3,
        inputChains: json['inputChains'] != null
            ? {
                for (final entry
                    in (json['inputChains'] as Map<String, dynamic>).entries)
                  MelvorId.fromJson(entry.key): PlannedChain.fromJson(
                    entry.value as Map<String, dynamic>,
                  ),
              }
            : null,
      ),
      _ => throw ArgumentError('Unknown MacroCandidate type: $type'),
    };
  }
}

/// Train a skill by doing its best action until ANY stop condition triggers.
///
/// Example: "Train Woodcutting until (next boundary OR Steel Axe affordable)"
class TrainSkillUntil extends MacroCandidate {
  const TrainSkillUntil(
    this.skill,
    this.primaryStop, {
    this.watchedStops = const [],
    this.actionId,
    super.provenance,
  });

  final Skill skill;

  /// The specific action to use for training. If null, the best action will
  /// be computed at execution time (but this may cause inconsistency with
  /// subsequent WaitSteps that expect a specific action's mastery).
  final ActionId? actionId;

  @override
  String get dedupeKey => 'train:${skill.name}:${primaryStop.hashCode}';

  /// Primary stop condition (usually boundary or goal).
  final MacroStopRule primaryStop;

  /// Additional stop conditions to watch (upgrades, inputs, etc.).
  /// Macro stops when ANY condition (primary OR watched) triggers.
  final List<MacroStopRule> watchedStops;

  /// All stop conditions (primary + watched).
  List<MacroStopRule> get allStops => [primaryStop, ...watchedStops];

  @override
  MacroPlanOutcome plan(MacroPlanContext context) {
    final state = context.state;

    // Find best unlocked action for this skill
    final bestAction = findBestActionForSkill(state, skill, context.goal);
    if (bestAction == null) {
      return MacroCannotPlan('No unlocked action for ${skill.name}');
    }

    // Switch to that action (if not already on it)
    var currentState = state;
    if (state.activeAction?.id != bestAction) {
      currentState = applyInteractionDeterministic(
        state,
        SwitchActivity(bestAction),
      );
    }

    // Build composite WaitFor from all stop rules (primary + watched)
    final stopRules = allStops.toList();
    final waitConditions = stopRules
        .map((rule) => rule.toWaitFor(currentState, context.boundaries))
        .toList();

    // Create composite WaitFor (stops when ANY condition triggers)
    final compositeWaitFor = waitConditions.length == 1
        ? waitConditions.first
        : WaitForAnyOf(waitConditions);

    // Estimate ticks until ANY stop condition triggers (use minimum)
    final rates = estimateRates(currentState);
    final ticksUntilStop = compositeWaitFor.estimateTicks(currentState, rates);

    if (ticksUntilStop <= 0) {
      return MacroAlreadySatisfied(
        'Stop condition already satisfied for ${skill.name}',
      );
    }
    if (ticksUntilStop >= infTicks) {
      return MacroCannotPlan(
        'No progress possible for ${skill.name} (infinite ticks)',
      );
    }

    // Find which condition triggered first (has minimum ticks)
    String? triggeringCondition;
    for (var i = 0; i < waitConditions.length; i++) {
      final ticks = waitConditions[i].estimateTicks(currentState, rates);
      if (ticks == ticksUntilStop) {
        triggeringCondition = waitConditions[i].shortDescription;
        break;
      }
    }

    // Use expected-value advance (deterministic for planning)
    final advanceResult = advanceDeterministic(currentState, ticksUntilStop);

    // Create enriched macro with the specific action we chose
    final enrichedMacro = TrainSkillUntil(
      skill,
      primaryStop,
      watchedStops: watchedStops,
      actionId: bestAction,
    );

    return MacroPlanned((
      state: advanceResult.state,
      ticksElapsed: ticksUntilStop,
      waitFor: compositeWaitFor,
      deaths: advanceResult.deaths,
      triggeringCondition: triggeringCondition,
      macro: enrichedMacro,
    ));
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'TrainSkillUntil',
    'skill': skill.name,
    'primaryStop': primaryStop.toJson(),
    'watchedStops': watchedStops.map((s) => s.toJson()).toList(),
    if (actionId != null) 'actionId': actionId!.toJson(),
  };

  @override
  MacroExecuteResult execute(MacroExecuteContext context) {
    // Use the action that was determined during planning
    final actionToUse =
        actionId ??
        findBestActionForSkill(
          context.state,
          skill,
          ReachSkillLevelGoal(skill, 99),
        );

    // Switch to action if needed
    var state = context.state;
    if (actionToUse != null && state.activeAction?.id != actionToUse) {
      state = applyInteraction(
        state,
        SwitchActivity(actionToUse),
        random: context.random,
      );
    }

    // Regenerate WaitFor based on actual execution state
    final waitFor = context.boundaries != null
        ? _buildCompositeWaitFor(state, context.boundaries!)
        : context.waitFor;

    // Execute with mid-macro boundary checking if watchSet provided
    if (context.watchSet != null) {
      final stepResult = executeTrainSkillWithBoundaryChecks(
        state,
        waitFor,
        context.random,
        context.watchSet!,
      );
      return MacroExecuteResult(
        state: stepResult.state,
        ticksElapsed: stepResult.ticksElapsed,
        deaths: stepResult.deaths,
        boundary: stepResult.boundary,
      );
    }

    // Simple execution without boundary checking
    final result = consumeUntil(state, waitFor, random: context.random);
    return MacroExecuteResult(
      state: result.state,
      ticksElapsed: result.ticksElapsed,
      deaths: result.deathCount,
      boundary: result.boundary,
    );
  }

  /// Builds composite WaitFor from all stop rules.
  WaitFor _buildCompositeWaitFor(
    GlobalState state,
    Map<Skill, SkillBoundaries> boundaries,
  ) {
    final waitConditions = allStops
        .map((rule) => rule.toWaitFor(state, boundaries))
        .toList();
    return waitConditions.length == 1
        ? waitConditions.first
        : WaitForAnyOf(waitConditions);
  }
}

/// Acquire items by producing them (and their prerequisites).
///
/// This macro:
/// 1. Finds the action that produces itemId
/// 2. Ensures prerequisites are met (skill levels, input items)
/// 3. Executes the producing action until quantity reached
///
/// Used for:
/// - Gathering inputs for consuming skills (ores for smithing)
/// - Multi-tier chains (bars need ores, which need mining skill)
class AcquireItem extends MacroCandidate {
  const AcquireItem(this.itemId, this.quantity, {super.provenance});

  /// The item to acquire.
  final MelvorId itemId;

  /// How many to acquire.
  final int quantity;

  @override
  String get dedupeKey => 'acquire:${itemId.localId}:$quantity';

  @override
  MacroPlanOutcome plan(MacroPlanContext context) {
    final state = context.state;

    // Find producer for this item
    final producer = context.findProducerAction(state, itemId, context.goal);

    if (producer == null) {
      // Check if a locked producer exists
      final lockedProducer = context.findAnyProducer(state, itemId);
      if (lockedProducer != null) {
        // Need to train skill first - return prerequisite
        return MacroNeedsPrerequisite(
          TrainSkillUntil(
            lockedProducer.skill,
            StopAtLevel(lockedProducer.skill, lockedProducer.unlockLevel),
          ),
        );
      }
      return MacroCannotPlan('No producer for ${itemId.localId}');
    }

    // Check if producer has prerequisites (skill level requirements)
    final prereqResult = context.ensureExecutable(
      state,
      producer,
      context.goal,
    );
    switch (prereqResult) {
      case ExecReady():
        break; // Producer is ready
      case ExecNeedsMacros(macros: final prereqMacros):
        // Return first prerequisite (don't expand recursively)
        return MacroNeedsPrerequisite(prereqMacros.first);
      case ExecUnknown(:final reason):
        return MacroCannotPlan(
          'Cannot determine prerequisites for $producer: $reason',
        );
    }

    // Check if producer has inputs (consuming action)
    final registries = state.registries;
    final producerAction = registries.actions.byId(producer) as SkillAction;
    if (producerAction.inputs.isNotEmpty) {
      // This is a consuming action - need to acquire its inputs first
      for (final inputEntry in producerAction.inputs.entries) {
        final inputId = inputEntry.key;
        final inputNeeded = inputEntry.value * quantity;
        final currentCount = state.inventory.countOfItem(
          registries.items.byId(inputId),
        );
        if (currentCount < inputNeeded) {
          // Need to acquire this input - return prerequisite
          return MacroNeedsPrerequisite(AcquireItem(inputId, inputNeeded));
        }
      }
    }

    // Producer is ready (simple action or inputs available) - switch to it
    final newState = applyInteractionDeterministic(
      state,
      SwitchActivity(producer),
    );

    // Capture start count for delta semantics
    final startCount = context.countItem(state, itemId);

    // Calculate ticks to produce the quantity
    final ticksPerAction = ticksFromDuration(producerAction.meanDuration);
    final outputsPerAction = producerAction.outputs[itemId] ?? 1;
    final actionsNeeded = (quantity / outputsPerAction).ceil();
    final ticksNeeded = actionsNeeded * ticksPerAction;

    // Project state forward (deterministic for planning)
    final advanceResult = advanceDeterministic(newState, ticksNeeded);

    // Use delta semantics: acquire quantity MORE items from startCount
    final waitFor = WaitForInventoryDelta(
      itemId,
      quantity,
      startCount: startCount,
    );

    return MacroPlanned((
      state: advanceResult.state,
      ticksElapsed: ticksNeeded,
      waitFor: waitFor,
      deaths: advanceResult.deaths,
      triggeringCondition: 'Acquired ${quantity}x ${itemId.localId}',
      macro: this,
    ));
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'AcquireItem',
    'itemId': itemId.toJson(),
    'quantity': quantity,
  };

  @override
  MacroExecuteResult execute(MacroExecuteContext context) {
    var state = context.state;
    final startCount = countItem(state, itemId);

    const goal = ReachSkillLevelGoal(Skill.mining, 99); // Placeholder goal
    final producer = findProducerActionForItem(state, itemId, goal);
    if (producer == null) {
      return MacroExecuteResult(
        state: state,
        boundary: NoProgressPossible(reason: 'No producer for $itemId'),
      );
    }

    // Switch to producer action if needed
    if (state.activeAction?.id != producer) {
      state = applyInteraction(
        state,
        SwitchActivity(producer),
        random: context.random,
      );
    }

    // Use delta-based wait condition: acquire quantity MORE items
    final waitFor = WaitForInventoryDelta(
      itemId,
      quantity,
      startCount: startCount,
    );
    final result = consumeUntil(state, waitFor, random: context.random);

    return MacroExecuteResult(
      state: result.state,
      ticksElapsed: result.ticksElapsed,
      deaths: result.deathCount,
      boundary: result.boundary,
    );
  }
}

/// Ensure inventory has at least [minTotal] of an item (absolute semantics).
///
/// Unlike [AcquireItem] which adds a delta quantity, EnsureStock targets an
/// absolute inventory count. This is useful for batch planning where we know
/// the exact total inputs needed for a craft phase.
///
/// If inventory already has >= minTotal, this is a no-op (returns
/// `MacroAlreadySatisfied` from expansion).
///
/// Used for:
/// - Batch acquisition of inputs for consuming skills
/// - Ensuring all raw materials before a craft-until-unlock phase
class EnsureStock extends MacroCandidate {
  const EnsureStock(this.itemId, this.minTotal, {super.provenance});

  /// The item to ensure stock of.
  final MelvorId itemId;

  /// The minimum total count required in inventory.
  final int minTotal;

  @override
  String get dedupeKey => 'ensure:${itemId.localId}:$minTotal';

  @override
  MacroPlanOutcome plan(MacroPlanContext context) {
    final state = context.state;
    final item = state.registries.items.byId(itemId);
    final currentCount = state.inventory.countOfItem(item);
    final deltaNeeded = minTotal - currentCount;

    if (deltaNeeded <= 0) {
      // Already have enough - this is a no-op
      if (_debugEnsureStock) {
        // We should use a logging framework or collect these in a list.
        // ignore: avoid_print
        print(
          'EnsureStock satisfied: ${itemId.localId} '
          'have=$currentCount need=$minTotal',
        );
      }
      return MacroAlreadySatisfied(
        'Already have $currentCount/$minTotal ${itemId.localId}',
      );
    }

    // Cap work-per-expansion to prevent state explosion.
    // This limits how much we produce in one expansion, not the hard minimum.
    // After producing a chunk, replanning will re-evaluate and continue.
    final chunkSize = min(deltaNeeded, MacroPlanContext.maxChunkSize);

    // Check inventory feasibility BEFORE expanding
    final feasibleBatch = context.computeFeasibleBatchSize(
      state,
      itemId,
      chunkSize,
      context.goal,
    );

    // If no batch is feasible, return boundary for solver to handle
    // The solver will compute sell policy and decide how to recover
    if (feasibleBatch == 0) {
      return MacroNeedsBoundary(
        InventoryPressure(
          usedSlots: state.inventoryUsed,
          totalSlots: state.inventoryCapacity,
          blockedItemId: itemId,
        ),
        message: 'Inventory full while stocking ${itemId.localId}',
      );
    }

    // Use the minimum of chunkSize and feasibleBatch to respect inventory
    // constraints. This ensures we don't plan a batch larger than what fits.
    final plannedBatch = min(chunkSize, feasibleBatch);

    // Use buildChainForItem to discover the full production chain
    // Use plannedBatch for planning to respect both chunk limits and inventory
    final chainResult = buildChainForItem(
      state,
      itemId,
      plannedBatch,
      context.goal,
    );

    switch (chainResult) {
      case ChainNeedsUnlock(:final skill, :final requiredLevel):
        // Return prerequisite without recursive expand
        return MacroNeedsPrerequisite(
          TrainSkillUntil(skill, StopAtLevel(skill, requiredLevel)),
        );

      case ChainFailed(:final reason):
        return MacroCannotPlan(reason);

      case ChainBuilt(:final chain):
        // Check for cycles in the chain (should not happen with correct data)
        final cycleCheck = assertNoCycles(chain);
        if (cycleCheck != null) {
          return MacroCannotPlan('Chain cycle: $cycleCheck');
        }
        // Chain is fully buildable - check if we need to stock inputs first
        // Walk the chain bottom-up and ensure stock for each level
        // Pass chunkedTarget so ProduceItem knows the per-chunk goal
        final chunkedTarget = currentCount + plannedBatch;
        return _planChainBottomUp(context, state, chain, chunkedTarget);
    }
  }

  /// Plans a production chain by ensuring inputs are stocked bottom-up.
  ///
  /// For each node in the chain (leaves first), we check if we have enough
  /// of that item. If not, we emit an EnsureStock for it.
  ///
  /// [chunkedTarget] is the inventory count to reach in this planning chunk.
  /// This may be less than [minTotal] when chunking large requirements.
  ///
  /// This replaces the old recursive "discover one input at a time" logic
  /// with explicit chain-based planning.
  MacroPlanOutcome _planChainBottomUp(
    MacroPlanContext context,
    GlobalState workingState,
    PlannedChain chain,
    int chunkedTarget,
  ) {
    // For the root node, check if all inputs are available
    // If not, emit EnsureStock for the first missing input
    for (final child in chain.children) {
      final childItem = workingState.registries.items.byId(child.itemId);
      final currentCount = workingState.inventory.countOfItem(childItem);

      if (currentCount < child.quantity) {
        // Need to stock this input first.
        // Limit the per-attempt increment to prevent state explosion from
        // unbounded EnsureStock targets. child.quantity remains the hard
        // requirement checked by the parent; attemptCap just bounds how much
        // we try to produce in one EnsureStock expansion.
        //
        // We cap attemptTarget at attemptCap to ensure quantization never
        // reduces the target (quantizeStockTarget returns >= target when
        // target <= maxChunkSize).
        const attemptCap = MacroPlanContext.maxChunkSize;
        final deltaNeeded = child.quantity - currentCount;
        // Cap the delta to limit work per EnsureStock expansion
        final cappedDelta = min(deltaNeeded, attemptCap);

        // Compute absolute target and round UP to discrete bucket.
        // Buckets: {20, 40, 80, 160, 320, 640, 1280, 1920, 2560, ...}
        // For targets <= 640: power of 2
        // For targets > 640: multiples of 640
        final rawTarget = currentCount + cappedDelta;
        int ensureStockTarget;
        if (rawTarget <= attemptCap) {
          // Use power-of-2 quantization for small targets
          final childAction =
              workingState.registries.actions.byId(child.actionId)
                  as SkillAction;
          ensureStockTarget = context.quantizeStockTarget(
            workingState,
            rawTarget,
            childAction,
          );
        } else {
          // Round up to next multiple of attemptCap for large targets
          ensureStockTarget =
              ((rawTarget + attemptCap - 1) ~/ attemptCap) * attemptCap;
        }

        // Critical invariant: target must be >= rawTarget to ensure we
        // produce enough items for the parent's requirement.
        assert(
          ensureStockTarget >= rawTarget,
          'EnsureStock target must be >= rawTarget: '
          'rawTarget=$rawTarget, ensureStockTarget=$ensureStockTarget',
        );

        // Debug: log EnsureStock creation with quantization details
        if (_debugEnsureStock) {
          // Debug print for tracing EnsureStock quantization behavior.
          // ignore: avoid_print
          print(
            'EnsureStock emit: ${child.itemId.localId} '
            'need=${child.quantity} raw=$rawTarget target=$ensureStockTarget '
            'have=$currentCount free=${workingState.inventoryRemaining}',
          );
        }
        // Return prerequisite without recursive expand
        return MacroNeedsPrerequisite(
          EnsureStock(
            child.itemId,
            ensureStockTarget,
            provenance: ChainProvenance(
              parentItem: itemId,
              childItem: child.itemId,
            ),
          ),
        );
      }
    }

    // All inputs are available - produce the target item
    final producerAction =
        workingState.registries.actions.byId(chain.actionId) as SkillAction;

    // Check skill level requirement
    final currentLevel = workingState
        .skillState(producerAction.skill)
        .skillLevel;
    if (producerAction.unlockLevel > currentLevel) {
      // Return prerequisite without recursive expand
      return MacroNeedsPrerequisite(
        TrainSkillUntil(
          producerAction.skill,
          StopAtLevel(producerAction.skill, producerAction.unlockLevel),
        ),
      );
    }

    // All prerequisites satisfied - return ProduceItem to do the actual
    // production. Use chunkedTarget to limit work per expansion.
    // This keeps EnsureStock.expand() pure (no state mutation).
    return MacroNeedsPrerequisite(
      ProduceItem(
        itemId: itemId,
        minTotal: chunkedTarget,
        actionId: chain.actionId,
        estimatedTicks: chain.ticksNeeded,
        provenance: provenance,
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'EnsureStock',
    'itemId': itemId.toJson(),
    'minTotal': minTotal,
  };

  @override
  MacroExecuteResult execute(MacroExecuteContext context) {
    // Handles inventory full by selling and continuing in a loop
    var state = context.state;
    var totalTicks = 0;
    var totalDeaths = 0;

    while (true) {
      // If we already have enough, done
      if (countItem(state, itemId) >= minTotal) {
        return MacroExecuteResult(
          state: state,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: const WaitConditionSatisfied(),
        );
      }

      const goal = ReachSkillLevelGoal(Skill.mining, 99);
      final producer = findProducerActionForItem(state, itemId, goal);
      if (producer == null) {
        return MacroExecuteResult(
          state: state,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: NoProgressPossible(reason: 'No producer for $itemId'),
        );
      }

      // Switch to producer action if needed
      if (state.activeAction?.id != producer) {
        try {
          state = applyInteraction(
            state,
            SwitchActivity(producer),
            random: context.random,
          );
        } on Exception catch (e) {
          return MacroExecuteResult(
            state: state,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: NoProgressPossible(
              reason: 'Cannot switch to producer for $itemId: $e',
            ),
          );
        }
      }

      final result = consumeUntil(
        state,
        WaitForInventoryAtLeast(itemId, minTotal),
        random: context.random,
      );

      state = result.state;
      totalTicks += result.ticksElapsed;
      totalDeaths += result.deathCount;

      // Check if we hit inventory full - sell and continue
      if (result.boundary is InventoryFull) {
        if (!_canSellToFreeSpace(context, state)) {
          return MacroExecuteResult(
            state: state,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: NoProgressPossible(
              reason:
                  'Inventory full during EnsureStock '
                  '${itemId.name} - cannot sell to free space',
            ),
          );
        }
        state = applyInteraction(
          state,
          SellItems(context.segmentSellPolicy!),
          random: context.random,
        );
        continue;
      }

      // For any other boundary or success, return
      return MacroExecuteResult(
        state: state,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: result.boundary,
      );
    }
  }

  /// Checks if we can sell items to free inventory space.
  bool _canSellToFreeSpace(MacroExecuteContext context, GlobalState state) {
    if (context.segmentSellPolicy == null) return false;
    final sellableValue =
        effectiveCredits(state, context.segmentSellPolicy!) - state.gp;
    return sellableValue > 0;
  }
}

/// Produce items via a specific action until inventory has minTotal.
///
/// This is the "executor" macro that actually does SwitchActivity + advance.
/// It is returned by [EnsureStock] when all inputs are satisfied.
///
/// Unlike [EnsureStock] (which is declarative and pure), [ProduceItem] is
/// imperative: its `expand()` DOES call `applyInteraction` and `advance`.
///
/// ## Design Rationale
///
/// Separating planning (EnsureStock) from execution (ProduceItem) ensures:
/// - `EnsureStock.expand()` remains pure (no state mutation)
/// - Time passes in exactly one place (ProduceItem.expand)
/// - The solver can see the full expansion chain before any execution
class ProduceItem extends MacroCandidate {
  const ProduceItem({
    required this.itemId,
    required this.minTotal,
    required this.actionId,
    required this.estimatedTicks,
    super.provenance,
  });

  /// The item to produce.
  final MelvorId itemId;

  /// The minimum total count required in inventory after production.
  final int minTotal;

  /// The action to use for production.
  final ActionId actionId;

  /// Estimated ticks to complete production (from chain planning).
  final int estimatedTicks;

  @override
  String get dedupeKey =>
      'produce:${itemId.localId}:$minTotal:${actionId.localId}';

  @override
  MacroPlanOutcome plan(MacroPlanContext context) {
    final state = context.state;

    // Switch to producer action (deterministic for planning)
    final newState = applyInteractionDeterministic(
      state,
      SwitchActivity(actionId),
    );

    // Advance time to produce items (deterministic for planning)
    final advanceResult = advanceDeterministic(newState, estimatedTicks);

    return MacroPlanned((
      state: advanceResult.state,
      ticksElapsed: estimatedTicks,
      waitFor: WaitForInventoryAtLeast(itemId, minTotal),
      deaths: advanceResult.deaths,
      triggeringCondition: 'Produce ${minTotal}x ${itemId.localId}',
      macro: this,
    ));
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ProduceItem',
    'itemId': itemId.toJson(),
    'minTotal': minTotal,
    'actionId': actionId.toJson(),
    'estimatedTicks': estimatedTicks,
  };

  @override
  MacroExecuteResult execute(MacroExecuteContext context) {
    var state = context.state;
    var totalTicks = 0;
    var totalDeaths = 0;

    // Switch to the producer action specified in the macro
    if (state.activeAction?.id != actionId) {
      try {
        state = applyInteraction(
          state,
          SwitchActivity(actionId),
          random: context.random,
        );
      } on Exception catch (e) {
        return MacroExecuteResult(
          state: state,
          boundary: NoProgressPossible(
            reason: 'Cannot switch to producer $actionId: $e',
          ),
        );
      }
    }

    final waitFor = WaitForInventoryAtLeast(itemId, minTotal);

    while (true) {
      // If we already have enough, done
      if (countItem(state, itemId) >= minTotal) {
        return MacroExecuteResult(
          state: state,
          ticksElapsed: totalTicks,
          deaths: totalDeaths,
          boundary: const WaitConditionSatisfied(),
        );
      }

      final result = consumeUntil(state, waitFor, random: context.random);

      state = result.state;
      totalTicks += result.ticksElapsed;
      totalDeaths += result.deathCount;

      // Check if we hit inventory full - sell and continue
      if (result.boundary is InventoryFull) {
        if (!_canSellToFreeSpace(context, state)) {
          return MacroExecuteResult(
            state: state,
            ticksElapsed: totalTicks,
            deaths: totalDeaths,
            boundary: NoProgressPossible(
              reason:
                  'Inventory full during ProduceItem '
                  '${itemId.name} - cannot sell to free space',
            ),
          );
        }
        state = applyInteraction(
          state,
          SellItems(context.segmentSellPolicy!),
          random: context.random,
        );
        continue;
      }

      // For any other boundary or success, return
      return MacroExecuteResult(
        state: state,
        ticksElapsed: totalTicks,
        deaths: totalDeaths,
        boundary: result.boundary,
      );
    }
  }

  /// Checks if we can sell items to free inventory space.
  bool _canSellToFreeSpace(MacroExecuteContext context, GlobalState state) {
    if (context.segmentSellPolicy == null) return false;
    final sellableValue =
        effectiveCredits(state, context.segmentSellPolicy!) - state.gp;
    return sellableValue > 0;
  }
}

/// Train a consuming skill via coupled produce/consume loops.
///
/// For consuming skills (Firemaking, Cooking, Smithing), this macro alternates:
/// 1. Produce inputs (e.g., cut logs, catch fish) until buffer threshold
/// 2. Consume inputs (e.g., burn logs, cook fish) until depleted
/// 3. Repeat until stop condition
///
/// This models the sustainable rate:
///   consumingXP/tick = (consumeRate * produceTime) / (produceTime + consumeTime)
///
/// ## New contract (plan-authorized execution)
///
/// The planner sets these fields to fully specify execution behavior:
/// - [consumeActionId]: the fixed consuming action (no runtime search)
/// - [producerByInputItem]: immediate producers for each consume input
/// - [bufferTarget]: quantized batch size chosen by solver
/// - [sellPolicySpec]: how to handle inventory pressure during execution
/// - [maxRecoveryAttempts]: guardrail for recovery loops
///
/// The executor adapts to randomness only by:
/// - Running until WaitFor triggers
/// - Performing explicitly authorized recovery actions (sell/bank/heal)
/// - Triggering a bounded replan using the same solver
class TrainConsumingSkillUntil extends MacroCandidate {
  const TrainConsumingSkillUntil(
    this.consumingSkill,
    this.primaryStop, {
    this.watchedStops = const [],
    this.actionId,
    this.consumeActionId,
    this.producerByInputItem,
    this.bufferTarget,
    this.sellPolicySpec,
    this.maxRecoveryAttempts = 3,
    this.inputChains,
    super.provenance,
  });

  final Skill consumingSkill;

  /// The specific consuming action to use. If null, the best action will be
  /// computed at execution time (but this may cause inconsistency if
  /// different actions become optimal mid-execution due to level-ups).
  ///
  /// @deprecated Use [consumeActionId] instead. This field exists for backward
  /// compatibility during the transition period.
  final ActionId? actionId;

  /// The fixed consuming action ID chosen during planning.
  ///
  /// When set, the executor uses this action without any runtime best-action
  /// search. This ensures deterministic execution and prevents strategy drift.
  ///
  /// If null, falls back to legacy behavior using [actionId] or runtime search.
  final ActionId? consumeActionId;

  /// Maps each input item to its immediate producer action.
  ///
  /// Example for Bronze Bar:
  /// ```dart
  /// {
  ///   MelvorId('melvorD:Copper_Ore'): ActionId(Skill.mining, 'Copper_Rocks'),
  ///   MelvorId('melvorD:Tin_Ore'): ActionId(Skill.mining, 'Tin_Rocks'),
  /// }
  /// ```
  ///
  /// The executor switches to these producers in order when inputs are needed.
  /// If null, falls back to legacy behavior (runtime producer lookup).
  final Map<MelvorId, ActionId>? producerByInputItem;

  /// The buffer threshold chosen by the solver during planning.
  ///
  /// During the produce phase, the executor gathers inputs until each reaches
  /// this count before switching to the consume phase.
  ///
  /// If null, falls back to legacy hardcoded value (10).
  final int? bufferTarget;

  /// The sell policy specification for handling inventory pressure.
  ///
  /// When inventory fills during execution, the executor uses this policy
  /// to determine which items to sell. This removes guesswork from the
  /// executor - the planner has already decided the sell strategy.
  ///
  /// If null, executor must get the policy from segment context or fail.
  final SellPolicySpec? sellPolicySpec;

  /// Maximum recovery attempts before triggering a replan.
  ///
  /// Guards against infinite recovery loops. If recovery fails this many
  /// times without meaningful progress, the executor triggers a replan.
  ///
  /// Default: 3
  final int maxRecoveryAttempts;

  /// Production chains for each input item requiring multi-tier production.
  ///
  /// For consuming skills like Smithing where inputs (bars) require their own
  /// inputs (ores), this stores the complete production chain. The executor
  /// uses this to run the correct sequence of production steps.
  ///
  /// Example for Bronze Dagger training:
  /// ```dart
  /// {
  ///   MelvorId('melvorD:Bronze_Bar'): PlannedChain(
  ///     itemId: 'Bronze_Bar',
  ///     actionId: 'Bronze Bar smelting',
  ///     children: [
  ///       PlannedChain(itemId: 'Copper_Ore', actionId: 'Copper mining'),
  ///       PlannedChain(itemId: 'Tin_Ore', actionId: 'Tin mining'),
  ///     ],
  ///   ),
  /// }
  /// ```
  ///
  /// If null or empty, falls back to single-tier producerByInputItem lookup.
  final Map<MelvorId, PlannedChain>? inputChains;

  /// Primary stop condition (usually boundary or goal).
  final MacroStopRule primaryStop;

  @override
  String get dedupeKey =>
      'trainConsuming:${consumingSkill.name}:${primaryStop.hashCode}';

  /// Additional stop conditions to watch (upgrades, etc.).
  final List<MacroStopRule> watchedStops;

  /// All stop conditions (primary + watched).
  List<MacroStopRule> get allStops => [primaryStop, ...watchedStops];

  @override
  MacroPlanOutcome plan(MacroPlanContext context) {
    final state = context.state;
    final registries = state.registries;
    final actionRegistry = registries.actions;
    final itemRegistry = registries.items;

    // Find best unlocked consuming action
    final bestConsumeAction = findBestActionForSkill(
      state,
      consumingSkill,
      context.goal,
    );

    if (bestConsumeAction == null) {
      return MacroCannotPlan('No unlocked action for ${consumingSkill.name}');
    }

    // Get the consuming action to find its inputs
    final consumeAction = actionRegistry.byId(bestConsumeAction);
    if (consumeAction is! SkillAction || consumeAction.inputs.isEmpty) {
      return MacroCannotPlan(
        'Action $bestConsumeAction is not a valid consuming action',
      );
    }

    // Check ALL inputs and gather prerequisites
    final allPrereqs = <MacroCandidate>[];
    ActionId? primaryProducerAction;

    // Minimum buffer to start execution - once we have this much, proceed.
    // This prevents infinite escalation where each boundary requires more.
    const minBufferToStart = 20;

    for (final inputEntry in consumeAction.inputs.entries) {
      final inputItem = inputEntry.key;
      final inputItemData = itemRegistry.byId(inputItem);
      final currentCount = state.inventory.countOfItem(inputItemData);
      final producer = context.findProducerAction(
        state,
        inputItem,
        context.goal,
      );

      if (producer == null) {
        // Check if a locked producer exists - may need skill training
        final lockedProducer = context.findAnyProducer(state, inputItem);
        if (lockedProducer != null) {
          // Need to train skill first
          allPrereqs.add(
            TrainSkillUntil(
              lockedProducer.skill,
              StopAtLevel(lockedProducer.skill, lockedProducer.unlockLevel),
            ),
          );
        } else {
          return MacroCannotPlan('No producer for input ${inputItem.localId}');
        }
      } else {
        // Check if producer has inputs (multi-tier chain)
        final producerActionData = actionRegistry.byId(producer);
        if (producerActionData is SkillAction &&
            producerActionData.inputs.isNotEmpty) {
          // Multi-tier chain - only require minimum buffer to start.
          // Once we have minBufferToStart, proceed to execution.
          // The coupled loop will produce more as needed.
          if (currentCount < minBufferToStart) {
            // Use discrete bucket for the minimum buffer
            final target = MacroPlanContext.discreteHardTarget(
              minBufferToStart,
            );
            // INVARIANT: TCU prereq targets are bounded by minBufferToStart's
            // discrete bucket, preventing escalation across re-expansions.
            assert(
              target == 20, // discreteHardTarget(20) == 20
              'TCU prereq target should be exactly 20 for minBufferToStart=20, '
              'got $target',
            );
            allPrereqs.add(EnsureStock(inputItem, target));
          }
        } else {
          // Simple producer (no inputs, e.g., Mining) - check prerequisites
          final prereqResult = context.ensureExecutable(
            state,
            producer,
            context.goal,
          );
          switch (prereqResult) {
            case ExecReady():
              // Producer is ready - only require minimum buffer to start
              if (currentCount < minBufferToStart) {
                final target = MacroPlanContext.discreteHardTarget(
                  minBufferToStart,
                );
                // INVARIANT: Same as multi-tier case - bounded prereqs.
                assert(
                  target == 20,
                  'TCU prereq target should be exactly 20 for '
                  'minBufferToStart=20, got $target',
                );
                allPrereqs.add(EnsureStock(inputItem, target));
              }
            case ExecNeedsMacros(macros: final prereqMacros):
              allPrereqs.addAll(prereqMacros);
            case ExecUnknown(:final reason):
              return MacroCannotPlan(
                'Cannot determine prerequisites for $producer: $reason',
              );
          }
          primaryProducerAction ??= producer;
        }
      }
    }

    // If prerequisites exist, return the first one (don't expand recursively)
    if (allPrereqs.isNotEmpty) {
      return MacroNeedsPrerequisite(allPrereqs.first);
    }

    // All prerequisites satisfied - find a producer action
    var producerAction = primaryProducerAction;
    if (producerAction == null) {
      // Find a producer that doesn't require inputs
      for (final inputEntry in consumeAction.inputs.entries) {
        final inputItemId = inputEntry.key;
        final producer = context.findProducerAction(
          state,
          inputItemId,
          context.goal,
        );
        if (producer == null) continue;
        final producerActionData = actionRegistry.byId(producer);
        if (producerActionData is SkillAction) {
          if (producerActionData.inputs.isEmpty) {
            producerAction = producer;
            break;
          } else {
            // Look for sub-producers
            for (final subInput in producerActionData.inputs.keys) {
              final subProducer = context.findProducerAction(
                state,
                subInput,
                context.goal,
              );
              if (subProducer != null) {
                final subProdData = actionRegistry.byId(subProducer);
                if (subProdData is SkillAction && subProdData.inputs.isEmpty) {
                  producerAction = subProducer;
                  break;
                }
              }
            }
            if (producerAction != null) break;
          }
        }
      }
    }

    if (producerAction == null) {
      return MacroCannotPlan(
        'No simple producer found for ${consumingSkill.name}',
      );
    }

    // Switch to producer action for state projection (deterministic)
    final producerState = applyInteractionDeterministic(
      state,
      SwitchActivity(producerAction),
    );

    // Build stop condition
    final waitFor = primaryStop.toWaitFor(producerState, context.boundaries);

    // Calculate sustainable XP rate
    final consumeTicksPerAction = ticksFromDuration(
      consumeAction.meanDuration,
    ).toDouble();

    // Calculate total production time for ALL inputs
    var totalProduceTicksPerCycle = 0.0;
    for (final inputEntry in consumeAction.inputs.entries) {
      final inputItemId = inputEntry.key;
      final inputCount = inputEntry.value;
      final producer = context.findProducerAction(
        state,
        inputItemId,
        context.goal,
      );
      if (producer == null) continue;
      final produceAction = actionRegistry.byId(producer) as SkillAction;
      final outputsPerAction = produceAction.outputs[inputItemId] ?? 1;
      final produceActionsNeeded = inputCount / outputsPerAction;
      totalProduceTicksPerCycle +=
          produceActionsNeeded *
          ticksFromDuration(produceAction.meanDuration).toDouble();
    }

    final totalTicksPerCycle =
        totalProduceTicksPerCycle + consumeTicksPerAction;
    final consumeXpPerAction = consumeAction.xp.toDouble();
    final sustainableXpPerTick = consumeXpPerAction / totalTicksPerCycle;

    // Calculate ticks needed
    final currentXp = state.skillState(consumingSkill).xp;
    int ticksUntilStop;

    if (waitFor is WaitForSkillXp) {
      final xpNeeded = (waitFor.targetXp - currentXp).toDouble();
      if (xpNeeded <= 0) {
        return MacroAlreadySatisfied(
          'XP goal already satisfied for ${consumingSkill.name}',
        );
      }
      ticksUntilStop = (xpNeeded / sustainableXpPerTick).ceil();
    } else {
      final consumeRates = estimateRatesForAction(state, bestConsumeAction);
      final estimatedTicks = waitFor.estimateTicks(producerState, consumeRates);
      if (estimatedTicks <= 0) {
        return MacroAlreadySatisfied(
          'Stop condition already satisfied for ${consumingSkill.name}',
        );
      }
      if (estimatedTicks >= infTicks) {
        return MacroCannotPlan(
          'No progress possible for ${consumingSkill.name} (infinite ticks)',
        );
      }
      final consumeXpPerTick = consumeAction.xp / consumeTicksPerAction;
      final slowdownFactor = sustainableXpPerTick / consumeXpPerTick;
      ticksUntilStop = (estimatedTicks / slowdownFactor).ceil();
    }

    // Calculate projected XP
    final consumingSkillXp =
        currentXp + (sustainableXpPerTick * ticksUntilStop).floor();

    // Calculate producer skill XP gains
    final numCycles = ticksUntilStop / totalTicksPerCycle;
    final producerSkillXpGains = <Skill, int>{};

    for (final inputEntry in consumeAction.inputs.entries) {
      final inputItemId = inputEntry.key;
      final inputCount = inputEntry.value;
      final producer = context.findProducerAction(
        state,
        inputItemId,
        context.goal,
      );
      if (producer == null) continue;
      final produceAction = actionRegistry.byId(producer) as SkillAction;
      final outputsPerAction = produceAction.outputs[inputItemId] ?? 1;
      final produceActionsNeeded = inputCount / outputsPerAction;
      final produceTicksPerAction = ticksFromDuration(
        produceAction.meanDuration,
      ).toDouble();

      final ticksForThisProducerPerCycle =
          produceActionsNeeded * produceTicksPerAction;
      final totalTicksForThisProducer =
          numCycles * ticksForThisProducerPerCycle;
      final xpGained =
          (totalTicksForThisProducer *
                  (produceAction.xp / produceTicksPerAction))
              .floor();

      producerSkillXpGains[produceAction.skill] =
          (producerSkillXpGains[produceAction.skill] ?? 0) + xpGained;
    }

    // Build projected state
    final produceAction_ =
        state.registries.actions.byId(producerAction) as SkillAction;
    final projectedState = state.copyWith(
      skillStates: {
        for (final skill in Skill.values)
          skill: skill == consumingSkill
              ? SkillState(
                  xp: consumingSkillXp,
                  masteryPoolXp: state.skillState(skill).masteryPoolXp,
                )
              : producerSkillXpGains.containsKey(skill)
              ? SkillState(
                  xp: state.skillState(skill).xp + producerSkillXpGains[skill]!,
                  masteryPoolXp: state.skillState(skill).masteryPoolXp,
                )
              : state.skillState(skill),
      },
      activeAction: ActiveAction(
        id: producerAction,
        remainingTicks: ticksFromDuration(produceAction_.meanDuration),
        totalTicks: ticksFromDuration(produceAction_.meanDuration),
      ),
    );

    // Calculate buffer target first (needed for chain sizing)
    final computedBufferTarget = context.quantizeStockTarget(
      state,
      10,
      consumeAction,
    );

    // Build producerByInputItem map and inputChains for multi-tier production
    final producerByInputItemMap = <MelvorId, ActionId>{};
    final inputChainsMap = <MelvorId, PlannedChain>{};

    for (final inputEntry in consumeAction.inputs.entries) {
      final inputItemId = inputEntry.key;
      final inputQty = inputEntry.value;

      // Use buildChainForItem to get the full production chain
      // Use buffer target quantity for chain sizing
      final chainResult = buildChainForItem(
        state,
        inputItemId,
        computedBufferTarget * inputQty,
        context.goal,
      );

      switch (chainResult) {
        case ChainBuilt(:final chain):
          // Store the chain for multi-tier inputs
          if (!chain.isLeaf) {
            inputChainsMap[inputItemId] = chain;
          }
          // The immediate producer is the chain's action
          producerByInputItemMap[inputItemId] = chain.actionId;

        case ChainNeedsUnlock():
          // Should have been caught earlier in prerequisite checking
          // Fall back to simple lookup
          final producer = context.findProducerAction(
            state,
            inputItemId,
            context.goal,
          );
          if (producer != null) {
            producerByInputItemMap[inputItemId] = producer;
          }

        case ChainFailed():
          // Fall back to simple lookup
          final producer = context.findProducerAction(
            state,
            inputItemId,
            context.goal,
          );
          if (producer != null) {
            producerByInputItemMap[inputItemId] = producer;
          }
      }
    }

    // Determine sell policy spec
    final sellPolicySpecValue = context.goal.isSellRelevant
        ? const SellAllSpec()
        : const ReserveConsumingInputsSpec();

    // Create enriched macro with inputChains for multi-tier production
    final enrichedMacro = TrainConsumingSkillUntil(
      consumingSkill,
      primaryStop,
      watchedStops: watchedStops,
      actionId: actionId,
      consumeActionId: bestConsumeAction,
      producerByInputItem: producerByInputItemMap,
      bufferTarget: computedBufferTarget,
      sellPolicySpec: sellPolicySpecValue,
      inputChains: inputChainsMap.isEmpty ? null : inputChainsMap,
    );

    return MacroPlanned((
      state: projectedState,
      ticksElapsed: ticksUntilStop,
      waitFor: waitFor,
      deaths: 0,
      triggeringCondition: waitFor.shortDescription,
      macro: enrichedMacro,
    ));
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'TrainConsumingSkillUntil',
    'consumingSkill': consumingSkill.name,
    'primaryStop': primaryStop.toJson(),
    'watchedStops': watchedStops.map((s) => s.toJson()).toList(),
    if (actionId != null) 'actionId': actionId!.toJson(),
    if (consumeActionId != null) 'consumeActionId': consumeActionId!.toJson(),
    if (producerByInputItem != null)
      'producerByInputItem': {
        for (final entry in producerByInputItem!.entries)
          entry.key.toJson(): entry.value.toJson(),
      },
    if (bufferTarget != null) 'bufferTarget': bufferTarget,
    if (sellPolicySpec != null) 'sellPolicySpec': sellPolicySpec!.toJson(),
    'maxRecoveryAttempts': maxRecoveryAttempts,
    if (inputChains != null)
      'inputChains': {
        for (final entry in inputChains!.entries)
          entry.key.toJson(): entry.value.toJson(),
      },
  };

  @override
  MacroExecuteResult execute(MacroExecuteContext context) {
    final stepResult = executeCoupledLoop(context, this);
    return MacroExecuteResult(
      state: stepResult.state,
      ticksElapsed: stepResult.ticksElapsed,
      deaths: stepResult.deaths,
      boundary: stepResult.boundary,
    );
  }
}

/// Stop conditions for macro training.
///
/// Each rule knows how to convert itself to a WaitFor for plan execution.
sealed class MacroStopRule extends Equatable {
  const MacroStopRule();

  /// Convert this stop rule to a WaitFor for plan execution.
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries);

  /// Serializes this [MacroStopRule] to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes a [MacroStopRule] from a JSON-compatible map.
  static MacroStopRule fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'StopAtNextBoundary' => StopAtNextBoundary(
        Skill.fromName(json['skill'] as String),
      ),
      'StopAtGoal' => StopAtGoal(
        Skill.fromName(json['skill'] as String),
        json['targetXp'] as int,
      ),
      'StopAtLevel' => StopAtLevel(
        Skill.fromName(json['skill'] as String),
        json['level'] as int,
      ),
      'StopWhenUpgradeAffordable' => StopWhenUpgradeAffordable(
        MelvorId.fromJson(json['purchaseId'] as String),
        json['cost'] as int,
        json['upgradeName'] as String,
      ),
      'StopWhenInputsDepleted' => const StopWhenInputsDepleted(),
      _ => throw ArgumentError('Unknown MacroStopRule type: $type'),
    };
  }
}

/// Stop at the next unlock boundary for this skill.
///
/// Boundaries are levels where new actions become available.
class StopAtNextBoundary extends MacroStopRule {
  const StopAtNextBoundary(this.skill);

  final Skill skill;

  @override
  List<Object?> get props => [skill];

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    final currentLevel = state.skillState(skill).skillLevel;
    final nextBoundary = boundaries[skill]?.nextBoundary(currentLevel);
    final targetLevel = nextBoundary ?? 99;
    final targetXp = startXpForLevel(targetLevel);

    return WaitForSkillXp(skill, targetXp, reason: 'Boundary L$targetLevel');
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'StopAtNextBoundary',
    'skill': skill.name,
  };
}

/// Stop when skill reaches goal level.
class StopAtGoal extends MacroStopRule {
  const StopAtGoal(this.skill, this.targetXp);

  final Skill skill;
  final int targetXp;

  @override
  List<Object?> get props => [skill, targetXp];

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    return WaitForSkillXp(skill, targetXp, reason: 'Goal reached');
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'StopAtGoal',
    'skill': skill.name,
    'targetXp': targetXp,
  };
}

/// Stop when skill reaches a specific level.
///
/// Used for prerequisite training (e.g., "train Mining to 50" to unlock
/// Mithril Ore before smithing Mithril Bars).
class StopAtLevel extends MacroStopRule {
  const StopAtLevel(this.skill, this.level);

  final Skill skill;
  final int level;

  @override
  List<Object?> get props => [skill, level];

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    return WaitForSkillXp(
      skill,
      startXpForLevel(level),
      reason: 'Unlock L$level',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'StopAtLevel',
    'skill': skill.name,
    'level': level,
  };
}

/// Stop when upgrade becomes affordable.
///
/// Used to allow early purchase of valuable upgrades before reaching
/// the next boundary.
class StopWhenUpgradeAffordable extends MacroStopRule {
  const StopWhenUpgradeAffordable(this.purchaseId, this.cost, this.upgradeName);

  final MelvorId purchaseId;
  final int cost;
  final String upgradeName;

  @override
  List<Object?> get props => [purchaseId, cost, upgradeName];

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    // Use SellAllPolicy as a conservative default - upgrade affordability
    // is typically checked with full liquidation potential.
    return WaitForEffectiveCredits(
      cost,
      sellPolicy: const SellAllPolicy(),
      reason: upgradeName,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'StopWhenUpgradeAffordable',
    'purchaseId': purchaseId.toJson(),
    'cost': cost,
    'upgradeName': upgradeName,
  };
}

/// Stop when inputs are depleted (for consuming actions like Firemaking).
///
/// This ensures the macro doesn't continue when there are no logs/fish to
/// consume, allowing the solver to switch to a producer action.
///
/// Note: This uses the active action from the state at toWaitFor() time,
/// not a fixed action ID, to handle cases where the best action changes
/// (e.g., Normal Logs -> Oak Logs as Firemaking level increases).
class StopWhenInputsDepleted extends MacroStopRule {
  const StopWhenInputsDepleted();

  @override
  List<Object?> get props => [];

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    // Use the currently active action, which may have changed since planning
    final activeActionId = state.activeAction?.id;
    if (activeActionId == null) {
      // No active action - this should never happen during macro execution
      // but return a no-op condition as fallback
      throw StateError('StopWhenInputsDepleted called with no active action');
    }
    return WaitForInputsDepleted(activeActionId);
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'StopWhenInputsDepleted'};
}

// ---------------------------------------------------------------------------
// Macro Plan Outcomes
// ---------------------------------------------------------------------------

/// Result of planning a macro into concrete execution steps.
typedef MacroPlanResult = ({
  GlobalState state,
  int ticksElapsed,
  WaitFor waitFor,
  int deaths,
  String? triggeringCondition,
  MacroCandidate macro,
});

/// Outcome of attempting to plan a macro - tri-state result.
///
/// This ensures we always know WHY planning failed, rather than silently
/// returning null.
sealed class MacroPlanOutcome {
  const MacroPlanOutcome();
}

/// Macro planned successfully to a future state.
class MacroPlanned extends MacroPlanOutcome {
  const MacroPlanned(this.result);
  final MacroPlanResult result;
}

/// Macro is already satisfied - no planning needed (legitimate no-op).
///
/// This is different from failure: the macro's goal is already met,
/// so there's nothing to plan.
class MacroAlreadySatisfied extends MacroPlanOutcome {
  const MacroAlreadySatisfied(this.reason);
  final String reason;
}

/// Macro cannot be planned due to missing prerequisites or unsatisfiable
/// constraints.
class MacroCannotPlan extends MacroPlanOutcome {
  const MacroCannotPlan(this.reason);
  final String reason;
}

/// Macro planning requires another macro to be satisfied first.
///
/// Unlike recursive `prereq.plan(context)`, this returns the dependency
/// without planning it. The solver's outer loop handles planning ordering.
///
/// This keeps `plan()` non-recursive and allows the solver to:
/// - Order planning globally (not depth-first)
/// - Detect cycles across the full planning queue
/// - Make prerequisites visible in the planning trace
class MacroNeedsPrerequisite extends MacroPlanOutcome {
  const MacroNeedsPrerequisite(this.prerequisite);

  /// The macro that must be planned before retrying this one.
  final MacroCandidate prerequisite;
}

/// Macro planning is blocked by a condition requiring external handling.
///
/// Unlike [MacroNeedsPrerequisite] (which emits another macro to plan),
/// this signals that planning cannot continue until something external
/// happens (e.g., sell items to free inventory space).
///
/// The solver/executor should handle the boundary appropriately:
/// - [InventoryPressure]: Execute sell policy, then retry planning
/// - Other boundaries: Bubble up for caller handling
class MacroNeedsBoundary extends MacroPlanOutcome {
  const MacroNeedsBoundary(this.boundary, {this.message});

  /// The boundary that must be handled before retrying planning.
  final ReplanBoundary boundary;

  /// Optional explanation for debugging.
  final String? message;
}

// ---------------------------------------------------------------------------
// Macro Execute Result (Execution Time)
// ---------------------------------------------------------------------------

/// Result of executing a macro with stochastic simulation.
///
/// This is the execution-time counterpart to [MacroPlanResult], which
/// uses expected-value modeling for planning. [MacroExecuteResult] contains
/// actual simulation results with randomness.
class MacroExecuteResult {
  const MacroExecuteResult({
    required this.state,
    this.ticksElapsed = 0,
    this.deaths = 0,
    this.boundary,
  });

  /// The game state after executing the macro.
  final GlobalState state;

  /// Number of ticks elapsed during macro execution.
  final int ticksElapsed;

  /// Number of deaths that occurred during macro execution.
  final int deaths;

  /// The boundary hit during execution, if any.
  ///
  /// Null means normal completion. Various boundary types indicate
  /// different outcomes (goal reached, inputs depleted, etc.).
  final ReplanBoundary? boundary;
}
