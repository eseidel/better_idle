/// Level 3 Meta Planner entry point.
///
/// The meta planner decomposes long-horizon goals into phases, calls Level 2
/// as an oracle to evaluate candidates, and produces a [MetaPlan].
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/meta/level2_oracle.dart';
import 'package:logic/src/solver/meta/meta_goal.dart';
import 'package:logic/src/solver/meta/meta_phase.dart';
import 'package:logic/src/solver/meta/meta_plan.dart';
import 'package:logic/src/solver/meta/milestone.dart';
import 'package:logic/src/solver/meta/milestone_extractor.dart';
import 'package:logic/src/solver/meta/phase_result.dart';
import 'package:logic/src/solver/meta/project.dart';
import 'package:logic/src/solver/meta/scheduling_policy.dart';
import 'package:logic/src/state.dart';

/// Configuration for the meta planner.
class MetaPlannerConfig {
  const MetaPlannerConfig({
    this.maxPhases = 100,
    this.maxTotalTicks = 86400000, // 24 hours in ticks (100ms each)
    this.frontierSize = 3,
    this.candidatesPerPhase = 3,
    this.oracleConfig = const OracleConfig(),
    this.verbose = false,
  });

  /// Maximum number of phases to generate.
  final int maxPhases;

  /// Maximum total ticks for the plan.
  final int maxTotalTicks;

  /// Number of frontier milestones to consider at once.
  final int frontierSize;

  /// Number of candidate phases to evaluate per decision.
  final int candidatesPerPhase;

  /// Configuration for Level 2 oracle calls.
  final OracleConfig oracleConfig;

  /// Whether to print verbose output.
  final bool verbose;
}

/// Exception thrown when meta planning fails.
class MetaPlannerException implements Exception {
  MetaPlannerException(this.message);
  final String message;

  @override
  String toString() => 'MetaPlannerException: $message';
}

/// Level 3 Meta Planner.
///
/// Decomposes high-level goals into phases and produces a [MetaPlan].
class MetaPlanner {
  MetaPlanner({
    required this.registries,
    this.config = const MetaPlannerConfig(),
  });

  final Registries registries;
  final MetaPlannerConfig config;

  late final MilestoneExtractor _extractor = MilestoneExtractor(registries);
  late final Level2Oracle _oracle = Level2Oracle(config: config.oracleConfig);

  /// Solve for a MetaPlan to achieve the given MetaGoal.
  MetaPlan solve(GlobalState initialState, MetaGoal metaGoal) {
    if (metaGoal is! AllSkills99Goal) {
      throw MetaPlannerException('Only AllSkills99Goal is supported currently');
    }

    // 1. Extract milestone graph for this goal
    final milestoneGraph = _extractor.extractForAllSkills99(metaGoal);

    if (config.verbose) {
      final status = milestoneGraph.countStatus(initialState);
      // Verbose output for debugging/CLI usage.
      // ignore: avoid_print
      print(
        'Milestone graph: ${status.total} milestones, '
        '${status.satisfied} satisfied, ${status.unsatisfied} remaining',
      );
    }

    // 2. Initialize planning state
    var currentState = initialState;
    final phases = <MetaPhase>[];
    final segments = <Plan>[];
    var totalTicks = 0;
    var phaseCounter = 0;

    // 3. Rolling horizon loop
    while (!metaGoal.isSatisfied(currentState)) {
      // Check budget
      if (phases.length >= config.maxPhases) {
        throw MetaPlannerException('Exceeded max phases (${config.maxPhases})');
      }
      if (totalTicks >= config.maxTotalTicks) {
        throw MetaPlannerException(
          'Exceeded tick budget ($totalTicks >= ${config.maxTotalTicks})',
        );
      }

      // 4. Select frontier milestones
      final frontier = _selectFrontier(currentState, milestoneGraph, metaGoal);
      if (frontier.isEmpty) {
        throw MetaPlannerException('No frontier milestones available');
      }

      if (config.verbose) {
        final frontierDesc = frontier
            .map((n) => n.milestone.describe())
            .join(', ');
        // Verbose output for debugging/CLI usage.
        // ignore: avoid_print
        print('Phase ${phaseCounter + 1}: Frontier: $frontierDesc');
      }

      // 5. Generate candidate phases
      final candidates = _generateCandidatePhases(
        currentState,
        frontier,
        metaGoal,
        phaseCounter,
      );

      if (candidates.isEmpty) {
        throw MetaPlannerException('No candidate phases generated');
      }

      // 6. Evaluate candidates via oracle
      final evaluations = <(MetaPhase, PhaseResult?)>[];
      for (final candidate in candidates) {
        // Use smaller node limits for multi-target goals (they're harder)
        final targetCount = candidate.targets.hardTargets.length;
        final oracleConfig = targetCount > 1
            ? OracleConfig(
                maxExpandedNodes: config.oracleConfig.maxExpandedNodes ~/ 2,
                maxQueueSize: config.oracleConfig.maxQueueSize ~/ 2,
              )
            : null;

        final result = _oracle.evaluate(
          currentState,
          candidate.targets.hardTargets,
          overrideConfig: oracleConfig,
        );
        evaluations.add((candidate, result));

        if (config.verbose) {
          if (result != null) {
            // Verbose output for debugging/CLI usage.
            // ignore: avoid_print
            print(
              '  Candidate ${candidate.policy.name}: '
              '${result.ticksElapsed} ticks, '
              '${result.milestonesSatisfied.length} milestones',
            );
          } else {
            // Verbose output for debugging/CLI usage.
            // ignore: avoid_print
            print('  Candidate ${candidate.policy.name}: solver failed');
          }
        }
      }

      // 7. Select best phase
      final (bestPhase, bestResult) = _selectBestPhase(
        evaluations,
        currentState,
        metaGoal,
      );
      if (bestResult == null) {
        throw MetaPlannerException('No viable phase found');
      }

      if (config.verbose) {
        // Verbose output for debugging/CLI usage.
        // ignore: avoid_print
        print(
          '  Selected: ${bestPhase.policy.describe()} '
          '(${bestResult.ticksElapsed} ticks)',
        );
      }

      // 8. Commit phase and its segment
      phases.add(bestPhase);
      segments.add(bestResult.plan);
      currentState = bestResult.terminalState;
      totalTicks += bestResult.ticksElapsed;
      phaseCounter++;
    }

    if (config.verbose) {
      // Verbose output for debugging/CLI usage.
      // ignore: avoid_print
      print(
        'Meta planning complete: ${phases.length} phases, '
        '$totalTicks total ticks',
      );
    }

    return MetaPlan(
      metaGoal: metaGoal,
      phases: phases,
      segments: segments,
      totalTicks: totalTicks,
    );
  }

