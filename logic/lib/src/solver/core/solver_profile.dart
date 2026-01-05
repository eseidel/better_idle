import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logic/src/data/actions.dart' show Skill;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:meta/meta.dart';

/// Reasons why bestRate might be zero.
@immutable
sealed class RateZeroReason {
  const RateZeroReason();

  /// Human-readable description of why the rate is zero.
  String describe();
}

/// No skills relevant to the goal were found.
@immutable
class NoRelevantSkillReason extends RateZeroReason {
  const NoRelevantSkillReason(this.goalDescription);

  final String goalDescription;

  @override
  String describe() => 'no relevant skill for goal "$goalDescription"';
}

/// Skills exist but no actions are unlocked yet.
@immutable
class NoUnlockedActionsReason extends RateZeroReason {
  const NoUnlockedActionsReason({
    required this.goalDescription,
    this.missingInputName,
    this.actionNeedingInput,
    this.skillName,
  });

  final String goalDescription;

  /// For consuming skills: the name of the input item that has no producer.
  final String? missingInputName;

  /// For consuming skills: the name of the action that needs the input.
  final String? actionNeedingInput;

  /// For consuming skills: the name of the skill.
  final String? skillName;

  @override
  String describe() {
    if (missingInputName != null && actionNeedingInput != null) {
      return 'no producer for $missingInputName '
          '(needed by $actionNeedingInput) at current skill levels';
    }
    if (skillName != null) {
      return 'no unlocked actions for $skillName';
    }
    return 'no unlocked actions for goal "$goalDescription"';
  }
}

/// All unlocked actions require inputs (consuming skill).
@immutable
class InputsRequiredReason extends RateZeroReason {
  const InputsRequiredReason();

  @override
  String describe() => 'all actions require inputs with no available producers';
}

/// Action has zero expected ticks (shouldn't happen).
@immutable
class ZeroTicksReason extends RateZeroReason {
  const ZeroTicksReason();

  @override
  String describe() => 'all actions have zero duration (configuration error)';
}

/// Stats from a single candidate enumeration call.
@immutable
class CandidateStats {
  const CandidateStats({
    required this.consumerActionsConsidered,
    required this.producerActionsConsidered,
    required this.pairsConsidered,
    required this.pairsKept,
    required this.topPairs,
  });

  final int consumerActionsConsidered;
  final int producerActionsConsidered;
  final int pairsConsidered;
  final int pairsKept;
  final List<({String consumerId, String producerId, double score})> topPairs;
}

/// Frontier statistics from dominance pruning.
@immutable
class FrontierStats {
  const FrontierStats({required this.inserted, required this.removed});

  static FrontierStats zero = const FrontierStats(inserted: 0, removed: 0);

  final int inserted;
  final int removed;
}

/// Cache statistics.
@immutable
class CacheStats {
  const CacheStats({required this.hits, required this.misses});

  final int hits;
  final int misses;
}

extension IterableDoubleExtension on Iterable<double> {
  double? get medianOrNull {
    if (isEmpty) return null;
    final sorted = List<double>.from(this)..sort();
    return sorted[sorted.length ~/ 2];
  }
}

