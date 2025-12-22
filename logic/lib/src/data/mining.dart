import 'package:logic/src/action_state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

import 'actions.dart';
import 'melvor_id.dart';

const _miningSwingDuration = Duration(seconds: 3);

/// A mining rock action parsed from Melvor data.
///
/// Mining actions have rock HP and respawn mechanics.
@immutable
class MiningAction extends SkillAction {
  MiningAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.outputs,
    required int respawnSeconds,
    required this.rockType,
    required this.productId,
    required this.baseQuantity,
    required this.hasPassiveRegen,
    required this.giveGems,
    required this.media,
  }) : respawnTime = Duration(seconds: respawnSeconds),
       super(skill: Skill.mining, duration: _miningSwingDuration);

  factory MiningAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productId = MelvorId.fromJsonWithNamespace(
      json['productId'] as String,
      defaultNamespace: namespace,
    );
    final baseRespawnInterval = json['baseRespawnInterval'] as int;
    final baseQuantity = json['baseQuantity'] as int? ?? 1;
    final category = json['category'] as String?;

    return MiningAction(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      outputs: {productId: baseQuantity},
      respawnSeconds: baseRespawnInterval ~/ 1000,
      rockType: parseRockType(category),
      productId: productId,
      baseQuantity: baseQuantity,
      hasPassiveRegen: json['hasPassiveRegen'] as bool? ?? true,
      giveGems: json['giveGems'] as bool? ?? true,
      media: json['media'] as String,
    );
  }

  /// The type of rock (ore or essence).
  final RockType rockType;

  /// Time for the rock to respawn after being depleted.
  final Duration respawnTime;

  /// The Melvor product ID (e.g., "melvorD:Copper_Ore").
  final MelvorId productId;

  /// Base quantity of ore produced per mining action.
  final int baseQuantity;

  /// Whether the rock passively regenerates HP.
  final bool hasPassiveRegen;

  /// Whether mining this rock can give gems.
  final bool giveGems;

  /// The media path for the rock icon.
  final String media;

  /// Number of ticks for the rock to respawn.
  int get respawnTicks => ticksFromDuration(respawnTime);

  /// Rock HP = 5 + Mastery Level + Boosts
  /// For now, boosts are 0
  int maxHpForMasteryLevel(int masteryLevel) => 5 + masteryLevel;

  /// Returns progress (0.0 to 1.0) toward respawn completion, or null if
  /// not respawning.
  double? respawnProgress(ActionState actionState) {
    final remaining = actionState.mining?.respawnTicksRemaining;
    if (remaining == null) return null;
    return 1.0 - (remaining / respawnTicks);
  }
}

/// Gem drop table for mining - 1% chance to trigger, then weighted selection.
final miningGemTable = DropChance(
  DropTable(<DropTableEntry>[
    Pick('Topaz', weight: 100), // 100 / 200 = 5%
    Pick('Sapphire', weight: 35), // 35 / 200 = 17.5%
    Pick('Ruby', weight: 35), // 35 / 200 = 17.5%
    Pick('Emerald', weight: 20), // 20 / 200 = 10%
    Pick('Diamond', weight: 10), // 10 / 200 = 5%
  ]),
  rate: 0.01, // 1% chance to get a gem
);
