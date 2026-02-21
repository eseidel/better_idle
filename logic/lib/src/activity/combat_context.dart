import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// The type of monster sequence being fought.
enum SequenceType { dungeon, stronghold }

/// Combat context identifying what type of combat we're engaged in.
///
/// This is a sealed class with subtypes for different combat modes:
/// - [MonsterCombatContext] for fighting a single monster
/// - [SequenceCombatContext] for progressing through a dungeon or stronghold
/// - [SlayerAreaCombatContext] for fighting in a slayer area
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
      'dungeon' || 'stronghold' => SequenceCombatContext.fromJson(json),
      // Migration: old saves stored slayer tasks as a combat context.
      // Now they are a separate GlobalState field; treat as regular combat.
      'slayerTask' => MonsterCombatContext(
        monsterId: MelvorId.fromJson(json['monsterId'] as String),
      ),
      'slayerArea' => SlayerAreaCombatContext.fromJson(json),
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

/// Context for fighting through a sequence of monsters (dungeon or stronghold).
///
/// The [currentMonsterIndex] tracks progress through the sequence.
@immutable
class SequenceCombatContext extends CombatContext {
  const SequenceCombatContext({
    required this.sequenceType,
    required this.sequenceId,
    required this.currentMonsterIndex,
    required this.monsterIds,
  });

  factory SequenceCombatContext.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final sequenceType = SequenceType.values.byName(type);
    // The ID field name varies by type for backwards compatibility.
    final idKey = switch (sequenceType) {
      SequenceType.dungeon => 'dungeonId',
      SequenceType.stronghold => 'strongholdId',
    };
    return SequenceCombatContext(
      sequenceType: sequenceType,
      sequenceId: MelvorId.fromJson(json[idKey] as String),
      currentMonsterIndex: json['currentMonsterIndex'] as int,
      monsterIds: (json['monsterIds'] as List<dynamic>)
          .map((e) => MelvorId.fromJson(e as String))
          .toList(),
    );
  }

  /// Whether this is a dungeon or stronghold.
  final SequenceType sequenceType;

  /// The ID of the dungeon or stronghold being run.
  final MelvorId sequenceId;

  /// The current monster index (0-based).
  final int currentMonsterIndex;

  /// The list of monster IDs in order.
  /// Stored here to avoid needing registry lookups during tick processing.
  final List<MelvorId> monsterIds;

  @override
  MelvorId get currentMonsterId => monsterIds[currentMonsterIndex];

  /// Returns true if currently fighting the last monster in the sequence.
  bool get isLastMonster => currentMonsterIndex == monsterIds.length - 1;

  /// Returns a new context with the monster index advanced by one.
  /// Wraps around to 0 if at the end (for sequence restart).
  SequenceCombatContext advanceToNextMonster() {
    final nextIndex = (currentMonsterIndex + 1) % monsterIds.length;
    return SequenceCombatContext(
      sequenceType: sequenceType,
      sequenceId: sequenceId,
      currentMonsterIndex: nextIndex,
      monsterIds: monsterIds,
    );
  }

  SequenceCombatContext copyWith({
    SequenceType? sequenceType,
    MelvorId? sequenceId,
    int? currentMonsterIndex,
    List<MelvorId>? monsterIds,
  }) {
    return SequenceCombatContext(
      sequenceType: sequenceType ?? this.sequenceType,
      sequenceId: sequenceId ?? this.sequenceId,
      currentMonsterIndex: currentMonsterIndex ?? this.currentMonsterIndex,
      monsterIds: monsterIds ?? this.monsterIds,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final idKey = switch (sequenceType) {
      SequenceType.dungeon => 'dungeonId',
      SequenceType.stronghold => 'strongholdId',
    };
    return {
      'type': sequenceType.name,
      idKey: sequenceId.toJson(),
      'currentMonsterIndex': currentMonsterIndex,
      'monsterIds': monsterIds.map((e) => e.toJson()).toList(),
    };
  }
}

/// Context for fighting a monster within a slayer area.
///
/// Tracks which slayer area the player is in so that area requirements
/// can be enforced (e.g. blocking gear changes that would violate them).
@immutable
class SlayerAreaCombatContext extends CombatContext {
  const SlayerAreaCombatContext({
    required this.slayerAreaId,
    required this.monsterId,
  });

  factory SlayerAreaCombatContext.fromJson(Map<String, dynamic> json) {
    return SlayerAreaCombatContext(
      slayerAreaId: MelvorId.fromJson(json['slayerAreaId'] as String),
      monsterId: MelvorId.fromJson(json['monsterId'] as String),
    );
  }

  /// The ID of the slayer area the player is fighting in.
  final MelvorId slayerAreaId;

  /// The ID of the monster being fought.
  final MelvorId monsterId;

  @override
  MelvorId get currentMonsterId => monsterId;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'slayerArea',
      'slayerAreaId': slayerAreaId.toJson(),
      'monsterId': monsterId.toJson(),
    };
  }
}