  /// Select a small frontier of milestone targets.
  List<MilestoneNode> _selectFrontier(
    GlobalState state,
    MilestoneGraph graph,
    AllSkills99Goal goal,
  ) {
    // Get all unsatisfied milestones (no dependency edges in v1)
    final allFrontier = graph.frontier(state);

    // Prioritize by skill level (raise the floor first)
    // Group by skill and pick next milestone for each unfinished skill
    final skillMilestones = <Skill, MilestoneNode>{};

    for (final node in allFrontier) {
      if (node.milestone is! SkillLevelMilestone) continue;
      final m = node.milestone as SkillLevelMilestone;

      // Only consider skills that are part of the goal
      if (!goal.trainableSkills.contains(m.skill)) continue;

      // Keep the lowest level milestone for each skill
      final existing = skillMilestones[m.skill];
      if (existing == null) {
        skillMilestones[m.skill] = node;
      } else {
        final existingLevel = (existing.milestone as SkillLevelMilestone).level;
        if (m.level < existingLevel) {
          skillMilestones[m.skill] = node;
        }
      }
    }

    // Sort skills by current level (lowest first - raise the floor)
    final sortedSkills = skillMilestones.keys.toList()
      ..sort((a, b) {
        final aLevel = state.skillState(a).skillLevel;
        final bLevel = state.skillState(b).skillLevel;
        return aLevel.compareTo(bLevel);
      });

    // Return top N skills' next milestones
    return sortedSkills
        .take(config.frontierSize)
        .map((s) => skillMilestones[s]!)
        .toList();
  }

  /// Generate candidate phases to evaluate.
  List<MetaPhase> _generateCandidatePhases(
    GlobalState state,
    List<MilestoneNode> frontier,
    AllSkills99Goal goal,
    int phaseIndex,
  ) {
    final candidates = <MetaPhase>[];

    // Candidate 1: BatchSkill for the skill with lowest level (raise floor)
    if (frontier.isNotEmpty) {
      final lowestNode = frontier.first;
      if (lowestNode.milestone is SkillLevelMilestone) {
        final m = lowestNode.milestone as SkillLevelMilestone;
        candidates.add(_createBatchSkillPhase(m, phaseIndex));
      }
    }

    // Candidate 2: BatchSkill for second-lowest skill (if different)
    if (frontier.length >= 2) {
      final secondNode = frontier[1];
      if (secondNode.milestone is SkillLevelMilestone) {
        final m = secondNode.milestone as SkillLevelMilestone;
        candidates.add(_createBatchSkillPhase(m, phaseIndex, variant: 1));
      }
    }

    // Candidate 3: RoundRobin across frontier skills (if multiple)
    if (frontier.length >= 2) {
      final skills = frontier
          .map((n) => n.milestone)
          .whereType<SkillLevelMilestone>()
          .map((m) => m.skill)
          .toSet()
          .toList();

      if (skills.length >= 2) {
        candidates.add(_createRoundRobinPhase(skills, goal, phaseIndex));
      }
    }

    return candidates;
  }

