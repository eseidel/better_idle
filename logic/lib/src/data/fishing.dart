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
    this.unlockedByItemID,
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

    final isSecret = json['isSecret'] as bool? ?? false;

    // The JSON doesn't encode what unlocks secret areas, so we map it here.
    // The Secret Area is unlocked by reading Message in a Bottle.
    final unlockedByItemIDJson =
        json['unlockedByItemID'] as String? ??
        (isSecret ? 'melvorD:Message_In_A_Bottle' : null);

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
      isSecret: isSecret,
      unlockedByItemID: unlockedByItemIDJson != null
          ? MelvorId.fromJsonWithNamespace(
              unlockedByItemIDJson,
              defaultNamespace: namespace,
            )
          : null,
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

  /// The readable item that must be read to unlock this area (for secret areas).
  final MelvorId? unlockedByItemID;
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
    required this.area,
  }) : super.ranged(skill: Skill.fishing);

  factory FishingAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
    required FishingArea area,
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
      area: area,
    );
  }

  /// The Melvor product ID (e.g., "melvorD:Raw_Shrimp").
  final MelvorId productId;

  /// Strength XP gained from catching this fish (for Barbarian fishing).
  final int strengthXP;

  /// The media path for the fish icon.
  final String media;

  /// The fishing area this action belongs to.
  final FishingArea area;
}

/// Unified registry for all fishing-related data.
@immutable
class FishingRegistry {
  FishingRegistry({
    required List<FishingAction> actions,
    required List<FishingArea> areas,
  }) : _actions = actions,
       _areas = areas {
    _byId = {for (final a in _actions) a.id.localId: a};
    _areaById = {for (final area in _areas) area.id: area};
  }

  final List<FishingAction> _actions;
  final List<FishingArea> _areas;
  late final Map<MelvorId, FishingAction> _byId;
  late final Map<MelvorId, FishingArea> _areaById;

  /// All fishing actions.
  List<FishingAction> get actions => _actions;

  /// All fishing areas.
  List<FishingArea> get areas => _areas;

  /// Look up a fishing action by its local ID.
  FishingAction? byId(MelvorId localId) => _byId[localId];

  /// Returns a fishing area by ID, or null if not found.
  FishingArea? areaById(MelvorId id) => _areaById[id];

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
