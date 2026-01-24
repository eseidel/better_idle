import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/progress_at.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// State for an active bonfire.
///
/// Bonfires are lit from logs and provide an XP bonus to firemaking
/// for their duration. The bonfire gradually burns down and the bonus
/// is lost when the timer expires.
@immutable
class BonfireState {
  const BonfireState({
    required this.actionId,
    required this.ticksRemaining,
    required this.totalTicks,
    required this.xpBonus,
  });

  const BonfireState.empty()
    : actionId = null,
      ticksRemaining = 0,
      totalTicks = 0,
      xpBonus = 0;

  factory BonfireState.fromJson(Map<String, dynamic> json) {
    final actionIdJson = json['actionId'];
    return BonfireState(
      actionId: actionIdJson != null
          ? ActionId.fromJson(actionIdJson as String)
          : null,
      ticksRemaining: json['ticksRemaining'] as Tick? ?? 0,
      totalTicks: json['totalTicks'] as Tick? ?? 0,
      xpBonus: json['xpBonus'] as int? ?? 0,
    );
  }

  /// Deserializes a [BonfireState] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static BonfireState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return BonfireState.fromJson(json as Map<String, dynamic>);
  }

  /// The firemaking action ID that produced this bonfire
  /// (e.g., Burn Normal Logs).
  /// Null if no bonfire is active.
  final ActionId? actionId;

  /// Ticks remaining until the bonfire burns out.
  final Tick ticksRemaining;

  /// Total ticks for this bonfire (used for progress bar display).
  final Tick totalTicks;

  /// XP bonus percentage while this bonfire is active.
  final int xpBonus;

  /// Returns true if a bonfire is currently active.
  bool get isActive => actionId != null && ticksRemaining > 0;

  /// Returns true if no bonfire is active.
  bool get isEmpty => !isActive;

  /// Returns the remaining duration as a Duration.
  Duration get remainingDuration => durationFromTicks(ticksRemaining);

  BonfireState copyWith({
    ActionId? actionId,
    Tick? ticksRemaining,
    Tick? totalTicks,
    int? xpBonus,
  }) {
    return BonfireState(
      actionId: actionId ?? this.actionId,
      ticksRemaining: ticksRemaining ?? this.ticksRemaining,
      totalTicks: totalTicks ?? this.totalTicks,
      xpBonus: xpBonus ?? this.xpBonus,
    );
  }

  /// Returns a new BonfireState with the given ticks consumed.
  /// If all ticks are consumed, returns an empty state.
  BonfireState consumeTicks(Tick ticks) {
    final newRemaining = ticksRemaining - ticks;
    if (newRemaining <= 0) {
      return const BonfireState.empty();
    }
    return copyWith(ticksRemaining: newRemaining);
  }

  Map<String, dynamic> toJson() {
    if (isEmpty) {
      return {};
    }
    return {
      if (actionId != null) 'actionId': actionId!.toJson(),
      'ticksRemaining': ticksRemaining,
      'totalTicks': totalTicks,
      'xpBonus': xpBonus,
    };
  }

  /// Converts bonfire state to a ProgressAt for smooth countdown animation.
  ///
  /// Returns progress as "consumed" (totalTicks - ticksRemaining). Use with
  /// TweenedProgressIndicator's countdown mode to show remaining time.
  ProgressAt toProgressAt(DateTime lastUpdateTime) {
    return ProgressAt(
      lastUpdateTime: lastUpdateTime,
      progressTicks: totalTicks - ticksRemaining,
      totalTicks: totalTicks,
      isAdvancing: isActive,
    );
  }
}
