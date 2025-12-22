import 'actions.dart';
import 'melvor_id.dart';

/// A mining rock action parsed from Melvor data.
///
/// Extends MiningAction so it can be used directly in the game.
class MiningRock extends MiningAction {
  MiningRock({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.outputs,
    required super.respawnSeconds,
    required super.rockType,
    required this.productId,
    required this.baseQuantity,
    required this.hasPassiveRegen,
    required this.giveGems,
    required this.media,
  });

  factory MiningRock.fromJson(
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

    return MiningRock(
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

  /// The output item name (e.g., "Copper Ore").
  String get outputName => outputs.keys.first.name;

  @override
  String toString() {
    return '$name (level $unlockLevel, ${respawnTime.inSeconds}s respawn, '
        '${xp}xp) -> $outputName x$baseQuantity';
  }
}
