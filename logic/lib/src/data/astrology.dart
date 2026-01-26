import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:logic/src/types/modifier_metadata.dart';
import 'package:meta/meta.dart';

/// The base interval for studying constellations (3 seconds).
const _astrologyStudyDuration = Duration(seconds: 3);

/// Type of astrology modifier (standard uses stardust, unique uses golden).
enum AstrologyModifierType {
  standard,
  unique;

  /// The item ID for the currency used to buy this modifier type.
  MelvorId get currencyItemId => switch (this) {
    AstrologyModifierType.standard => const MelvorId('melvorF:Stardust'),
    AstrologyModifierType.unique => const MelvorId('melvorF:Golden_Stardust'),
  };
}

/// A single modifier that can be purchased multiple times on a constellation.
@immutable
class AstrologyModifier {
  const AstrologyModifier({
    required this.type,
    required this.modifierKey,
    required this.skills,
    required this.maxCount,
    required this.costs,
    required this.unlockMasteryLevel,
  });

  factory AstrologyModifier.fromJson(
    Map<String, dynamic> json,
    AstrologyModifierType type,
  ) {
    // Parse the modifier key and affected skills
    final modifiers = json['modifiers'] as Map<String, dynamic>;
    final modifierKey = modifiers.keys.first;
    final modifierValue = modifiers[modifierKey];

    // Extract skill IDs from the modifier values (if it's a list)
    // Some modifiers have simple int values instead of skill-specific lists
    final skills = <MelvorId>[];
    if (modifierValue is List) {
      for (final value in modifierValue) {
        final valueMap = value as Map<String, dynamic>;
        if (valueMap.containsKey('skillID')) {
          skills.add(MelvorId.fromJson(valueMap['skillID'] as String));
        }
      }
    }

    // Parse costs
    final costsJson = json['costs'] as List<dynamic>;
    final costs = costsJson.map((c) => c as int).toList();

    // Parse unlock requirements (mastery level)
    var unlockMasteryLevel = 1;
    final requirements = json['unlockRequirements'] as List<dynamic>?;
    if (requirements != null && requirements.isNotEmpty) {
      final req = requirements[0] as Map<String, dynamic>;
      if (req['type'] == 'MasteryLevel') {
        unlockMasteryLevel = req['level'] as int;
      }
    }

    return AstrologyModifier(
      type: type,
      modifierKey: modifierKey,
      skills: skills,
      maxCount: json['maxCount'] as int,
      costs: costs,
      unlockMasteryLevel: unlockMasteryLevel,
    );
  }

  /// Whether this is a standard or unique modifier.
  final AstrologyModifierType type;

  /// The modifier key (e.g., 'skillXP', 'masteryXP',
  /// 'skillItemDoublingChance').
  final String modifierKey;

  /// The skills this modifier affects.
  final List<MelvorId> skills;

  /// Maximum number of times this modifier can be purchased.
  final int maxCount;

  /// Cost for each purchase level (length == maxCount).
  final List<int> costs;

  /// Mastery level required to unlock this modifier.
  final int unlockMasteryLevel;

  /// Returns human-readable descriptions of this modifier using the registry.
  ///
  /// For modifiers that affect specific skills, this returns one description
  /// per skill rather than combining them.
  ///
  /// Shows the current total effect (e.g., "+3% Woodcutting Skill XP").
  List<String> formatDescriptionLines(
    ModifierMetadataRegistry registry, {
    required int currentLevel,
  }) {
    if (skills.isEmpty) {
      return [
        registry.formatDescription(name: modifierKey, value: currentLevel),
      ];
    }

    // Return one line per skill
    return skills.map((skillId) {
      final skillName = Skill.fromId(skillId).name;
      return registry.formatDescription(
        name: modifierKey,
        value: currentLevel,
        skillName: skillName,
      );
    }).toList();
  }

