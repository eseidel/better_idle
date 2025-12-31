import 'dart:math';

/// Reasons why bestRate might be zero.
sealed class RateZeroReason {
  const RateZeroReason();

  /// Human-readable description of why the rate is zero.
  String describe();
}

/// No skills relevant to the goal were found.
class NoRelevantSkillReason extends RateZeroReason {
  const NoRelevantSkillReason(this.goalDescription);

  final String goalDescription;

  @override
  String describe() => 'no relevant skill for goal "$goalDescription"';
}

/// Skills exist but no actions are unlocked yet.
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
class InputsRequiredReason extends RateZeroReason {
  const InputsRequiredReason();

  @override
  String describe() => 'all actions require inputs with no available producers';
}

/// Action has zero expected ticks (shouldn't happen).
class ZeroTicksReason extends RateZeroReason {
  const ZeroTicksReason();

  @override
  String describe() => 'all actions have zero duration (configuration error)';
}

/// Stats from a single candidate enumeration call.
class CandidateStats {
  CandidateStats({
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
class FrontierStats {
  const FrontierStats({required this.inserted, required this.removed});

  final int inserted;
  final int removed;
}

/// Cache statistics.
class CacheStats {
  const CacheStats({required this.hits, required this.misses});

  final int hits;
  final int misses;
}

/// Immutable profiling stats from a completed solve.
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
    required this.rateZeroBecauseNoRelevantSkill,
    required this.rateZeroBecauseNoUnlockedActions,
    required this.rateZeroBecauseInputsRequired,
    required this.rateZeroBecauseZeroTicks,
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
  final int rateZeroBecauseNoRelevantSkill;
  final int rateZeroBecauseNoUnlockedActions;
  final int rateZeroBecauseInputsRequired;
  final int rateZeroBecauseZeroTicks;

  // Computed getters
  double get minBestRate =>
      bestRateSamples.isEmpty ? 0 : bestRateSamples.reduce(min);

  double get maxBestRate =>
      bestRateSamples.isEmpty ? 0 : bestRateSamples.reduce(max);

  double get medianBestRate {
    if (bestRateSamples.isEmpty) return 0;
    final sorted = List<double>.from(bestRateSamples)..sort();
    return sorted[sorted.length ~/ 2];
  }

  double get nodesPerSecond =>
      totalTimeUs > 0 ? expandedNodes / (totalTimeUs / 1e6) : 0;

  double get avgBranchingFactor =>
      expandedNodes > 0 ? totalNeighborsGenerated / expandedNodes : 0;

  int get minDelta => decisionDeltas.isEmpty ? 0 : decisionDeltas.reduce(min);

  int get medianDelta {
    if (decisionDeltas.isEmpty) return 0;
    final sorted = List<int>.from(decisionDeltas)..sort();
    return sorted[sorted.length ~/ 2];
  }

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

  int get minHeuristic =>
      heuristicValues.isEmpty ? 0 : heuristicValues.reduce(min);

  int get maxHeuristic =>
      heuristicValues.isEmpty ? 0 : heuristicValues.reduce(max);

  int get medianHeuristic {
    if (heuristicValues.isEmpty) return 0;
    final sorted = List<int>.from(heuristicValues)..sort();
    return sorted[sorted.length ~/ 2];
  }

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
  int rateZeroBecauseNoRelevantSkill = 0;
  int rateZeroBecauseNoUnlockedActions = 0;
  int rateZeroBecauseInputsRequired = 0;
  int rateZeroBecauseZeroTicks = 0;

  void recordBestRate(double rate, {required bool isRoot}) {
    bestRateSamples.add(rate);
    if (isRoot) rootBestRate = rate;
  }

  void recordRateZeroReason(RateZeroReason reason) {
    switch (reason) {
      case NoRelevantSkillReason():
        rateZeroBecauseNoRelevantSkill++;
      case NoUnlockedActionsReason():
        rateZeroBecauseNoUnlockedActions++;
      case InputsRequiredReason():
        rateZeroBecauseInputsRequired++;
      case ZeroTicksReason():
        rateZeroBecauseZeroTicks++;
    }
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
      rateZeroBecauseNoRelevantSkill: rateZeroBecauseNoRelevantSkill,
      rateZeroBecauseNoUnlockedActions: rateZeroBecauseNoUnlockedActions,
      rateZeroBecauseInputsRequired: rateZeroBecauseInputsRequired,
      rateZeroBecauseZeroTicks: rateZeroBecauseZeroTicks,
    );
  }
}
