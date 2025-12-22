import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A fishing area parsed from Melvor data.
@immutable
class FishingAreaData {
  const FishingAreaData({
    required this.id,
    required this.name,
    required this.fishChance,
    required this.junkChance,
    required this.specialChance,
    required this.fishIDs,
    this.requiredItemID,
    this.isSecret = false,
  });

  factory FishingAreaData.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final fishIDs = (json['fishIDs'] as List<dynamic>)
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final requiredItemIDJson = json['requiredItemID'] as String?;

    return FishingAreaData(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      fishChance: (json['fishChance'] as int) / 100,
      junkChance: (json['junkChance'] as int) / 100,
      specialChance: (json['specialChance'] as int) / 100,
      fishIDs: fishIDs,
      requiredItemID: requiredItemIDJson != null
          ? MelvorId.fromJsonWithNamespace(
              requiredItemIDJson,
              defaultNamespace: namespace,
            )
          : null,
      isSecret: json['isSecret'] as bool? ?? false,
    );
  }

  final MelvorId id;
  final String name;
  final double fishChance;
  final double junkChance;
  final double specialChance;
  final List<MelvorId> fishIDs;
  final MelvorId? requiredItemID;
  final bool isSecret;

  @override
  String toString() {
    return '$name (fish: ${(fishChance * 100).toInt()}%, '
        'junk: ${(junkChance * 100).toInt()}%, '
        'special: ${(specialChance * 100).toInt()}%)';
  }
}

/// A fishing action parsed from Melvor data.
///
/// Extends SkillAction so it can be used directly in the game.
@immutable
class FishingFish extends SkillAction {
  FishingFish({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.outputs,
    required super.minDuration,
    required super.maxDuration,
    required this.productId,
    required this.strengthXP,
    required this.media,
  }) : super.ranged(skill: Skill.fishing);

  factory FishingFish.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productId = MelvorId.fromJsonWithNamespace(
      json['productId'] as String,
      defaultNamespace: namespace,
    );
    final baseMinInterval = json['baseMinInterval'] as int;
    final baseMaxInterval = json['baseMaxInterval'] as int;

    // Use item name from productId for action name (e.g., "Raw Shrimp").
    final name = productId.name;

    return FishingFish(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: name,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      outputs: {productId: 1},
      minDuration: Duration(milliseconds: baseMinInterval),
      maxDuration: Duration(milliseconds: baseMaxInterval),
      productId: productId,
      strengthXP: json['strengthXP'] as int? ?? 0,
      media: json['media'] as String? ?? '',
    );
  }

  /// The Melvor product ID (e.g., "melvorD:Raw_Shrimp").
  final MelvorId productId;

  /// Strength XP gained from catching this fish (for Barbarian fishing).
  final int strengthXP;

  /// The media path for the fish icon.
  final String media;

  /// The output item name (e.g., "Raw Shrimp").
  String get outputName => outputs.keys.first.name;

  @override
  String toString() {
    return '$name (level $unlockLevel, '
        '${minDuration.inSeconds}-${maxDuration.inSeconds}s, '
        '${xp}xp)';
  }
}
