import 'package:logic/src/data/melvor_data.dart' show SkillDataEntry;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/types/conditional_modifier.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

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

    return SummoningSynergy(
      summonIds: summonIds,
      modifiers: modifiers,
      conditionalModifiers: conditionalModifiers,
    );
  }

  /// The two summon IDs that form this synergy.
  /// These are recipe IDs (e.g., "melvorF:GolbinThief"), not product IDs.
  final List<MelvorId> summonIds;

  /// The modifiers provided when this synergy is active.
  final ModifierDataSet modifiers;

  /// Conditional modifiers that apply when their conditions are met.
  final List<ConditionalModifier> conditionalModifiers;

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
