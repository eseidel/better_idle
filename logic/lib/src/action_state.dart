import 'dart:math';

import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'data/actions.dart';
import 'data/melvor_id.dart';
import 'data/xp.dart';

/// Mining-specific state for rock HP and respawn.
class MiningState {
  const MiningState({
    this.totalHpLost = 0,
    this.respawnTicksRemaining,
    this.hpRegenTicksRemaining = 0,
  });

  const MiningState.empty() : this();

  factory MiningState.fromJson(Map<String, dynamic> json) {
    return MiningState(
      totalHpLost: json['totalHpLost'] as int? ?? 0,
      respawnTicksRemaining: json['respawnTicksRemaining'] as int?,
      hpRegenTicksRemaining: json['hpRegenTicksRemaining'] as int? ?? 0,
    );
  }

  /// Gets the current HP of a mining node.
  int currentHp(MiningAction action, int masteryXp) {
    final masteryLevel = levelForXp(masteryXp);
    final maxHp = action.maxHpForMasteryLevel(masteryLevel);
    return max(0, maxHp - totalHpLost);
  }

  /// How much HP this mining node has lost.
  final int totalHpLost;

  /// How many ticks until this mining node respawns if depleted.
  final Tick? respawnTicksRemaining; // Null if not depleted

  /// How many ticks until this mining node regens 1 HP.
  final Tick hpRegenTicksRemaining; // Ticks until next HP regen

  /// Returns true if the node is currently depleted and not yet respawned.
  bool get isDepleted {
    final respawnTicks = respawnTicksRemaining;
    return respawnTicks != null && respawnTicks > 0;
  }

  MiningState copyWith({
    int? totalHpLost,
    Tick? respawnTicksRemaining,
    Tick? hpRegenTicksRemaining,
  }) {
    return MiningState(
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
      'respawnTicksRemaining': respawnTicksRemaining,
      'hpRegenTicksRemaining': hpRegenTicksRemaining,
    };
  }
}

/// Respawn time for monsters after death.
const Duration monsterRespawnDuration = Duration(seconds: 3);

/// Combat-specific state for fighting a monster.
@immutable
class CombatActionState {
  const CombatActionState({
    required this.monsterId,
    required this.monsterHp,
    required this.playerAttackTicksRemaining,
    required this.monsterAttackTicksRemaining,
    this.respawnTicksRemaining,
  });

  /// Start a new combat against a monster.
  factory CombatActionState.start(CombatAction action, Stats playerStats) {
    final playerAttackTicks = ticksFromDuration(
      Duration(milliseconds: (playerStats.attackSpeed * 1000).round()),
    );
    final monsterAttackTicks = ticksFromDuration(
      Duration(milliseconds: (action.stats.attackSpeed * 1000).round()),
    );
    return CombatActionState(
      monsterId: action.id,
      monsterHp: action.maxHp,
      playerAttackTicksRemaining: playerAttackTicks,
      monsterAttackTicksRemaining: monsterAttackTicks,
    );
  }

  factory CombatActionState.fromJson(Map<String, dynamic> json) {
    return CombatActionState(
      monsterId: MelvorId.fromJson(json['monsterId'] as String),
      monsterHp: json['monsterHp'] as int,
      playerAttackTicksRemaining: json['playerAttackTicksRemaining'] as int,
      monsterAttackTicksRemaining: json['monsterAttackTicksRemaining'] as int,
      respawnTicksRemaining: json['respawnTicksRemaining'] as int?,
    );
  }

  /// The ID of the monster being fought.
  final MelvorId monsterId;
  final int monsterHp;
  final int playerAttackTicksRemaining;
  final int monsterAttackTicksRemaining;
  final int? respawnTicksRemaining;

  bool get isMonsterDead => monsterHp <= 0;
  bool get isRespawning => respawnTicksRemaining != null;

  CombatActionState copyWith({
    MelvorId? monsterId,
    int? monsterHp,
    int? playerAttackTicksRemaining,
    int? monsterAttackTicksRemaining,
    int? respawnTicksRemaining,
  }) {
    return CombatActionState(
      monsterId: monsterId ?? this.monsterId,
      monsterHp: monsterHp ?? this.monsterHp,
      playerAttackTicksRemaining:
          playerAttackTicksRemaining ?? this.playerAttackTicksRemaining,
      monsterAttackTicksRemaining:
          monsterAttackTicksRemaining ?? this.monsterAttackTicksRemaining,
      respawnTicksRemaining:
          respawnTicksRemaining ?? this.respawnTicksRemaining,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monsterId': monsterId.toJson(),
      'monsterHp': monsterHp,
      'playerAttackTicksRemaining': playerAttackTicksRemaining,
      'monsterAttackTicksRemaining': monsterAttackTicksRemaining,
      'respawnTicksRemaining': respawnTicksRemaining,
    };
  }
}

/// The serialized state of an Action in progress.
@immutable
class ActionState {
  const ActionState({required this.masteryXp, this.mining, this.combat});

  const ActionState.empty() : this(masteryXp: 0);

  factory ActionState.fromJson(Map<String, dynamic> json) {
    return ActionState(
      masteryXp: json['masteryXp'] as int,
      mining: json['mining'] != null
          ? MiningState.fromJson(json['mining'] as Map<String, dynamic>)
          : null,
      combat: json['combat'] != null
          ? CombatActionState.fromJson(json['combat'] as Map<String, dynamic>)
          : null,
    );
  }

  /// How much accumulated mastery xp this action has.
  final int masteryXp;

  /// Mining-specific state (null for non-mining actions).
  final MiningState? mining;

  /// Combat-specific state (null for non-combat actions).
  final CombatActionState? combat;

  /// The mastery level for this action, derived from mastery XP.
  int get masteryLevel => levelForXp(masteryXp);

  ActionState copyWith({
    int? masteryXp,
    MiningState? mining,
    CombatActionState? combat,
  }) {
    return ActionState(
      masteryXp: masteryXp ?? this.masteryXp,
      mining: mining ?? this.mining,
      combat: combat ?? this.combat,
    );
  }

  /// Create a new state for this action, as though it restarted fresh.
  ActionState copyRestarting() {
    return ActionState(masteryXp: masteryXp);
  }

  Map<String, dynamic> toJson() {
    return {
      'masteryXp': masteryXp,
      if (mining != null) 'mining': mining!.toJson(),
      if (combat != null) 'combat': combat!.toJson(),
    };
  }
}
