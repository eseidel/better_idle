import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A fishing area parsed from Melvor data.
@immutable
class FishingArea {
  const FishingArea({
    required this.id,
    required this.name,
    required this.fishChance,
    required this.junkChance,
    required this.specialChance,
    required this.fishIDs,
    this.requiredItemID,
    this.isSecret = false,
  });

  factory FishingArea.fromJson(
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

    return FishingArea(
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
}

/// A fishing action parsed from Melvor data.
@immutable
class FishingAction extends SkillAction {
  const FishingAction({
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

  factory FishingAction.fromJson(
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

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return FishingAction(
      id: ActionId(Skill.fishing.id, localId),
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
}

/// Registry for fishing areas.
@immutable
class FishingAreaRegistry {
  FishingAreaRegistry(List<FishingArea> areas) : _areas = areas {
    _byId = {for (final area in _areas) area.id: area};
  }

  final List<FishingArea> _areas;
  late final Map<MelvorId, FishingArea> _byId;

  /// Returns all fishing areas.
  List<FishingArea> get all => _areas;

  /// Returns a fishing area by ID, or null if not found.
  FishingArea? byId(MelvorId id) => _byId[id];

  /// Returns fishing area containing the given fish ID, or null if not found.
  FishingArea? areaForFish(MelvorId fishId) {
    for (final area in _areas) {
      if (area.fishIDs.contains(fishId)) {
        return area;
      }
    }
    return null;
  }
}
