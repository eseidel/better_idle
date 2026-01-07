/// Serializable meta plan container.
///
/// Contains the complete output of Level 3 planning: phases and their
/// associated Level 2 segments.
library;

import 'package:equatable/equatable.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/meta/meta_goal.dart';
import 'package:logic/src/solver/meta/meta_phase.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Serializable container for the complete meta plan.
@immutable
class MetaPlan extends Equatable {
  const MetaPlan({
    required this.metaGoal,
    required this.phases,
    required this.segments,
    required this.totalTicks,
  });

  factory MetaPlan.fromJson(Map<String, dynamic> json) {
    final phasesJson = json['phases'] as List<dynamic>;
    final segmentsJson = json['segments'] as List<dynamic>;

    return MetaPlan(
      metaGoal: MetaGoal.fromJson(json['metaGoal'] as Map<String, dynamic>),
      phases: phasesJson
          .map((p) => MetaPhase.fromJson(p as Map<String, dynamic>))
          .toList(),
      segments: segmentsJson
          .map((s) => Plan.fromJson(s as Map<String, dynamic>))
          .toList(),
      totalTicks: json['totalTicks'] as int,
    );
  }

  /// The high-level goal this plan achieves.
  final MetaGoal metaGoal;

  /// Ordered list of phases.
  final List<MetaPhase> phases;

  /// Level-2 plan segments, one per phase.
  final List<Plan> segments;

  /// Total predicted ticks for the entire plan.
  final int totalTicks;

  /// Total predicted duration.
  Duration get totalDuration => durationFromTicks(totalTicks);

  Map<String, dynamic> toJson() => {
    'metaGoal': metaGoal.toJson(),
    'phases': phases.map((p) => p.toJson()).toList(),
    'segments': segments.map((s) => s.toJson()).toList(),
    'totalTicks': totalTicks,
  };

  /// Pretty-print the plan at high level (phases only).
  String prettyPrintSummary() {
    final buffer = StringBuffer()
      ..writeln('=== Meta Plan ===')
      ..writeln('Goal: ${metaGoal.describe()}')
      ..writeln('Total: ${_formatDuration(totalDuration)}')
      ..writeln('Phases: ${phases.length}')
      ..writeln();

    for (var i = 0; i < phases.length; i++) {
      final phase = phases[i];
      final segment = i < segments.length ? segments[i] : null;
      final segmentTicks = segment?.totalTicks ?? 0;

      buffer
        ..writeln('  ${i + 1}. ${phase.policy.describe()}')
        ..writeln(
          '     Duration: ${_formatDuration(durationFromTicks(segmentTicks))}',
        );
      if (phase.explain != null) {
        buffer.writeln('     Why: ${phase.explain}');
      }
    }

    return buffer.toString();
  }

  /// Pretty-print with full segment detail.
  String prettyPrintFull({int maxStepsPerSegment = 20}) {
    final buffer = StringBuffer()
      ..write(prettyPrintSummary())
      ..writeln()
      ..writeln('=== Segment Details ===');

    for (var i = 0; i < phases.length; i++) {
      final phase = phases[i];
      final segment = i < segments.length ? segments[i] : null;

      buffer
        ..writeln()
        ..writeln('--- Phase ${i + 1}: ${phase.policy.name} ---');

      if (segment != null) {
        buffer.writeln(segment.prettyPrint(maxSteps: maxStepsPerSegment));
      } else {
        buffer.writeln('  (no segment)');
      }
    }

    return buffer.toString();
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  @override
  List<Object?> get props => [metaGoal, phases, segments, totalTicks];
}