  /// Create a BatchSkill phase for a milestone.
  MetaPhase _createBatchSkillPhase(
    SkillLevelMilestone target,
    int phaseIndex, {
    int variant = 0,
  }) {
    final policy = BatchSkillPolicy(
      skill: target.skill,
      targetLevel: target.level,
    );

    final project = TrainSkillProject(
      skill: target.skill,
      targetMilestones: [target],
    );

    return MetaPhase(
      id: 'phase_${phaseIndex}_batch_${target.skill.name}_v$variant',
      targets: PhaseTargets(hardTargets: [target]),
      activeProjects: [project],
      policy: policy,
      explain: 'Focus ${target.skill.name} to L${target.level}',
    );
  }

  /// Create a RoundRobin phase across multiple skills.
  MetaPhase _createRoundRobinPhase(
    List<Skill> skills,
    AllSkills99Goal goal,
    int phaseIndex,
  ) {
    final policy = RoundRobinByDeficitPolicy(
      skills: skills,
      targetLevel: goal.targetLevel,
    );

    final milestones = skills.map((s) {
      return SkillLevelMilestone(skill: s, level: goal.targetLevel);
    }).toList();

    final projects = skills.map((s) {
      return TrainSkillProject(
        skill: s,
        targetMilestones: [
          SkillLevelMilestone(skill: s, level: goal.targetLevel),
        ],
      );
    }).toList();

    return MetaPhase(
      id: 'phase_${phaseIndex}_roundrobin',
      targets: PhaseTargets(hardTargets: milestones),
      activeProjects: projects,
      policy: policy,
      explain: 'Balance ${skills.map((s) => s.name).join(", ")}',
    );
  }

  /// Select the best phase from evaluated candidates.
  (MetaPhase, PhaseResult?) _selectBestPhase(
    List<(MetaPhase, PhaseResult?)> evaluations,
    GlobalState currentState,
    AllSkills99Goal goal,
  ) {
    var best = evaluations.first;
    var bestScore = _scorePhase(best.$1, best.$2, currentState, goal);

    for (final eval in evaluations.skip(1)) {
      final score = _scorePhase(eval.$1, eval.$2, currentState, goal);
      if (score > bestScore) {
        best = eval;
        bestScore = score;
      }
    }

    return best;
  }

  /// Score a phase evaluation.
  ///
  /// Scoring factors:
  /// - Progress on min skill level (raise the floor)
  /// - Milestones satisfied
  /// - Efficiency (progress / ticks)
  /// - Penalties for deaths, inventory pressure
  double _scorePhase(
    MetaPhase phase,
    PhaseResult? result,
    GlobalState currentState,
    AllSkills99Goal goal,
  ) {
    if (result == null) return double.negativeInfinity;

    var score = 0.0;

    // 1. Progress on min skill level (raise the floor) - HIGH weight
    final initialMinLevel = goal.minSkillLevel(currentState);
    final terminalMinLevel = goal.minSkillLevel(result.terminalState);
    final floorProgress = terminalMinLevel - initialMinLevel;
    score += floorProgress * 10000; // High weight for raising floor

    // 2. Milestones satisfied - MEDIUM weight
    score += result.milestonesSatisfied.length * 1000;

    // 3. XP efficiency - MEDIUM weight
    final totalXp = result.totalXpGained;
    final ticks = result.ticksElapsed;
    if (ticks > 0) {
      final xpPerTick = totalXp / ticks;
      score += xpPerTick * 100;
    }

    // 4. Level ups - MEDIUM weight (unlocks new actions)
    if (result.hadLevelUp) {
      score += 500;
    }

    // 5. Penalties
    // Deaths
    final deathCount = result.countEvents(PhaseEventType.death);
    score -= deathCount * 200;

    // Inventory pressure
    final pressureCount = result.countEvents(PhaseEventType.inventoryPressure);
    score -= pressureCount * 300;

    // 6. Penalty for very long phases (prefer making progress sooner)
    if (ticks > 100000) {
      score -= (ticks - 100000) / 1000;
    }

    return score;
  }
}
