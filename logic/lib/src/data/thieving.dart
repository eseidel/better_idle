import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

import 'action_id.dart';

/// Duration for all thieving actions.
const thievingDuration = Duration(seconds: 3);

// TODO(eseidel): Confirm these rates from Melvor wiki or game source.
/// Drop rate for area unique drops (e.g., Crate of Basic Supplies).
const double areaUniqueDropRate = 1 / 500;

/// Chance that a thieving loot table drops something (vs nothing).
const double lootTableDropChance = 0.75;

/// Thieving area - groups NPCs together.
/// May include area-level drops that apply to all NPCs in the area.
@immutable
class ThievingArea {
  const ThievingArea({
    required this.id,
    required this.name,
    required this.npcIds,
    this.uniqueDrops = const [],
  });

  factory ThievingArea.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final npcIds = (json['npcIDs'] as List<dynamic>)
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final uniqueDropsJson = json['uniqueDrops'] as List<dynamic>? ?? [];
    final uniqueDrops = <Drop>[];
    for (final dropJson in uniqueDropsJson) {
      final dropMap = dropJson as Map<String, dynamic>;
      final itemId = MelvorId.fromJsonWithNamespace(
        dropMap['id'] as String,
        defaultNamespace: namespace,
      );
      final quantity = dropMap['quantity'] as int? ?? 1;
      uniqueDrops.add(Drop(itemId, count: quantity, rate: areaUniqueDropRate));
    }

    return ThievingArea(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      npcIds: npcIds,
      uniqueDrops: uniqueDrops,
    );
  }

  final MelvorId id;
  final String name;
  final List<MelvorId> npcIds;

  /// Drops that apply to all NPCs in this area.
  final List<Drop> uniqueDrops;
}

/// Registry for thieving areas.
class ThievingAreaRegistry {
  ThievingAreaRegistry(List<ThievingArea> areas) : _areas = areas;

  final List<ThievingArea> _areas;

  /// Returns the thieving area containing the given NPC ID.
  ///
  /// Throws [StateError] if the NPC is not found in any area.
  ThievingArea areaForNpc(MelvorId npcId) {
    for (final area in _areas) {
      if (area.npcIds.contains(npcId)) {
        return area;
      }
    }
    throw StateError('Thieving NPC $npcId has no area');
  }
}

// TODO(eseidel): roll this into defaultRewards?
List<Droppable> _thievingRewards(
  SkillAction action,
  RecipeSelection selection,
) {
  final thievingAction = action as ThievingAction;
  final areaDrops = thievingAction.area.uniqueDrops;
  final actionDropTable = thievingAction.dropTable;
  if (actionDropTable != null) {
    return [actionDropTable, ...areaDrops];
  }
  assert(
    thievingAction.outputs.isEmpty,
    'ThievingAction ${thievingAction.name} has outputs but no drop table.',
  );
  return [...areaDrops];
}

/// Thieving action with success/fail mechanics.
/// On success: grants 1-maxGold GP and rolls for drops.
/// On failure: deals 1-maxHit damage and stuns the player.
@immutable
class ThievingAction extends SkillAction {
  const ThievingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required this.perception,
    required this.maxHit,
    required this.maxGold,
    required this.area,
    super.outputs = const {},
    this.dropTable,
    this.media,
  }) : super(
         skill: Skill.thieving,
         duration: thievingDuration,
         rewardsAtLevel: _thievingRewards,
       );

  factory ThievingAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
    required ThievingArea area,
  }) {
    // Parse currency drops to get max gold.
    final currencyDrops = json['currencyDrops'] as List<dynamic>? ?? [];
    var maxGold = 0;
    for (final drop in currencyDrops) {
      final dropMap = drop as Map<String, dynamic>;
      final currencyId = dropMap['id'] as String;
      if (currencyId == 'melvorD:GP') {
        maxGold = dropMap['quantity'] as int;
        break;
      }
    }

    // Parse loot table using DropTableEntry.
    final lootTableJson = json['lootTable'] as List<dynamic>? ?? [];
    Droppable? dropTable;
    if (lootTableJson.isNotEmpty) {
      final entries = lootTableJson
          .map(
            (lootJson) => DropTableEntry.fromThievingJson(
              lootJson as Map<String, dynamic>,
              namespace: namespace,
            ),
          )
          .toList();
      dropTable = DropChance(DropTable(entries), rate: lootTableDropChance);
    }

    // maxHit in JSON is in units of 10 HP (e.g., 2.2 = 22 damage).
    final maxHitRaw = json['maxHit'];
    final maxHit = maxHitRaw is int
        ? maxHitRaw * 10
        : ((maxHitRaw as double) * 10).round();

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return ThievingAction(
      id: ActionId(Skill.thieving.id, localId),
      name: json['name'] as String,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      perception: json['perception'] as int,
      maxHit: maxHit,
      maxGold: maxGold,
      area: area,
      dropTable: dropTable,
      media: json['media'] as String?,
    );
  }

  /// NPC perception - used to calculate success rate.
  final int perception;

  /// Maximum damage dealt on failure (1-maxHit).
  final int maxHit;

  /// Maximum gold granted on success (1-maxGold).
  final int maxGold;

  /// The area this NPC belongs to.
  final ThievingArea area;

  /// The drop table for this NPC.
  final Droppable? dropTable;

  /// The media path for the NPC icon.
  final String? media;

  /// Rolls damage dealt on failure (1 to maxHit inclusive).
  int rollDamage(Random random) {
    if (maxHit <= 1) return 1;
    return 1 + random.nextInt(maxHit);
  }

  /// Rolls gold granted on success (1 to maxGold inclusive).
  int rollGold(Random random) {
    if (maxGold <= 1) return 1;
    return 1 + random.nextInt(maxGold);
  }

  /// Determines if the thieving attempt succeeds.
  /// Success chance = min(1, (100 + stealth) / (100 + perception))
  /// where stealth = 40 + thievingLevel + actionMasteryLevel
  bool rollSuccess(Random random, int thievingLevel, int actionMasteryLevel) {
    final stealth = calculateStealth(thievingLevel, actionMasteryLevel);
    final successChance = ((100 + stealth) / (100 + perception)).clamp(
      0.0,
      1.0,
    );
    final roll = random.nextDouble();
    return roll < successChance;
  }
}

/// Base stealth value before skill/mastery bonuses.
const int baseStealth = 40;

/// Calculates stealth value for thieving.
/// Stealth = 40 + thieving level + action mastery level
int calculateStealth(int thievingLevel, int actionMasteryLevel) {
  return baseStealth + thievingLevel + actionMasteryLevel;
}
