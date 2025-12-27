import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// The base interval for casting alt magic spells (2 seconds).
const _altMagicCastDuration = Duration(seconds: 2);

/// An alt magic spell action parsed from Melvor data.
///
/// Alt Magic spells convert items or resources into other items/GP.
@immutable
class AltMagicAction extends SkillAction {
  const AltMagicAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required this.media,
    required this.runesRequired,
    required this.produces,
    required this.productionRatio,
    required this.specialCostType,
  }) : super(
         skill: Skill.altMagic,
         duration: _altMagicCastDuration,
         inputs: runesRequired,
       );

  factory AltMagicAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // Parse runes required
    final runesJson = json['runesRequired'] as List<dynamic>? ?? [];
    final runesRequired = <MelvorId, int>{};
    for (final rune in runesJson) {
      final runeMap = rune as Map<String, dynamic>;
      final runeId = MelvorId.fromJsonWithNamespace(
        runeMap['id'] as String,
        defaultNamespace: namespace,
      );
      runesRequired[runeId] = runeMap['quantity'] as int;
    }

    // Parse what it produces (can be an item ID, "GP", or "Bar")
    final produces = json['produces'] as String?;

    // Parse special cost type
    final specialCost = json['specialCost'] as Map<String, dynamic>?;
    final specialCostType = specialCost?['type'] as String?;

    return AltMagicAction(
      id: ActionId(Skill.altMagic.id, localId),
      name: json['name'] as String,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      media: json['media'] as String,
      runesRequired: runesRequired,
      produces: produces,
      productionRatio: (json['productionRatio'] as num?)?.toDouble() ?? 1.0,
      specialCostType: specialCostType,
    );
  }

  /// The media path for the spell icon.
  final String media;

  /// The runes required to cast this spell.
  final Map<MelvorId, int> runesRequired;

  /// What this spell produces (item ID, "GP", or "Bar").
  final String? produces;

  /// The production ratio (e.g., 0.4 for alchemy means 40% of item value).
  final double productionRatio;

  /// The type of special cost (e.g., "AnyItem", "BarIngredientsWithCoal").
  final String? specialCostType;
}
