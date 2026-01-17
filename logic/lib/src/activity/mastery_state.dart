import 'package:logic/src/data/xp.dart';
import 'package:meta/meta.dart';

/// Per-action mastery tracking state.
///
/// This is the new replacement for the mastery-related fields in
/// the old [ActionState] class. It only contains mastery XP and
/// cumulative time tracking, not combat/mining state or recipe selection.
///
/// Mastery is tracked per-action (e.g., each specific woodcutting action
/// like Oak Tree has its own mastery XP), stored in a
/// `Map<ActionId, MasteryState>`.
@immutable
class MasteryState {
  const MasteryState({required this.masteryXp, this.cumulativeTicks = 0});

  const MasteryState.empty() : this(masteryXp: 0);

  factory MasteryState.fromJson(Map<String, dynamic> json) {
    return MasteryState(
      masteryXp: json['masteryXp'] as int,
      cumulativeTicks: json['cumulativeTicks'] as int? ?? 0,
    );
  }

  /// How much accumulated mastery XP this action has.
  final int masteryXp;

  /// Cumulative ticks spent performing this action (all time).
  final int cumulativeTicks;

  /// The mastery level for this action, derived from mastery XP.
  int get masteryLevel => levelForXp(masteryXp);

  MasteryState copyWith({int? masteryXp, int? cumulativeTicks}) {
    return MasteryState(
      masteryXp: masteryXp ?? this.masteryXp,
      cumulativeTicks: cumulativeTicks ?? this.cumulativeTicks,
    );
  }

  Map<String, dynamic> toJson() {
    return {'masteryXp': masteryXp, 'cumulativeTicks': cumulativeTicks};
  }
}
