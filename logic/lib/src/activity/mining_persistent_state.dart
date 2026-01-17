import 'dart:math';

import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/mining.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Persistent state for mining rocks across the game.
///
/// This tracks rock HP and respawn timers for each mining action,
/// stored separately from the active activity state. This allows
/// mining rocks to regenerate HP and respawn in the background
/// while performing other activities.
@immutable
class MiningPersistentState {
  const MiningPersistentState({this.rockStates = const {}});

  const MiningPersistentState.empty() : rockStates = const {};

  factory MiningPersistentState.fromJson(Map<String, dynamic> json) {
    final rockStatesJson = json['rockStates'] as Map<String, dynamic>? ?? {};
    final rockStates = <MelvorId, MiningRockState>{};
    for (final entry in rockStatesJson.entries) {
      rockStates[MelvorId.fromJson(entry.key)] = MiningRockState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return MiningPersistentState(rockStates: rockStates);
  }

  /// State for each mining rock, keyed by action ID (local part).
  final Map<MelvorId, MiningRockState> rockStates;

  /// Gets the state for a specific rock, or creates empty state if not found.
  MiningRockState rockState(MelvorId actionId) {
    return rockStates[actionId] ?? const MiningRockState.empty();
  }

  /// Returns a copy with updated state for a specific rock.
  MiningPersistentState withRockState(
    MelvorId actionId,
    MiningRockState state,
  ) {
    return MiningPersistentState(rockStates: {...rockStates, actionId: state});
  }

  Map<String, dynamic> toJson() {
    final rockStatesJson = <String, dynamic>{};
    for (final entry in rockStates.entries) {
      rockStatesJson[entry.key.toJson()] = entry.value.toJson();
    }
    return {'rockStates': rockStatesJson};
  }
}

/// State for a single mining rock (HP and respawn/regen timers).
@immutable
class MiningRockState {
  const MiningRockState({
    this.totalHpLost = 0,
    this.respawnTicksRemaining,
    this.hpRegenTicksRemaining = 0,
  });

  const MiningRockState.empty() : this();

  factory MiningRockState.fromJson(Map<String, dynamic> json) {
    return MiningRockState(
      totalHpLost: json['totalHpLost'] as int? ?? 0,
      respawnTicksRemaining: json['respawnTicksRemaining'] as int?,
      hpRegenTicksRemaining: json['hpRegenTicksRemaining'] as int? ?? 0,
    );
  }

  /// How much HP this mining rock has lost.
  final int totalHpLost;

  /// How many ticks until this mining rock respawns if depleted.
  /// Null if the rock is not depleted.
  final Tick? respawnTicksRemaining;

  /// How many ticks until this mining rock regens 1 HP.
  final Tick hpRegenTicksRemaining;

  /// Gets the current HP of a mining rock.
  int currentHp(MiningAction action, int masteryXp) {
    final masteryLevel = levelForXp(masteryXp);
    final maxHp = action.maxHpForMasteryLevel(masteryLevel);
    return max(0, maxHp - totalHpLost);
  }

  /// Returns true if the rock is currently depleted and not yet respawned.
  bool get isDepleted {
    final respawnTicks = respawnTicksRemaining;
    return respawnTicks != null && respawnTicks > 0;
  }

  MiningRockState copyWith({
    int? totalHpLost,
    Tick? respawnTicksRemaining,
    Tick? hpRegenTicksRemaining,
  }) {
    return MiningRockState(
      totalHpLost: totalHpLost ?? this.totalHpLost,
      respawnTicksRemaining:
          respawnTicksRemaining ?? this.respawnTicksRemaining,
      hpRegenTicksRemaining:
          hpRegenTicksRemaining ?? this.hpRegenTicksRemaining,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalHpLost': totalHpLost,
      if (respawnTicksRemaining != null)
        'respawnTicksRemaining': respawnTicksRemaining,
      'hpRegenTicksRemaining': hpRegenTicksRemaining,
    };
  }
}
