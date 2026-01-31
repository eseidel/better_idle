import 'dart:math';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/state.dart' show CombatType;
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

/// Combat stats for a player or monster.
@immutable
class Stats {
  const Stats({
    required this.minHit,
    required this.maxHit,
    required this.damageReduction,
    required this.attackSpeed,
  });

  /// Minimum damage dealt per attack.
  final int minHit;

  /// Maximum damage dealt per attack.
  final int maxHit;

  /// Percentage of damage reduced (0.0 to 1.0).
  final double damageReduction;

  /// Seconds between attacks.
  final double attackSpeed;

  /// Roll a random damage value between minHit and maxHit (inclusive).
  int rollDamage(Random random) {
    if (minHit == maxHit) return minHit;
    return minHit + random.nextInt((maxHit - minHit) + 1);
  }
}

/// Monster levels used for combat calculations.
@immutable
class MonsterLevels {
  const MonsterLevels({
    required this.hitpoints,
    required this.attack,
    required this.strength,
    required this.defense,
    required this.ranged,
    required this.magic,
  });

  factory MonsterLevels.fromJson(Map<String, dynamic> json) {
    return MonsterLevels(
      hitpoints: json['Hitpoints'] as int,
      attack: json['Attack'] as int,
      strength: json['Strength'] as int,
      // The json uses the british spelling of defense.
      defense: json['Defence'] as int, // cspell:disable-line
      ranged: json['Ranged'] as int,
      magic: json['Magic'] as int,
    );
  }

  final int hitpoints;
  final int attack;
  final int strength;
  final int defense;
  final int ranged;
  final int magic;

  /// Calculates the combat level using the Melvor formula.
  /// Combat level = (Defense + Hitpoints + floor(Prayer / 2)) / 4
  ///              + max(Attack + Strength, Ranged * 1.5, Magic * 1.5) * 0.325
  int get combatLevel {
    final base = (defense + hitpoints) / 4;
    final melee = attack + strength;
    final rangedContrib = ranged * 1.5;
    final magicContrib = magic * 1.5;
    final maxOffense = [
      melee.toDouble(),
      rangedContrib,
      magicContrib,
    ].reduce((a, b) => a > b ? a : b);
    return (base + maxOffense * 0.325).floor();
  }
}

/// Bones dropped by a monster on death.
/// Each monster only drops one kind of bones, up to a specific quantity.
@immutable
class BonesDrop {
  const BonesDrop({required this.itemId, required this.quantity});

  factory BonesDrop.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return BonesDrop(
      itemId: MelvorId.fromJsonWithNamespace(
        json['itemID'] as String,
        defaultNamespace: namespace,
      ),
      quantity: json['quantity'] as int,
    );
  }

  final MelvorId itemId;
  final int quantity;
}

/// Type of attack the monster uses.
enum AttackType {
  melee,
  ranged,
  magic,
  random;

  factory AttackType.fromJson(String value) {
    return AttackType.values.firstWhere((e) => e.name == value);
  }

  /// Returns the corresponding CombatType for this attack type.
  /// For random, defaults to melee.
  CombatType get combatType => switch (this) {
    // TODO(eseidel): mapping random here seems wrong?
    AttackType.melee || AttackType.random => CombatType.melee,
    AttackType.ranged => CombatType.ranged,
    AttackType.magic => CombatType.magic,
  };
}

/// A combat action for fighting a specific monster.
/// Unlike skill actions, combat doesn't complete after a duration - attacks
/// happen on timers and the action continues until stopped or player dies.
@immutable
class CombatAction extends Action {
  const CombatAction({
    required super.id,
    required super.name,
    required this.levels,
    required this.attackType,
    required this.attackSpeed,
    required this.lootChance,
    required this.minGpDrop,
    required this.maxGpDrop,
    this.bones,
    this.lootTable,
    this.media,
    this.canSlayer = true,
    this.isBoss = false,
  }) : super(skill: Skill.attack);

  factory CombatAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final levels = MonsterLevels.fromJson(
      json['levels'] as Map<String, dynamic>,
    );

    // Parse attack speed from equipmentStats.
    final equipmentStats = json['equipmentStats'] as List<dynamic>? ?? [];
    var attackSpeed = 2.4; // Default attack speed in seconds
    for (final stat in equipmentStats) {
      final statMap = stat as Map<String, dynamic>;
      if (statMap['key'] == 'attackSpeed') {
        // Value is in milliseconds, convert to seconds
        attackSpeed = (statMap['value'] as int) / 1000;
        break;
      }
    }

