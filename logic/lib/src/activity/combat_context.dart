import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// Combat context identifying what type of combat we're engaged in.
///
/// This is a sealed class with subtypes for different combat modes:
/// - [MonsterCombatContext] for fighting a single monster
/// - [DungeonCombatContext] for progressing through a dungeon
/// - [SlayerTaskContext] for working on a slayer task
@immutable
sealed class CombatContext {
  const CombatContext();

  /// The ID of the monster currently being fought.
  MelvorId get currentMonsterId;

  /// Serializes the context to JSON.
  Map<String, dynamic> toJson();

  /// Deserializes a context from JSON.
  static CombatContext fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'monster' => MonsterCombatContext.fromJson(json),
      'dungeon' => DungeonCombatContext.fromJson(json),
      'slayerTask' => SlayerTaskContext.fromJson(json),
      _ => throw ArgumentError('Unknown combat context type: $type'),
    };
  }
}

/// Context for fighting a single monster outside of any special mode.
@immutable
class MonsterCombatContext extends CombatContext {
  const MonsterCombatContext({required this.monsterId});

  factory MonsterCombatContext.fromJson(Map<String, dynamic> json) {
    return MonsterCombatContext(
      monsterId: MelvorId.fromJson(json['monsterId'] as String),
    );
  }

  /// The ID of the monster being fought.
  final MelvorId monsterId;

  @override
  MelvorId get currentMonsterId => monsterId;

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'monster', 'monsterId': monsterId.toJson()};
  }
}

/// Context for fighting through a dungeon.
///
/// A dungeon is a sequence of monsters that must be defeated in order.
/// The [currentMonsterIndex] tracks progress through the dungeon.
@immutable
class DungeonCombatContext extends CombatContext {
  const DungeonCombatContext({
    required this.dungeonId,
    required this.currentMonsterIndex,
    required this.monsterIds,
  });

  factory DungeonCombatContext.fromJson(Map<String, dynamic> json) {
    return DungeonCombatContext(
      dungeonId: MelvorId.fromJson(json['dungeonId'] as String),
      currentMonsterIndex: json['currentMonsterIndex'] as int,
      monsterIds: (json['monsterIds'] as List<dynamic>)
          .map((e) => MelvorId.fromJson(e as String))
          .toList(),
    );
  }

  /// The ID of the dungeon being run.
  final MelvorId dungeonId;

  /// The current monster index in the dungeon (0-based).
  final int currentMonsterIndex;

  /// The list of monster IDs in this dungeon, in order.
  /// Stored here to avoid needing registry lookups during tick processing.
  final List<MelvorId> monsterIds;

  @override
  MelvorId get currentMonsterId => monsterIds[currentMonsterIndex];

  /// Returns true if currently fighting the last monster in the dungeon.
  bool get isLastMonster => currentMonsterIndex == monsterIds.length - 1;

  /// Returns a new context with the monster index advanced by one.
  /// Wraps around to 0 if at the end (for dungeon restart).
  DungeonCombatContext advanceToNextMonster() {
    final nextIndex = (currentMonsterIndex + 1) % monsterIds.length;
    return DungeonCombatContext(
      dungeonId: dungeonId,
      currentMonsterIndex: nextIndex,
      monsterIds: monsterIds,
    );
  }

  DungeonCombatContext copyWith({
    MelvorId? dungeonId,
    int? currentMonsterIndex,
    List<MelvorId>? monsterIds,
  }) {
    return DungeonCombatContext(
      dungeonId: dungeonId ?? this.dungeonId,
      currentMonsterIndex: currentMonsterIndex ?? this.currentMonsterIndex,
      monsterIds: monsterIds ?? this.monsterIds,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'dungeon',
      'dungeonId': dungeonId.toJson(),
      'currentMonsterIndex': currentMonsterIndex,
      'monsterIds': monsterIds.map((e) => e.toJson()).toList(),
    };
  }
}

/// Context for working on a slayer task.
///
/// A slayer task requires killing a specific number of a given monster.
/// When completed, the player earns slayer coins and XP.
@immutable
class SlayerTaskContext extends CombatContext {
  const SlayerTaskContext({
    required this.categoryId,
    required this.monsterId,
    required this.killsRequired,
    required this.killsCompleted,
  });

  factory SlayerTaskContext.fromJson(Map<String, dynamic> json) {
    return SlayerTaskContext(
      categoryId: MelvorId.fromJson(json['categoryId'] as String),
      monsterId: MelvorId.fromJson(json['monsterId'] as String),
      killsRequired: json['killsRequired'] as int,
      killsCompleted: json['killsCompleted'] as int,
    );
  }

  /// The slayer task category (Easy, Normal, Hard, etc.).
  final MelvorId categoryId;

  /// The ID of the monster to kill for this task.
  final MelvorId monsterId;

  /// Total number of kills required to complete the task.
  final int killsRequired;

  /// Number of kills completed so far.
  final int killsCompleted;

  @override
  MelvorId get currentMonsterId => monsterId;

  /// Returns the number of kills remaining.
  int get killsRemaining => killsRequired - killsCompleted;

  /// Returns true if the task is complete.
  bool get isComplete => killsCompleted >= killsRequired;

  /// Returns a new context with an additional kill recorded.
  SlayerTaskContext recordKill() {
    return SlayerTaskContext(
      categoryId: categoryId,
      monsterId: monsterId,
      killsRequired: killsRequired,
      killsCompleted: killsCompleted + 1,
    );
  }

  SlayerTaskContext copyWith({
    MelvorId? categoryId,
    MelvorId? monsterId,
    int? killsRequired,
    int? killsCompleted,
  }) {
    return SlayerTaskContext(
      categoryId: categoryId ?? this.categoryId,
      monsterId: monsterId ?? this.monsterId,
      killsRequired: killsRequired ?? this.killsRequired,
      killsCompleted: killsCompleted ?? this.killsCompleted,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'slayerTask',
      'categoryId': categoryId.toJson(),
      'monsterId': monsterId.toJson(),
      'killsRequired': killsRequired,
      'killsCompleted': killsCompleted,
    };
  }
}
