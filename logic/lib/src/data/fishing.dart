import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/drop.dart';
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
    this.junkDropTable,
    this.specialDropTable,
  });

  factory FishingArea.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
    required DropTable? junkDropTable,
    required DropTable? specialDropTable,
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
      junkDropTable: junkDropTable,
      specialDropTable: specialDropTable,
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

  /// Drop table for junk items (equal weight for all junk items).
  final DropTable? junkDropTable;

  /// Drop table for special items (gems, treasure, etc).
  final DropTable? specialDropTable;
}

/// Returns the drops for a fishing action, including area-based junk/special.
///
/// When fishing completes, the player rolls:
/// 1. Fish (normal output) - at area.fishChance rate
/// 2. Junk item - at area.junkChance rate
/// 3. Special item - at area.specialChance rate
///
/// The fish/junk/special chances are mutually exclusive in Melvor (they sum
/// to 100%), so we model this by always giving the fish output and adding
/// junk/special as separate drop chances that replace the fish when rolled.
List<Droppable> _fishingRewards(SkillAction action, RecipeSelection selection) {
  final fishingAction = action as FishingAction;
  final area = fishingAction.area;

  // Start with the default fish output.
  final rewards = <Droppable>[...defaultRewards(action, selection)];

  // Add junk drop table with area's junk chance.
  // Junk replaces fish when rolled, but we model this as additional drops
  // since the chances are already balanced (fish + junk + special = 100%).
  if (area.junkDropTable != null && area.junkChance > 0) {
    rewards.add(DropChance(area.junkDropTable!, rate: area.junkChance));
  }

  // Add special drop table with area's special chance.
  if (area.specialDropTable != null && area.specialChance > 0) {
    rewards.add(DropChance(area.specialDropTable!, rate: area.specialChance));
  }

  return rewards;
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
  }) : super.ranged(skill: Skill.fishing, rewardsAtLevel: _fishingRewards);

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