    // Parse currency drops for GP.
    final currencyDrops = json['currencyDrops'] as List<dynamic>? ?? [];
    var minGp = 0;
    var maxGp = 0;
    for (final drop in currencyDrops) {
      final dropMap = drop as Map<String, dynamic>;
      final currencyId = dropMap['currencyID'] as String;
      if (currencyId == 'melvorD:GP') {
        minGp = dropMap['min'] as int;
        maxGp = dropMap['max'] as int;
        break;
      }
    }

    // Parse bones drop.
    BonesDrop? bones;
    final bonesJson = json['bones'] as Map<String, dynamic>?;
    if (bonesJson != null) {
      bones = BonesDrop.fromJson(bonesJson, namespace: namespace);
    }

    // Parse loot table.
    Droppable? lootTable;
    final lootTableJson = json['lootTable'] as List<dynamic>? ?? [];
    final lootChanceRaw = json['lootChance'];
    final lootChance = lootChanceRaw is int
        ? lootChanceRaw
        : (lootChanceRaw as num?)?.toInt() ?? 0;
    if (lootTableJson.isNotEmpty && lootChance > 0) {
      final entries = lootTableJson
          .map(
            (lootJson) =>
                DropTableEntry.fromJson(lootJson as Map<String, dynamic>),
          )
          .toList();
      // lootChance is a percentage (0-100), convert to rate (0-1)
      lootTable = DropChance(DropTable(entries), rate: lootChance / 100);
    }

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return CombatAction(
      id: ActionId(Skill.combat.id, localId),
      name: json['name'] as String,
      levels: levels,
      attackType: AttackType.fromJson(json['attackType'] as String),
      attackSpeed: attackSpeed,
      lootChance: lootChance,
      minGpDrop: minGp,
      maxGpDrop: maxGp,
      bones: bones,
      lootTable: lootTable,
      media: json['media'] as String?,
      canSlayer: json['canSlayer'] as bool? ?? true,
      isBoss: json['isBoss'] as bool? ?? false,
    );
  }

  /// The monster's levels
  final MonsterLevels levels;

  /// The type of attack this monster uses.
  final AttackType attackType;

  /// Seconds between attacks.
  final double attackSpeed;

  /// Chance (0-100) that the loot table drops something.
  final int lootChance;

  /// Minimum GP dropped on kill.
  final int minGpDrop;

  /// Maximum GP dropped on kill.
  final int maxGpDrop;

  /// Bones dropped on kill (null if no bones).
  final BonesDrop? bones;

  /// The loot table for this monster (null if no loot).
  final Droppable? lootTable;

  /// The media path for the monster icon.
  final String? media;

  /// Whether this monster counts for slayer tasks.
  final bool canSlayer;

  /// Whether this monster is a boss.
  final bool isBoss;

  /// The monster's max HP (hitpoints level * 10 in Melvor).
  int get maxHp => levels.hitpoints * 10;

  /// The monster's combat level.
  int get combatLevel => levels.combatLevel;

  /// Calculate monster stats for combat.
  /// This is a simplified calculation - full Melvor has more complex formulas.
  // TODO(eseidel): Add more complete formulas.
  Stats get stats {
    // Calculate max hit based on attack type and levels.
    // Simplified formula: strength-based for melee, ranged/magic for others.
    final effectiveLevel = switch (attackType) {
      AttackType.melee => levels.strength,
      AttackType.ranged => levels.ranged,
      AttackType.magic => levels.magic,
      AttackType.random => [
        levels.strength,
        levels.ranged,
        levels.magic,
      ].reduce((a, b) => a > b ? a : b),
    };

    // Simplified max hit calculation.
    // In Melvor, max hit = floor(0.5 + effectiveLevel * (1 + strengthBonus/64))
    // We'll use a simpler formula for now.
    final maxHit = (effectiveLevel * 1.3).round().clamp(1, 9999);

    return Stats(
      minHit: 0,
      maxHit: maxHit,
      damageReduction: 0, // Monsters don't have damage reduction in base game
      attackSpeed: attackSpeed,
    );
  }

  /// Roll a random GP drop between minGpDrop and maxGpDrop (inclusive).
  int rollGpDrop(Random random) {
    if (minGpDrop >= maxGpDrop) return maxGpDrop;
    return minGpDrop + random.nextInt((maxGpDrop - minGpDrop) + 1);
  }
}

/// A combat area containing multiple monsters.
@immutable
class CombatArea {
  const CombatArea({
    required this.id,
    required this.name,
    required this.monsterIds,
    this.difficulty = const [],
    this.media,
  });

  factory CombatArea.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final monsterIds = (json['monsterIDs'] as List<dynamic>)
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final difficultyRaw = json['difficulty'] as List<dynamic>? ?? [];
    final difficulty = difficultyRaw.map((e) => e as int).toList();

