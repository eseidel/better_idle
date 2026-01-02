/// Rate caching for the solver heuristic.
///
/// Provides cached computation of best unlocked rates for both GP and XP goals.
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/solver_profile.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/stunned.dart';

// Re-export types from solver_profile.dart for convenience
export 'package:logic/src/solver/solver_profile.dart'
    show
        NoRelevantSkillReason,
        NoUnlockedActionsReason,
        RateZeroReason,
        ZeroTicksReason;

/// Result of rate computation with optional diagnostic info.
class RateResult {
  RateResult(this.rate, {this.zeroReason});

  final double rate;
  final RateZeroReason? zeroReason;
}

/// Cache for best unlocked rate by state key (skill levels + tool tiers).
/// Supports both GP goals (gold/tick) and skill goals (XP/tick).
class RateCache {
  RateCache(this.goal);

  final Goal goal;
  final Map<String, double> _cache = {};
  final Map<String, double> _skillCache = {};
  final Map<String, RateZeroReason?> _reasonCache = {};

  String _rateKey(GlobalState state) {
    // Key by skill levels and tool tiers (things that affect unlocks/rates)
    return '${state.skillState(Skill.woodcutting).skillLevel}|'
        '${state.skillState(Skill.fishing).skillLevel}|'
        '${state.skillState(Skill.mining).skillLevel}|'
        '${state.skillState(Skill.thieving).skillLevel}|'
        '${state.skillState(Skill.firemaking).skillLevel}|'
        '${state.skillState(Skill.cooking).skillLevel}|'
        '${state.skillState(Skill.smithing).skillLevel}|'
        '${state.shop.axeLevel}|'
        '${state.shop.fishingRodLevel}|'
        '${state.shop.pickaxeLevel}';
  }

  double getBestUnlockedRate(GlobalState state) {
    final key = _rateKey(state);
    final cached = _cache[key];
    if (cached != null) return cached;

    final result = _computeBestUnlockedRate(state);
    _cache[key] = result.rate;
    _reasonCache[key] = result.zeroReason;
    return result.rate;
  }

  /// Gets the reason why the rate was zero for this state.
  /// Returns null if the rate was non-zero or not yet computed.
  RateZeroReason? getZeroReason(GlobalState state) {
    final key = _rateKey(state);
    return _reasonCache[key];
  }

  /// Gets the best XP rate for a specific skill.
  /// Used by multi-skill goal heuristic to compute per-skill estimates.
  double getBestRateForSkill(GlobalState state, Skill targetSkill) {
    final key = '${_rateKey(state)}|${targetSkill.name}';
    final cached = _skillCache[key];
    if (cached != null) return cached;

    final rate = _computeBestRateForSkill(state, targetSkill);
    _skillCache[key] = rate;
    return rate;
  }

  double _computeBestRateForSkill(GlobalState state, Skill targetSkill) {
    var maxRate = 0.0;
    final registries = state.registries;
    final skillLevel = state.skillState(targetSkill).skillLevel;

    for (final action in registries.actions.forSkill(targetSkill)) {
      // Only consider unlocked actions
      if (skillLevel < action.unlockLevel) continue;

      // Calculate expected ticks with upgrade modifier
      final baseExpectedTicks = ticksFromDuration(
        action.meanDuration,
      ).toDouble();
      final percentModifier = state.shopDurationModifierForSkill(targetSkill);
      final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);
      if (expectedTicks <= 0) continue;

      var xpRate = action.xp / expectedTicks;

      // For consuming actions, cap effective rate by producer throughput.
      // This keeps the heuristic admissible but less wildly optimistic.
      if (action.inputs.isNotEmpty) {
        final producerCap = _computeProducerCapForAction(state, action);
        if (producerCap != null && producerCap < xpRate) {
          xpRate = producerCap;
        }
      }

      if (xpRate > maxRate) {
        maxRate = xpRate;
      }
    }