  /// Returns a description of the per-level increment.
  ///
  /// Example: "(+1% per level)"
  String formatIncrementDescription(ModifierMetadataRegistry registry) {
    final valueStr = registry.formatValue(name: modifierKey, value: 1);
    return '($valueStr per level)';
  }

  /// Returns the cost for the next purchase, or null if maxed out.
  int? costForLevel(int currentLevel) {
    if (currentLevel >= maxCount) return null;
    return costs[currentLevel];
  }

  /// Converts this modifier at the given level to a ModifierData.
  ///
  /// Creates one entry per skill, or a single global entry if no skills.
  ModifierData toModifierData(int level) {
    if (skills.isEmpty) {
      return ModifierData(
        name: modifierKey,
        entries: [ModifierEntry(value: level)],
      );
    }
    return ModifierData(
      name: modifierKey,
      entries: [
        for (final skillId in skills)
          ModifierEntry(
            value: level,
            scope: ModifierScope(skillId: skillId),
          ),
      ],
    );
  }
}

/// An astrology constellation action parsed from Melvor data.
///
/// Astrology actions represent constellations that can be studied to gain XP
/// and unlock modifiers that affect other skills.
@immutable
class AstrologyAction extends SkillAction {
  const AstrologyAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required this.media,
    required this.skillIds,
    required this.standardModifiers,
    required this.uniqueModifiers,
  }) : super(skill: Skill.astrology, duration: _astrologyStudyDuration);

  factory AstrologyAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // Parse the skillIDs that this constellation affects
    final skillIdsJson = json['skillIDs'] as List<dynamic>? ?? [];
    final skillIds = skillIdsJson
        .map((s) => MelvorId.fromJson(s as String))
        .toList();

    // Parse standard modifiers (use stardust)
    final standardModifiersJson =
        json['standardModifiers'] as List<dynamic>? ?? [];
    final standardModifiers = standardModifiersJson
        .map(
          (m) => AstrologyModifier.fromJson(
            m as Map<String, dynamic>,
            AstrologyModifierType.standard,
          ),
        )
        .toList();

    // Parse unique modifiers (use golden stardust)
    final uniqueModifiersJson = json['uniqueModifiers'] as List<dynamic>? ?? [];
    final uniqueModifiers = uniqueModifiersJson
        .map(
          (m) => AstrologyModifier.fromJson(
            m as Map<String, dynamic>,
            AstrologyModifierType.unique,
          ),
        )
        .toList();

    return AstrologyAction(
      id: ActionId(Skill.astrology.id, localId),
      name: json['name'] as String,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      media: json['media'] as String,
      skillIds: skillIds,
      standardModifiers: standardModifiers,
      uniqueModifiers: uniqueModifiers,
    );
  }

  /// The media path for the constellation icon.
  final String media;

  /// The skill IDs that this constellation provides modifiers for.
  final List<MelvorId> skillIds;

  /// Standard modifiers that can be purchased with stardust.
  final List<AstrologyModifier> standardModifiers;

  /// Unique modifiers that can be purchased with golden stardust.
  final List<AstrologyModifier> uniqueModifiers;
}

/// Registry for astrology skill data.
@immutable
class AstrologyRegistry {
  const AstrologyRegistry(this.actions) : _byId = null;

  const AstrologyRegistry._withCache(this.actions, this._byId);

  /// All astrology constellation actions.
  final List<AstrologyAction> actions;

  final Map<MelvorId, AstrologyAction>? _byId;

  Map<MelvorId, AstrologyAction> get _actionMap {
    if (_byId != null) return _byId;
    return {for (final a in actions) a.id.localId: a};
  }

  /// Look up an astrology action by its local ID.
  AstrologyAction? byId(MelvorId localId) => _actionMap[localId];

  /// Create a cached version for faster lookups.
  AstrologyRegistry withCache() {
    if (_byId != null) return this;
    return AstrologyRegistry._withCache(actions, _actionMap);
  }
}