    return CombatArea(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      monsterIds: monsterIds,
      difficulty: difficulty,
      media: json['media'] as String?,
    );
  }

  final MelvorId id;
  final String name;
  final List<MelvorId> monsterIds;
  final List<int> difficulty;
  final String? media;
}

/// Registry for combat areas.
@immutable
class CombatAreaRegistry {
  CombatAreaRegistry(List<CombatArea> areas) : _areas = areas {
    _byId = {for (final area in _areas) area.id: area};
  }

  final List<CombatArea> _areas;
  late final Map<MelvorId, CombatArea> _byId;

  /// Returns all combat areas.
  List<CombatArea> get all => _areas;

  /// Returns a combat area by ID, or null if not found.
  CombatArea? byId(MelvorId id) => _byId[id];
}

/// A dungeon (similar structure to combat area).
@immutable
class Dungeon {
  const Dungeon({
    required this.id,
    required this.name,
    required this.monsterIds,
    this.difficulty = const [],
    this.media,
  });

  factory Dungeon.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final monsterIds = (json['monsterIDs'] as List<dynamic>)
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final difficultyRaw = json['difficulty'] as List<dynamic>? ?? [];
    final difficulty = difficultyRaw.map((e) => e as int).toList();

    return Dungeon(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      monsterIds: monsterIds,
      difficulty: difficulty,
      media: json['media'] as String?,
    );
  }

  final MelvorId id;
  final String name;
  final List<MelvorId> monsterIds;
  final List<int> difficulty;
  final String? media;
}

/// Registry for dungeons.
@immutable
class DungeonRegistry {
  DungeonRegistry(List<Dungeon> dungeons) : _dungeons = dungeons {
    _byId = {for (final dungeon in _dungeons) dungeon.id: dungeon};
  }

  final List<Dungeon> _dungeons;
  late final Map<MelvorId, Dungeon> _byId;

  /// Returns all dungeons.
  List<Dungeon> get all => _dungeons;

  /// Returns a dungeon by ID.
  /// Throws [StateError] if the dungeon is not found.
  Dungeon byId(MelvorId id) {
    final dungeon = _byId[id];
    if (dungeon == null) {
      throw StateError('Missing dungeon with id: $id');
    }
    return dungeon;
  }
}

/// A stronghold (similar structure to dungeon).
@immutable
class Stronghold {
  const Stronghold({
    required this.id,
    required this.name,
    required this.monsterIds,
    this.difficulty = const [],
    this.media,
  });

  factory Stronghold.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final monsterIds = (json['monsterIDs'] as List<dynamic>)
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final difficultyRaw = json['difficulty'] as List<dynamic>? ?? [];
    final difficulty = difficultyRaw.map((e) => e as int).toList();

    return Stronghold(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      monsterIds: monsterIds,
      difficulty: difficulty,
      media: json['media'] as String?,
    );
  }

  final MelvorId id;
  final String name;
  final List<MelvorId> monsterIds;
  final List<int> difficulty;
  final String? media;
}

/// Registry for strongholds.
@immutable
class StrongholdRegistry {
  StrongholdRegistry(List<Stronghold> strongholds)
    : _strongholds = strongholds {
    _byId = {for (final stronghold in _strongholds) stronghold.id: stronghold};
  }

  final List<Stronghold> _strongholds;
  late final Map<MelvorId, Stronghold> _byId;

  /// Returns all strongholds.
  List<Stronghold> get all => _strongholds;

  /// Returns a stronghold by ID.
  /// Throws [StateError] if the stronghold is not found.
  Stronghold byId(MelvorId id) {
    final stronghold = _byId[id];
    if (stronghold == null) {
      throw StateError('Missing stronghold with id: $id');
    }
    return stronghold;
  }
}

/// Unified registry for all combat-related data.
@immutable
class CombatRegistry {
  CombatRegistry({
    required List<CombatAction> monsters,
    required this.areas,
    required this.dungeons,
    required this.strongholds,
  }) : _monsters = monsters {
    _byId = {for (final m in _monsters) m.id.localId: m};
  }

  final List<CombatAction> _monsters;
  late final Map<MelvorId, CombatAction> _byId;

  /// All combat areas.
  final CombatAreaRegistry areas;

  /// All dungeons.
  final DungeonRegistry dungeons;

  /// All strongholds.
  final StrongholdRegistry strongholds;

  /// All monsters.
  List<CombatAction> get monsters => _monsters;

  /// Look up a monster by its local ID.
  /// Throws [StateError] if the monster is not found.
  CombatAction monsterById(MelvorId localId) {
    final monster = _byId[localId];
    if (monster == null) {
      throw StateError('Missing monster with id: $localId');
    }
    return monster;
  }
}