    return maxRate;
  }

  /// Computes the maximum XP rate a consuming action can sustain based on
  /// producer throughput. Returns null if producers aren't available.
  ///
  /// For each input, finds the best unlocked producer and calculates how fast
  /// inputs can be supplied. The effective XP rate is capped by the slowest
  /// input supply chain.
  double? _computeProducerCapForAction(GlobalState state, SkillAction action) {
    final registries = state.registries;
    double? minCap;

    for (final inputEntry in action.inputs.entries) {
      final inputItemId = inputEntry.key;
      final inputsPerAction = inputEntry.value;

      // Find best producer for this input item
      double bestProducerRate = 0;
      for (final skill in Skill.values) {
        final producerSkillLevel = state.skillState(skill).skillLevel;

        for (final producer in registries.actions.forSkill(skill)) {
          // Only non-consuming, unlocked producers
          if (producer.inputs.isNotEmpty) continue;
          if (producerSkillLevel < producer.unlockLevel) continue;

          // Check if this action produces the needed item
          final outputCount = producer.outputs[inputItemId];
          if (outputCount == null || outputCount <= 0) continue;

          // Calculate producer rate
          final producerTicks = ticksFromDuration(
            producer.meanDuration,
          ).toDouble();
          final modifier = state.shopDurationModifierForSkill(skill);
          final effectiveTicks = producerTicks * (1.0 + modifier);
          if (effectiveTicks <= 0) continue;

          final itemsPerTick = outputCount / effectiveTicks;
          if (itemsPerTick > bestProducerRate) {
            bestProducerRate = itemsPerTick;
          }
        }
      }

      if (bestProducerRate <= 0) {
        // No producer available - can't sustain this action
        return 0;
      }

      // How many consuming actions can we do per tick given producer rate?
      // items/tick from producer / items needed per action = actions/tick
      // actions/tick * XP/action = XP/tick cap
      final actionsPerTick = bestProducerRate / inputsPerAction;
      final xpCap = actionsPerTick * action.xp;

      if (minCap == null || xpCap < minCap) {
        minCap = xpCap;
      }
    }

    return minCap;
  }

  /// Computes the best rate among currently UNLOCKED actions.
  /// Uses the goal to determine which rate type and skills are relevant.
  ///
  /// For consuming skills (Firemaking, Cooking), calculates the sustainable
  /// XP rate based on best consumer+producer pairs, not just raw consume rate.
  /// This ensures the heuristic doesn't return 0 just because inputs
  /// aren't currently in inventory.
  ///
  /// Returns rate and reason if zero.
  RateResult _computeBestUnlockedRate(GlobalState state) {
    var maxRate = 0.0;
    final registries = state.registries;

    // Track why rate might be zero
    var sawRelevantSkill = false;
    var sawUnlockedAction = false;
    var sawZeroTicks = false;

    // For consuming skills: track first missing producer for better error msg
    String? missingInputName;
    String? actionNeedingInput;
    String? relevantSkillName;

    for (final skill in Skill.values) {
      // Only consider skills relevant to the goal
      if (!goal.isSkillRelevant(skill)) continue;
      sawRelevantSkill = true;
      relevantSkillName ??= skill.name;

      final skillLevel = state.skillState(skill).skillLevel;

      for (final action in registries.actions.forSkill(skill)) {
        // Only consider unlocked actions
        if (skillLevel < action.unlockLevel) continue;

        // Calculate expected ticks with upgrade modifier
        final baseExpectedTicks = ticksFromDuration(
          action.meanDuration,
        ).toDouble();
        final percentModifier = state.shopDurationModifierForSkill(skill);
        final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);
        if (expectedTicks <= 0) {
          sawZeroTicks = true;
          continue;
        }

        // Compute both gold and XP rates, let goal decide which matters
        double goldRate;
        double xpRate;

        if (action is ThievingAction) {
          final thievingLevel = state.skillState(Skill.thieving).skillLevel;
          final mastery = state.actionState(action.id).masteryLevel;
          final stealth = calculateStealth(thievingLevel, mastery);
          final successChance = thievingSuccessChance(
            stealth,
            action.perception,
          );
          final failureChance = 1.0 - successChance;
          final effectiveTicks =
              expectedTicks + failureChance * stunnedDurationTicks;

          // XP is only gained on success
          final expectedXpPerAction = successChance * action.xp;
          xpRate = expectedXpPerAction / effectiveTicks;

          // Gold from thieving
          var expectedGoldPerAction = 0.0;
          for (final output in action.outputs.entries) {
            final item = registries.items.byId(output.key);
            expectedGoldPerAction += item.sellsFor * output.value;
          }
          final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
          expectedGoldPerAction += expectedThievingGold;
          goldRate = expectedGoldPerAction / effectiveTicks;

          // Apply cycle adjustment for death risk
          final expectedDamagePerAttempt =
              failureChance * (1 + action.maxHit) / 2;
          final hpLossPerTick = expectedDamagePerAttempt / effectiveTicks;
          if (hpLossPerTick > 0) {
            final playerHp = state.playerHp;
            final ticksToDeath = ((playerHp - 1) / hpLossPerTick).floor();
            if (ticksToDeath > 0) {
              // With 0 restart overhead, cycleRatio = 1.0 (no penalty yet)
              // When we add restartOverheadTicks, this becomes meaningful
              const restartOverheadTicks = 0;
              final ticksPerCycle = ticksToDeath + restartOverheadTicks;
              final cycleRatio = ticksToDeath.toDouble() / ticksPerCycle;
              goldRate *= cycleRatio;
              xpRate *= cycleRatio;
            }
          }
        } else if (action.inputs.isNotEmpty) {
          // Consuming action (Firemaking, Cooking): compute sustainable rate
          // based on best producer throughput, not raw consume rate.
          final sustainedRate = _computeSustainedRateForConsumingAction(
            state,
            action,
          );
          if (sustainedRate == null || sustainedRate <= 0) {
            // No producer available for this action - capture info for error
            if (missingInputName == null) {
              final inputId = action.inputs.keys.first;
              missingInputName = registries.items.byId(inputId).name;
              actionNeedingInput = action.name;
            }
            continue;
          }
          xpRate = sustainedRate;
          // Gold rate for consuming actions is typically 0 (logs don't sell)
          goldRate = 0;
          sawUnlockedAction = true;
        } else {
          xpRate = action.xp / expectedTicks;

          var expectedGoldPerAction = 0.0;
          for (final output in action.outputs.entries) {
            final item = registries.items.byId(output.key);
            expectedGoldPerAction += item.sellsFor * output.value;
          }
          goldRate = expectedGoldPerAction / expectedTicks;
        }

        sawUnlockedAction = true;

        // Let the goal decide which rate matters
        final rate = goal.activityRate(skill, goldRate, xpRate);
        if (rate > maxRate) {
          maxRate = rate;
        }
      }
    }

    // Determine reason if rate is zero
    if (maxRate <= 0) {
      final goalDesc = goal.describe();
      RateZeroReason reason;
      if (!sawRelevantSkill) {
        reason = NoRelevantSkillReason(goalDesc);
      } else if (!sawUnlockedAction) {
        reason = NoUnlockedActionsReason(
          goalDescription: goalDesc,
          missingInputName: missingInputName,
          actionNeedingInput: actionNeedingInput,
          skillName: relevantSkillName,
        );
      } else if (sawZeroTicks) {
        reason = const ZeroTicksReason();
      } else {
        // Rare: saw unlocked actions but all rates were zero
        reason = NoUnlockedActionsReason(goalDescription: goalDesc);
      }
      return RateResult(0, zeroReason: reason);
    }

    return RateResult(maxRate);
  }

  /// Computes the sustainable XP rate for a consuming action.
  ///
  /// For a consuming action (e.g., burning logs, cooking fish), calculates:
  /// - How fast we can produce inputs with the best unlocked producer
  /// - The effective XP/tick accounting for production overhead
  ///
  /// Returns null if no producer is available for the required inputs.
  double? _computeSustainedRateForConsumingAction(
    GlobalState state,
    SkillAction consumeAction,
  ) {
    final registries = state.registries;

    // Get the first input item (logs for firemaking, fish for cooking)
    if (consumeAction.inputs.isEmpty) return null;
    final inputItemId = consumeAction.inputs.keys.first;
    final inputsPerConsumeAction = consumeAction.inputs[inputItemId] ?? 1;

    // Find the best unlocked producer for this input
    double? bestProducerOutputPerTick;
    double? bestProducerTicksPerAction;

    for (final skill in Skill.values) {
      final producerSkillLevel = state.skillState(skill).skillLevel;

      for (final producer in registries.actions.forSkill(skill)) {
        // Only non-consuming, unlocked producers
        if (producer.inputs.isNotEmpty) continue;
        if (producerSkillLevel < producer.unlockLevel) continue;

        // Check if this action produces the needed item
        final outputCount = producer.outputs[inputItemId];
        if (outputCount == null || outputCount <= 0) continue;

        // Calculate producer rate
        final producerBaseTicks = ticksFromDuration(
          producer.meanDuration,
        ).toDouble();
        final modifier = state.shopDurationModifierForSkill(skill);
        final producerTicks = producerBaseTicks * (1.0 + modifier);
        if (producerTicks <= 0) continue;

        final outputPerTick = outputCount / producerTicks;
        if (bestProducerOutputPerTick == null ||
            outputPerTick > bestProducerOutputPerTick) {
          bestProducerOutputPerTick = outputPerTick;
          bestProducerTicksPerAction = producerTicks;
        }
      }
    }

    if (bestProducerOutputPerTick == null ||
        bestProducerTicksPerAction == null) {
      return null; // No producer available
    }

    // Calculate consume action ticks
    final consumeBaseTicks = ticksFromDuration(
      consumeAction.meanDuration,
    ).toDouble();
    final consumeModifier = state.shopDurationModifierForSkill(
      consumeAction.skill,
    );
    final consumeTicks = consumeBaseTicks * (1.0 + consumeModifier);
    if (consumeTicks <= 0) return null;

    // Calculate sustainable XP rate:
    // To do one consume action, we need inputsPerConsumeAction inputs.
    // Producer makes outputPerTick items/tick.
    // So we need (inputsPerConsumeAction / bestProducerOutputPerTick) ticks
    // to produce enough inputs.
    // Total cycle = produce time + consume time
    // XP per cycle = consumeAction.xp
    // Sustained rate = XP / total cycle time

    // How many producer actions needed per consume action?
    // producer outputs `outputCount` per action taking `producerTicks`
    // We get bestProducerOutputPerTick = outputCount / producerTicks
    // To get inputsPerConsumeAction inputs:
    // ticks needed = inputsPerConsumeAction / bestProducerOutputPerTick
    final produceTicksPerCycle =
        inputsPerConsumeAction / bestProducerOutputPerTick;
    final totalTicksPerCycle = produceTicksPerCycle + consumeTicks;

    final sustainedXpPerTick = consumeAction.xp / totalTicksPerCycle;
    return sustainedXpPerTick;
  }
}
