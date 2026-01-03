/// Macro-level planning primitives for solver.
///
/// Macros represent "train until boundary/goal/upgrade" decisions that span
/// many ticks, reducing the solver's branching factor and state explosion.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/next_decision_delta.dart'
    show infTicks;
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/build_chain.dart';
import 'package:logic/src/solver/candidates/macro_expansion_context.dart';
import 'package:logic/src/solver/execution/state_advance.dart';
import 'package:logic/src/solver/interactions/apply_interaction.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart' show ticksFromDuration;

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
sealed class MacroCandidate {
  const MacroCandidate({this.provenance});

  /// Why this macro was created (for debugging/explanation).
  final MacroProvenance? provenance;

  /// Unique key for deduplication purposes.
  ///
  /// Two macros with the same key are considered equivalent for planning,
  /// allowing the solver to eliminate duplicates.
  String get dedupeKey;

  /// Expands this macro into concrete execution steps.
  ///
  /// Returns [MacroExpanded] on success, [MacroAlreadySatisfied] if no work
  /// needed, or [MacroCannotExpand] with a reason if expansion is impossible.
  MacroExpansionOutcome expand(MacroExpansionContext context);

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
  MacroExpansionOutcome expand(MacroExpansionContext context) {
    final state = context.state;

    // Find best unlocked action for this skill
    final bestAction = context.findBestActionForSkill(
      state,
      skill,
      context.goal,
    );
    if (bestAction == null) {
      return MacroCannotExpand('No unlocked action for ${skill.name}');
    }

    // Switch to that action (if not already on it)
    var currentState = state;
    if (state.activeAction?.id != bestAction) {
      currentState = applyInteraction(
        state,
        SwitchActivity(bestAction),
        random: context.random,
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
      return MacroCannotExpand(
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

    // Use expected-value advance
    final advanceResult = advance(
      currentState,
      ticksUntilStop,
      random: context.random,
    );

    // Create enriched macro with the specific action we chose
    final enrichedMacro = TrainSkillUntil(
      skill,
      primaryStop,
      watchedStops: watchedStops,
      actionId: bestAction,
    );

    return MacroExpanded((
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
  MacroExpansionOutcome expand(MacroExpansionContext context) {
    final state = context.state;

    // Find producer for this item
    final producer = context.findProducerActionForItem(
      state,
      itemId,
      context.goal,
    );

    if (producer == null) {
      // Check if a locked producer exists
      final lockedProducer = context.findAnyProducerForItem(state, itemId);
      if (lockedProducer != null) {
        // Need to train skill first - expand that prerequisite
        final trainMacro = TrainSkillUntil(
          lockedProducer.skill,
          StopAtLevel(lockedProducer.skill, lockedProducer.unlockLevel),
        );
        return trainMacro.expand(context);
      }
      return MacroCannotExpand('No producer for ${itemId.localId}');
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
        // Expand the first prerequisite
        return prereqMacros.first.expand(context);
      case ExecUnknown(:final reason):
        return MacroCannotExpand(
          'Cannot determine prerequisites for $producer: $reason',
        );
    }

    // Check if producer has inputs (consuming action)
    final producerAction =
        state.registries.actions.byId(producer) as SkillAction;
    if (producerAction.inputs.isNotEmpty) {
      // This is a consuming action - need to acquire its inputs first
      for (final inputEntry in producerAction.inputs.entries) {
        final inputId = inputEntry.key;
        final inputNeeded = inputEntry.value * quantity;
        final currentCount = state.inventory.countOfItem(
          state.registries.items.byId(inputId),
        );
        if (currentCount < inputNeeded) {
          // Need to acquire this input
          final acquireInput = AcquireItem(inputId, inputNeeded);
          return acquireInput.expand(context);
        }
      }
    }

    // Producer is ready (simple action or inputs available) - switch to it
    final newState = applyInteraction(
      state,
      SwitchActivity(producer),
      random: context.random,
    );

    // Capture start count for delta semantics
    final startCount = context.countItem(state, itemId);

    // Calculate ticks to produce the quantity
    final ticksPerAction = ticksFromDuration(producerAction.meanDuration);
    final outputsPerAction = producerAction.outputs[itemId] ?? 1;
    final actionsNeeded = (quantity / outputsPerAction).ceil();
    final ticksNeeded = actionsNeeded * ticksPerAction;

    // Project state forward
    final advanceResult = advance(
      newState,
      ticksNeeded,
      random: context.random,
    );

    // Use delta semantics: acquire quantity MORE items from startCount
    final waitFor = WaitForInventoryDelta(
      itemId,
      quantity,
      startCount: startCount,
    );

    return MacroExpanded((
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
  MacroExpansionOutcome expand(MacroExpansionContext context) {
    final state = context.state;
    final item = state.registries.items.byId(itemId);
    final currentCount = state.inventory.countOfItem(item);
    final deltaNeeded = minTotal - currentCount;

    if (deltaNeeded <= 0) {
      // Already have enough - this is a no-op
      return MacroAlreadySatisfied(
        'Already have $currentCount/$minTotal ${itemId.localId}',
      );
    }

    // Check inventory feasibility BEFORE expanding
    final feasibleBatch = context.computeFeasibleBatchSize(
      state,
      itemId,
      deltaNeeded,
      context.goal,
    );

    // If no batch is feasible and inventory is nearly full, sell first
    var workingState = state;
    if (feasibleBatch == 0 && state.inventoryRemaining <= 2) {
      // Inventory is too full - need to sell before we can produce
      final sellPolicy = context.goal.computeSellPolicy(state);
      final sellableValue = effectiveCredits(state, sellPolicy) - state.gp;

      if (sellableValue > 0) {
        // Apply sell interaction to free up inventory space, then continue
        workingState = applyInteraction(
          state,
          SellItems(sellPolicy),
          random: context.random,
        );
      } else {
        // Nothing to sell - truly stuck
        return MacroCannotExpand(
          'Inventory full (${state.inventoryUsed}/${state.inventoryCapacity}) '
          'and nothing to sell for ${itemId.localId}',
        );
      }
    }

    // Use buildChainForItem to discover the full production chain
    final chainResult = buildChainForItem(
      workingState,
      itemId,
      deltaNeeded,
      context.goal,
    );

    switch (chainResult) {
      case ChainNeedsUnlock(:final skill, :final requiredLevel):
        // Need to train skill first - expand that prerequisite
        final trainMacro = TrainSkillUntil(
          skill,
          StopAtLevel(skill, requiredLevel),
        );
        return trainMacro.expand(context.withState(workingState));

      case ChainFailed(:final reason):
        return MacroCannotExpand(reason);

      case ChainBuilt(:final chain):
        // Chain is fully buildable - check if we need to stock inputs first
        // Walk the chain bottom-up and ensure stock for each level
        return _expandChainBottomUp(context, workingState, chain);
    }
  }

  /// Expands a production chain by ensuring inputs are stocked bottom-up.
  ///
  /// For each node in the chain (leaves first), we check if we have enough
  /// of that item. If not, we emit an EnsureStock for it.
  ///
  /// This replaces the old recursive "discover one input at a time" logic
  /// with explicit chain-based expansion.
  MacroExpansionOutcome _expandChainBottomUp(
    MacroExpansionContext context,
    GlobalState workingState,
    PlannedChain chain,
  ) {
    // For the root node, check if all inputs are available
    // If not, emit EnsureStock for the first missing input
    for (final child in chain.children) {
      final childItem = workingState.registries.items.byId(child.itemId);
      final currentCount = workingState.inventory.countOfItem(childItem);

      if (currentCount < child.quantity) {
        // Need to stock this input first
        // Quantize the target to reduce plan thrash
        final producerAction =
            workingState.registries.actions.byId(chain.actionId) as SkillAction;
        final quantizedTarget = context.quantizeStockTarget(
          workingState,
          child.quantity,
          producerAction,
        );
        final stockMacro = EnsureStock(
          child.itemId,
          quantizedTarget,
          provenance: ChainProvenance(
            parentItem: itemId,
            childItem: child.itemId,
          ),
        );
        return stockMacro.expand(context.withState(workingState));
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
      final trainMacro = TrainSkillUntil(
        producerAction.skill,
        StopAtLevel(producerAction.skill, producerAction.unlockLevel),
      );
      return trainMacro.expand(context.withState(workingState));
    }

    // Producer is ready - switch to it and produce
    final newState = applyInteraction(
      workingState,
      SwitchActivity(chain.actionId),
      random: context.random,
    );

    // Calculate ticks to produce using chain's precomputed values
    final ticksNeeded = chain.ticksNeeded;

    // Project state forward
    final advanceResult = advance(
      newState,
      ticksNeeded,
      random: context.random,
    );

    // Use absolute semantics: wait until we have minTotal
    final waitFor = WaitForInventoryAtLeast(itemId, minTotal);

    return MacroExpanded((
      state: advanceResult.state,
      ticksElapsed: ticksNeeded,
      waitFor: waitFor,
      deaths: advanceResult.deaths,
      triggeringCondition: 'Stock ${minTotal}x ${itemId.localId}',
      macro: this,
    ));
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'EnsureStock',
    'itemId': itemId.toJson(),
    'minTotal': minTotal,
  };
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

  /// Creates a copy with updated fields.
  ///
  /// Used by the solver to fill in execution details after initial creation.
  TrainConsumingSkillUntil copyWith({
    ActionId? consumeActionId,
    Map<MelvorId, ActionId>? producerByInputItem,
    int? bufferTarget,
    SellPolicySpec? sellPolicySpec,
    int? maxRecoveryAttempts,
    List<MacroStopRule>? watchedStops,
    Map<MelvorId, PlannedChain>? inputChains,
  }) {
    return TrainConsumingSkillUntil(
      consumingSkill,
      primaryStop,
      watchedStops: watchedStops ?? this.watchedStops,
      actionId: actionId,
      consumeActionId: consumeActionId ?? this.consumeActionId,
      producerByInputItem: producerByInputItem ?? this.producerByInputItem,
      bufferTarget: bufferTarget ?? this.bufferTarget,
      sellPolicySpec: sellPolicySpec ?? this.sellPolicySpec,
      maxRecoveryAttempts: maxRecoveryAttempts ?? this.maxRecoveryAttempts,
      inputChains: inputChains ?? this.inputChains,
      provenance: provenance,
    );
  }

  @override
  MacroExpansionOutcome expand(MacroExpansionContext context) {
    final state = context.state;

    // Find best unlocked consuming action
    final bestConsumeAction = context.findBestActionForSkill(
      state,
      consumingSkill,
      context.goal,
    );
    if (bestConsumeAction == null) {
      return MacroCannotExpand('No unlocked action for ${consumingSkill.name}');
    }

    // Get the consuming action to find its inputs
    final consumeAction = state.registries.actions.byId(bestConsumeAction);
    if (consumeAction is! SkillAction || consumeAction.inputs.isEmpty) {
      return MacroCannotExpand(
        'Action $bestConsumeAction is not a valid consuming action',
      );
    }

    // Check ALL inputs and gather prerequisites
    final allPrereqs = <MacroCandidate>[];
    ActionId? primaryProducerAction;

    for (final inputEntry in consumeAction.inputs.entries) {
      final inputItem = inputEntry.key;
      final producer = context.findProducerActionForItem(
        state,
        inputItem,
        context.goal,
      );

      if (producer == null) {
        // Check if a locked producer exists - may need skill training
        final lockedProducer = context.findAnyProducerForItem(state, inputItem);
        if (lockedProducer != null) {
          // Need to train skill first
          allPrereqs.add(
            TrainSkillUntil(
              lockedProducer.skill,
              StopAtLevel(lockedProducer.skill, lockedProducer.unlockLevel),
            ),
          );
        } else {
          return MacroCannotExpand(
            'No producer for input ${inputItem.localId}',
          );
        }
      } else {
        // Check if producer has inputs (multi-tier chain)
        final producerActionData = state.registries.actions.byId(producer);
        if (producerActionData is SkillAction &&
            producerActionData.inputs.isNotEmpty) {
          // Multi-tier chain - compute batch size
          final batch = context.computeBatchToNextUnlock(
            state: state,
            consumingAction: consumeAction,
            boundaries: context.boundaries,
          );

          if (batch != null) {
            final inputNeeded = batch.inputRequirements[inputItem] ?? 0;
            final inputItemData = state.registries.items.byId(inputItem);
            final currentCount = state.inventory.countOfItem(inputItemData);
            if (inputNeeded > 0 && currentCount < inputNeeded) {
              final quantizedTarget = context.quantizeStockTarget(
                state,
                inputNeeded,
                consumeAction,
              );
              allPrereqs.add(EnsureStock(inputItem, quantizedTarget));
            }
          } else {
            // Fallback: near goal or no boundary, use smaller batches
            const bufferSize = 10;
            final inputItemData = state.registries.items.byId(inputItem);
            final currentCount = state.inventory.countOfItem(inputItemData);
            if (currentCount < bufferSize) {
              allPrereqs.add(AcquireItem(inputItem, bufferSize - currentCount));
            }
          }
        } else {
          // Simple producer - check prerequisites
          final prereqResult = context.ensureExecutable(
            state,
            producer,
            context.goal,
          );
          switch (prereqResult) {
            case ExecReady():
              break;
            case ExecNeedsMacros(macros: final prereqMacros):
              allPrereqs.addAll(prereqMacros);
            case ExecUnknown(:final reason):
              return MacroCannotExpand(
                'Cannot determine prerequisites for $producer: $reason',
              );
          }
          primaryProducerAction ??= producer;
        }
      }
    }

    // If prerequisites exist, expand the first one
    if (allPrereqs.isNotEmpty) {
      return allPrereqs.first.expand(context);
    }

    // All prerequisites satisfied - find a producer action
    var producerAction = primaryProducerAction;
    if (producerAction == null) {
      // Find a producer that doesn't require inputs
      for (final inputEntry in consumeAction.inputs.entries) {
        final inputItemId = inputEntry.key;
        final producer = context.findProducerActionForItem(
          state,
          inputItemId,
          context.goal,
        );
        if (producer == null) continue;
        final producerActionData = state.registries.actions.byId(producer);
        if (producerActionData is SkillAction) {
          if (producerActionData.inputs.isEmpty) {
            producerAction = producer;
            break;
          } else {
            // Look for sub-producers
            for (final subInput in producerActionData.inputs.keys) {
              final subProducer = context.findProducerActionForItem(
                state,
                subInput,
                context.goal,
              );
              if (subProducer != null) {
                final subProdData = state.registries.actions.byId(subProducer);
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
      return MacroCannotExpand(
        'No simple producer found for ${consumingSkill.name}',
      );
    }

    // Switch to producer action for state projection
    final producerState = applyInteraction(
      state,
      SwitchActivity(producerAction),
      random: context.random,
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
      final producer = context.findProducerActionForItem(
        state,
        inputItemId,
        context.goal,
      );
      if (producer == null) continue;
      final produceAction =
          state.registries.actions.byId(producer) as SkillAction;
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
        return MacroCannotExpand(
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
      final producer = context.findProducerActionForItem(
        state,
        inputItemId,
        context.goal,
      );
      if (producer == null) continue;
      final produceAction =
          state.registries.actions.byId(producer) as SkillAction;
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
          final producer = context.findProducerActionForItem(
            state,
            inputItemId,
            context.goal,
          );
          if (producer != null) {
            producerByInputItemMap[inputItemId] = producer;
          }

        case ChainFailed():
          // Fall back to simple lookup
          final producer = context.findProducerActionForItem(
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

    return MacroExpanded((
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
}

/// Stop conditions for macro training.
///
/// Each rule knows how to convert itself to a WaitFor for plan execution.
sealed class MacroStopRule {
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
// Macro Expansion Outcomes
// ---------------------------------------------------------------------------

/// Result of expanding a macro into concrete execution steps.
typedef MacroExpansionResult = ({
  GlobalState state,
  int ticksElapsed,
  WaitFor waitFor,
  int deaths,
  String? triggeringCondition,
  MacroCandidate macro,
});

/// Outcome of attempting to expand a macro - tri-state result.
///
/// This ensures we always know WHY an expansion failed, rather than silently
/// returning null.
sealed class MacroExpansionOutcome {
  const MacroExpansionOutcome();
}

/// Macro expanded successfully to a future state.
class MacroExpanded extends MacroExpansionOutcome {
  const MacroExpanded(this.result);
  final MacroExpansionResult result;
}

/// Macro is already satisfied - no expansion needed (legitimate no-op).
///
/// This is different from failure: the macro's goal is already met,
/// so there's nothing to expand.
class MacroAlreadySatisfied extends MacroExpansionOutcome {
  const MacroAlreadySatisfied(this.reason);
  final String reason;
}

/// Macro cannot be expanded due to missing prerequisites or unsatisfiable
/// constraints.
class MacroCannotExpand extends MacroExpansionOutcome {
  const MacroCannotExpand(this.reason);
  final String reason;
}