extension IterableIntExtension on Iterable<int> {
  int? get medianOrNull {
    if (isEmpty) return null;
    final sorted = List<int>.from(this)..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// Immutable profiling stats from a completed solve.
@immutable
class SolverProfile {
  const SolverProfile({
    required this.expandedNodes,
    required this.totalNeighborsGenerated,
    required this.decisionDeltas,
    required this.advanceTimeUs,
    required this.enumerateCandidatesTimeUs,
    required this.cacheKeyTimeUs,
    required this.hashingTimeUs,
    required this.totalTimeUs,
    required this.dominatedSkipped,
    required this.frontier,
    required this.cache,
    required this.peakQueueSize,
    required this.uniqueBucketKeys,
    required this.heuristicValues,
    required this.zeroRateCount,
    required this.macroStopTriggers,
    required this.candidateStatsHistory,
    required this.rootBestRate,
    required this.bestRateSamples,
    required this.rateZeroReasonCounts,
    required this.prereqCacheHits,
    required this.prereqCacheMisses,
    required this.prereqMacrosByType,
    required this.blockedChainsByItem,
  });

  final int expandedNodes;
  final int totalNeighborsGenerated;
  final List<int> decisionDeltas;

  // Timing in microseconds
  final int advanceTimeUs;
  final int enumerateCandidatesTimeUs;
  final int cacheKeyTimeUs;
  final int hashingTimeUs;
  final int totalTimeUs;

  // Dominance pruning stats
  final int dominatedSkipped;
  final FrontierStats frontier;

  // Candidate cache stats
  final CacheStats cache;

  // Extended diagnostic stats
  final int peakQueueSize;
  final int uniqueBucketKeys;

  // Heuristic health metrics
  final List<int> heuristicValues;
  final int zeroRateCount;

  // Macro stop trigger histogram
  final Map<String, int> macroStopTriggers;

  // Candidate stats per enumeration call
  final List<CandidateStats> candidateStatsHistory;

  // Best rate diagnostics
  final double? rootBestRate;
  final List<double> bestRateSamples;

  // Why bestRate is zero counters
  final Map<Type, int> rateZeroReasonCounts;

  // Prerequisite tracking
  final int prereqCacheHits;
  final int prereqCacheMisses;
  final Map<String, int> prereqMacrosByType;
  final Map<String, int> blockedChainsByItem;

  // Computed getters
  double get minBestRate => bestRateSamples.minOrNull ?? 0;

  double get maxBestRate => bestRateSamples.maxOrNull ?? 0;

  double get medianBestRate => bestRateSamples.medianOrNull ?? 0;

  double get nodesPerSecond =>
      totalTimeUs > 0 ? expandedNodes / (totalTimeUs / 1e6) : 0;

  double get avgBranchingFactor =>
      expandedNodes > 0 ? totalNeighborsGenerated / expandedNodes : 0;

  int get minDelta => decisionDeltas.isEmpty ? 0 : decisionDeltas.reduce(min);

  int get medianDelta => decisionDeltas.medianOrNull ?? 0;

  int get p95Delta {
    if (decisionDeltas.isEmpty) return 0;
    final sorted = List<int>.from(decisionDeltas)..sort();
    final idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  double get advancePercent =>
      totalTimeUs > 0 ? 100.0 * advanceTimeUs / totalTimeUs : 0;

  double get enumeratePercent =>
      totalTimeUs > 0 ? 100.0 * enumerateCandidatesTimeUs / totalTimeUs : 0;

  double get cacheKeyPercent =>
      totalTimeUs > 0 ? 100.0 * cacheKeyTimeUs / totalTimeUs : 0;

  double get hashingPercent =>
      totalTimeUs > 0 ? 100.0 * hashingTimeUs / totalTimeUs : 0;

  int get minHeuristic => heuristicValues.minOrNull ?? 0;

  int get maxHeuristic => heuristicValues.maxOrNull ?? 0;

  int get medianHeuristic => heuristicValues.medianOrNull ?? 0;

  double get zeroRateFraction =>
      heuristicValues.isEmpty ? 0 : zeroRateCount / heuristicValues.length;

  int get heuristicSpread => maxHeuristic - minHeuristic;
}

/// Mutable builder for accumulating profiling stats during a solve.
class SolverProfileBuilder {
  final Stopwatch _stopwatch = Stopwatch()..start();

  int totalNeighborsGenerated = 0;
  final List<int> decisionDeltas = [];

  // Timing in microseconds
  int advanceTimeUs = 0;
  int enumerateCandidatesTimeUs = 0;
  int cacheKeyTimeUs = 0;
  int hashingTimeUs = 0;

  // Dominance pruning stats
  int dominatedSkipped = 0;

  // Extended diagnostic stats
  int peakQueueSize = 0;
  int uniqueBucketKeys = 0;
  final Set<String> _seenBucketKeys = {};

  // Heuristic health metrics
  final List<int> heuristicValues = [];
  int zeroRateCount = 0;

  // Macro stop trigger histogram
  final Map<String, int> macroStopTriggers = {};

  // Candidate stats per enumeration call
  final List<CandidateStats> candidateStatsHistory = [];

  // Best rate diagnostics
  double? rootBestRate;
  final List<double> bestRateSamples = [];

  // Why bestRate is zero counters
  final Map<Type, int> rateZeroReasonCounts = {};

  // Prerequisite tracking
  int prereqCacheHits = 0;
  int prereqCacheMisses = 0;
  final Map<String, int> prereqMacrosByType = {};
  final Map<String, int> blockedChainsByItem = {};

  void recordPrereqMacro(MacroCandidate prereq) {
    final key = prereq.runtimeType.toString();
    prereqMacrosByType[key] = (prereqMacrosByType[key] ?? 0) + 1;
  }

  void recordBlockedChain(MelvorId itemId, Skill skill, int level) {
    final key = '${itemId.localId} (${skill.name} L$level)';
    blockedChainsByItem[key] = (blockedChainsByItem[key] ?? 0) + 1;
  }

  void recordBestRate(double rate, {required bool isRoot}) {
    bestRateSamples.add(rate);
    if (isRoot) rootBestRate = rate;
  }

  void recordRateZeroReason(RateZeroReason reason) {
    final type = reason.runtimeType;
    rateZeroReasonCounts[type] = (rateZeroReasonCounts[type] ?? 0) + 1;
  }

  void recordBucketKey(String key) {
    if (_seenBucketKeys.add(key)) {
      uniqueBucketKeys = _seenBucketKeys.length;
    }
  }

  void recordHeuristic(int h, {required bool hasZeroRate}) {
    heuristicValues.add(h);
    if (hasZeroRate) zeroRateCount++;
  }

  void recordMacroStopTrigger(String trigger) {
    macroStopTriggers[trigger] = (macroStopTriggers[trigger] ?? 0) + 1;
  }

  SolverProfile build({
    required int expandedNodes,
    required FrontierStats frontier,
    int cacheHits = 0,
    int cacheMisses = 0,
  }) {
    _stopwatch.stop();
    return SolverProfile(
      expandedNodes: expandedNodes,
      totalNeighborsGenerated: totalNeighborsGenerated,
      decisionDeltas: List.unmodifiable(decisionDeltas),
      advanceTimeUs: advanceTimeUs,
      enumerateCandidatesTimeUs: enumerateCandidatesTimeUs,
      cacheKeyTimeUs: cacheKeyTimeUs,
      hashingTimeUs: hashingTimeUs,
      totalTimeUs: _stopwatch.elapsedMicroseconds,
      dominatedSkipped: dominatedSkipped,
      frontier: frontier,
      cache: CacheStats(hits: cacheHits, misses: cacheMisses),
      peakQueueSize: peakQueueSize,
      uniqueBucketKeys: uniqueBucketKeys,
      heuristicValues: List.unmodifiable(heuristicValues),
      zeroRateCount: zeroRateCount,
      macroStopTriggers: Map.unmodifiable(macroStopTriggers),
      candidateStatsHistory: List.unmodifiable(candidateStatsHistory),
      rootBestRate: rootBestRate,
      bestRateSamples: List.unmodifiable(bestRateSamples),
      rateZeroReasonCounts: Map.unmodifiable(rateZeroReasonCounts),
      prereqCacheHits: prereqCacheHits,
      prereqCacheMisses: prereqCacheMisses,
      prereqMacrosByType: Map.unmodifiable(prereqMacrosByType),
      blockedChainsByItem: Map.unmodifiable(blockedChainsByItem),
    );
  }
}
