// cspell:words smithed succesful
import 'package:logic/src/data/items.dart' show ConsumesOnType;
import 'package:logic/src/data/melvor_data.dart' show SkillDataEntry;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/types/conditional_modifier.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

/// A single entry in a synergy's consumesOn array.
///
/// Describes when synergy charges are consumed. The [type] determines
/// the skill/combat context, and optional fields narrow the condition
/// (e.g. specific NPCs for thieving, specific action IDs for mining).
@immutable
class ConsumesOnEntry {
  const ConsumesOnEntry({
    required this.type,
    this.actionIds = const [],
    this.npcIds = const [],
    this.categoryIds = const [],
    this.subcategoryIds = const [],
    this.activePotionIds = const [],
    this.consumedItemIds = const [],
    this.realms = const [],
    this.successful,
    this.commonDropObtained,
    this.nestGiven,
    this.smithedVersionExists,
    this.cookedVersionExists,
    this.actionGivesGems,
  });

  factory ConsumesOnEntry.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final typeStr = json['type'] as String;
    final type = ConsumesOnType.fromJson(typeStr);
    if (type == null) {
      throw FormatException('Unknown consumesOn type: $typeStr');
    }

    List<MelvorId> parseIds(String key) =>
        (json[key] as List<dynamic>?)
            ?.map(
              (id) => MelvorId.fromJsonWithNamespace(
                id as String,
                defaultNamespace: namespace,
              ),
            )
            .toList() ??
        const [];

    return ConsumesOnEntry(
      type: type,
      actionIds: parseIds('actionIDs'),
      npcIds: parseIds('npcIDs'),
      categoryIds: parseIds('categoryIDs'),
      subcategoryIds: parseIds('subcategoryIDs'),
      activePotionIds: parseIds('activePotionIDs'),
      consumedItemIds: parseIds('consumedItemIDs'),
      realms: parseIds('realms'),
      successful: json['succesful'] as bool?, // sic — Melvor typo
      commonDropObtained: json['commonDropObtained'] as bool?,
      nestGiven: json['nestGiven'] as bool?,
      smithedVersionExists: json['smithedVersionExists'] as bool?,
      cookedVersionExists: json['cookedVersionExists'] as bool?,
      actionGivesGems: json['actionGivesGems'] as bool?,
    );
  }

  final ConsumesOnType type;
  final List<MelvorId> actionIds;
  final List<MelvorId> npcIds;
  final List<MelvorId> categoryIds;
  final List<MelvorId> subcategoryIds;
  final List<MelvorId> activePotionIds;
  final List<MelvorId> consumedItemIds;
  final List<MelvorId> realms;
  final bool? successful;
  final bool? commonDropObtained;
  final bool? nestGiven;
  final bool? smithedVersionExists;
  final bool? cookedVersionExists;
  final bool? actionGivesGems;
}

/// A synergy between two summoning familiars.
///
/// Synergies provide additional modifiers when both familiars are equipped
/// in summon slots 1 and 2. The player must have mark level 3 for both
/// familiars to activate the synergy.
@immutable
class SummoningSynergy {
  const SummoningSynergy({
    required this.summonIds,
    required this.modifiers,
    this.conditionalModifiers = const [],
    this.consumesOn = const [],
  });

  factory SummoningSynergy.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final summonIdsJson = json['summonIDs'] as List<dynamic>;
    final summonIds = summonIdsJson
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final modifiersJson = json['modifiers'] as Map<String, dynamic>? ?? {};
    final modifiers = ModifierDataSet.fromJson(
      modifiersJson,
      namespace: namespace,
    );

    final conditionalModifiers =
        maybeList<ConditionalModifier>(
          json['conditionalModifiers'],
          (e) => ConditionalModifier.fromJson(e, namespace: namespace),
        ) ??
        const <ConditionalModifier>[];

    final consumesOnJson = json['consumesOn'] as List<dynamic>? ?? [];
    final consumesOn = consumesOnJson
        .map(
          (e) => ConsumesOnEntry.fromJson(
            e as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();

    return SummoningSynergy(
      summonIds: summonIds,
      modifiers: modifiers,
      conditionalModifiers: conditionalModifiers,
      consumesOn: consumesOn,
    );
  }

  /// The two summon IDs that form this synergy.
  /// These are recipe IDs (e.g., "melvorF:GolbinThief"), not product IDs.
  final List<MelvorId> summonIds;

  /// The modifiers provided when this synergy is active.
  final ModifierDataSet modifiers;

  /// Conditional modifiers that apply when their conditions are met.
  final List<ConditionalModifier> conditionalModifiers;

  /// When synergy charges are consumed. Each entry describes an action
  /// context (skill or combat) and optional narrowing conditions.
  final List<ConsumesOnEntry> consumesOn;

  /// Whether this synergy applies to the given [type].
  bool appliesTo(ConsumesOnType type) => consumesOn.any((e) => e.type == type);

  /// Returns true if the given pair of summon IDs matches this synergy.
  /// Order doesn't matter - (A, B) matches synergy [A, B] or [B, A].
  bool matches(MelvorId summon1, MelvorId summon2) {
    if (summonIds.length != 2) return false;
    return (summonIds[0] == summon1 && summonIds[1] == summon2) ||
        (summonIds[0] == summon2 && summonIds[1] == summon1);
  }
}

/// Registry for summoning synergies.
@immutable
class SummoningSynergyRegistry {
  const SummoningSynergyRegistry(List<SummoningSynergy> synergies)
    : _synergies = synergies;

  final List<SummoningSynergy> _synergies;

  /// All registered synergies.
  List<SummoningSynergy> get all => _synergies;

  /// Finds a synergy for the given pair of summon IDs.
  /// Returns null if no synergy exists for this pair.
  SummoningSynergy? findSynergy(MelvorId summon1, MelvorId summon2) {
    for (final synergy in _synergies) {
      if (synergy.matches(summon1, summon2)) {
        return synergy;
      }
    }
    return null;
  }
}

/// Parses summoning synergies from skill data entries.
SummoningSynergyRegistry parseSummoningSynergies(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) return const SummoningSynergyRegistry([]);

  final synergies = <SummoningSynergy>[];
  for (final entry in entries) {
    final synergiesJson = entry.data['synergies'] as List<dynamic>?;
    if (synergiesJson != null) {
      synergies.addAll(
        synergiesJson.map(
          (json) => SummoningSynergy.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return SummoningSynergyRegistry(synergies);
}
