import 'package:equatable/equatable.dart';
import 'package:logic/src/strings.dart';
import 'package:meta/meta.dart';

/// A single description template for a modifier value.
///
/// Each description has conditions (`above`/`below`) that determine when
/// this template should be used based on the modifier value.
@immutable
class ModifierDescription extends Equatable {
  const ModifierDescription({
    required this.text,
    required this.lang,
    this.below,
    this.above,
    this.includeSign = true,
  });

  factory ModifierDescription.fromJson(Map<String, dynamic> json) {
    return ModifierDescription(
      text: json['text'] as String,
      lang: json['lang'] as String? ?? '',
      below: json['below'] as num?,
      above: json['above'] as num?,
      includeSign: json['includeSign'] as bool? ?? true,
    );
  }

  /// The format template (e.g., "+${value}% ${skillName} Skill XP").
  final String text;

  /// Localization key (e.g., "MODIFIER_DATA_increasedSkillXP").
  final String lang;

  /// If set, this description applies when value < below.
  final num? below;

  /// If set, this description applies when value > above.
  final num? above;

  /// Whether to include the sign in the formatted output.
  /// When false, the template already contains the sign.
  final bool includeSign;

  /// Checks if this description matches the given value.
  bool matchesValue(num value) {
    if (below != null && value >= below!) return false;
    if (above != null && value <= above!) return false;
    return true;
  }

  @override
  List<Object?> get props => [text, lang, below, above, includeSign];
}

/// An alias for a modifier (e.g., "increasedGPGlobal" -> "currencyGain").
@immutable
class ModifierAlias extends Equatable {
  const ModifierAlias({required this.key, this.currencyId});

  factory ModifierAlias.fromJson(Map<String, dynamic> json) {
    return ModifierAlias(
      key: json['key'] as String,
      currencyId: json['currencyID'] as String?,
    );
  }

  /// The alias key (e.g., "increasedGPGlobal").
  final String key;

  /// Default currency ID if this alias implies a specific currency.
  final String? currencyId;

  @override
  List<Object?> get props => [key, currencyId];
}

/// A scope definition for a modifier, with descriptions for that scope.
///
/// A modifier can have multiple scope definitions, each for different
/// combinations of scope variables (skill, currency, action, etc.).
@immutable
class ModifierScopeDefinition extends Equatable {
  const ModifierScopeDefinition({
    required this.scopes,
    required this.descriptions,
    this.posAliases = const [],
    this.negAliases = const [],
  });

  factory ModifierScopeDefinition.fromJson(Map<String, dynamic> json) {
    final scopesJson = json['scopes'] as Map<String, dynamic>? ?? {};
    final scopes = <String>{};
    for (final entry in scopesJson.entries) {
      if (entry.value == true) {
        scopes.add(entry.key);
      }
    }

    final descriptionsJson = json['descriptions'] as List<dynamic>? ?? [];
    final descriptions = descriptionsJson
        .map((d) => ModifierDescription.fromJson(d as Map<String, dynamic>))
        .toList();

    final posAliasesJson = json['posAliases'] as List<dynamic>? ?? [];
    final posAliases = posAliasesJson
        .map((a) => ModifierAlias.fromJson(a as Map<String, dynamic>))
        .toList();

    final negAliasesJson = json['negAliases'] as List<dynamic>? ?? [];
    final negAliases = negAliasesJson
        .map((a) => ModifierAlias.fromJson(a as Map<String, dynamic>))
        .toList();

    return ModifierScopeDefinition(
      scopes: scopes,
      descriptions: descriptions,
      posAliases: posAliases,
      negAliases: negAliases,
    );
  }

  /// Required scope variables (e.g., {"skill"}, {"currency"}, {}).
  /// Empty set means global/no scope required.
  final Set<String> scopes;

  /// Description templates for different value conditions.
  final List<ModifierDescription> descriptions;

  /// Aliases for positive values of this modifier.
  final List<ModifierAlias> posAliases;

  /// Aliases for negative values of this modifier.
  final List<ModifierAlias> negAliases;

  /// Checks if this scope definition matches the provided scope variables.
  bool matchesScopes({
    bool hasSkill = false,
    bool hasCurrency = false,
    bool hasAction = false,
    bool hasRealm = false,
    bool hasCategory = false,
    bool hasDamageType = false,
  }) {
    // Check if all required scopes are provided
    for (final scope in scopes) {
      final hasScope = switch (scope) {
        'skill' => hasSkill,
        'currency' => hasCurrency,
        'action' => hasAction,
        'realm' => hasRealm,
        'category' => hasCategory,
        'subcategory' => hasCategory, // subcategory uses category
        'damageType' => hasDamageType,
        _ => false, // Unknown scope, don't match
      };
      if (!hasScope) return false;
    }
    return true;
  }

  /// Gets the description that matches the given value.
  ModifierDescription? descriptionForValue(num value) {
    for (final desc in descriptions) {
      if (desc.matchesValue(value)) {
        return desc;
      }
    }
    // Fallback to first description if none match
    return descriptions.isNotEmpty ? descriptions.first : null;
  }

  @override
  List<Object?> get props => [scopes, descriptions, posAliases, negAliases];
}

/// Metadata for a modifier type, defining how it should be displayed.
@immutable
class ModifierMetadata extends Equatable {
  const ModifierMetadata({
    required this.id,
    required this.allowedScopes,
    this.isCombat = false,
    this.allowEnemy = false,
    this.allowNegative = true,
  });

  factory ModifierMetadata.fromJson(Map<String, dynamic> json) {
    final allowedScopesJson = json['allowedScopes'] as List<dynamic>? ?? [];
    final allowedScopes = allowedScopesJson
        .map((s) => ModifierScopeDefinition.fromJson(s as Map<String, dynamic>))
        .toList();

    return ModifierMetadata(
      id: json['id'] as String,
      allowedScopes: allowedScopes,
      isCombat: json['isCombat'] as bool? ?? false,
      allowEnemy: json['allowEnemy'] as bool? ?? false,
      allowNegative: json['allowNegative'] as bool? ?? true,
    );
  }

  /// The modifier ID (e.g., "skillXP", "currencyGain").
  final String id;

  /// Scope definitions with descriptions for each scope combination.
  final List<ModifierScopeDefinition> allowedScopes;

  /// Whether this is a combat modifier.
  final bool isCombat;

  /// Whether this modifier can be applied to enemies.
  final bool allowEnemy;

  /// Whether negative values are allowed.
  final bool allowNegative;

  /// Gets the scope definition that matches the provided scope variables.
  ModifierScopeDefinition? scopeForContext({
    bool hasSkill = false,
    bool hasCurrency = false,
    bool hasAction = false,
    bool hasRealm = false,
    bool hasCategory = false,
    bool hasDamageType = false,
  }) {
    // Find the most specific matching scope (most required scopes)
    ModifierScopeDefinition? best;
    var bestScore = -1;

    for (final scope in allowedScopes) {
      if (scope.matchesScopes(
        hasSkill: hasSkill,
        hasCurrency: hasCurrency,
        hasAction: hasAction,
        hasRealm: hasRealm,
        hasCategory: hasCategory,
        hasDamageType: hasDamageType,
      )) {
        final score = scope.scopes.length;
        if (score > bestScore) {
          bestScore = score;
          best = scope;
        }
      }
    }

    return best;
  }

  @override
  List<Object?> get props => [
    id,
    allowedScopes,
    isCombat,
    allowEnemy,
    allowNegative,
  ];
}

/// Registry for modifier metadata, enabling display string lookups.
@immutable
class ModifierMetadataRegistry {
  ModifierMetadataRegistry(List<ModifierMetadata> modifiers)
    : _byId = {for (final m in modifiers) m.id: m},
      _byAlias = _buildAliasMap(modifiers);

  /// Empty registry for testing.
  const ModifierMetadataRegistry.empty()
    : _byId = const {},
      _byAlias = const {};

  final Map<String, ModifierMetadata> _byId;
  final Map<String, _AliasResolution> _byAlias;

  static Map<String, _AliasResolution> _buildAliasMap(
    List<ModifierMetadata> modifiers,
  ) {
    final result = <String, _AliasResolution>{};
    for (final mod in modifiers) {
      for (final scope in mod.allowedScopes) {
        for (final alias in scope.posAliases) {
          result[alias.key] = _AliasResolution(
            modifierId: mod.id,
            isNegative: false,
            currencyId: alias.currencyId,
          );
        }
        for (final alias in scope.negAliases) {
          result[alias.key] = _AliasResolution(
            modifierId: mod.id,
            isNegative: true,
            currencyId: alias.currencyId,
          );
        }
      }
    }
    return result;
  }

  /// Gets metadata by modifier ID.
  ModifierMetadata? byId(String id) => _byId[id];

  /// Resolves an alias to modifier ID and optional default currency.
  /// Returns null if the alias is not found.
  ({String modifierId, String? currencyId, bool isNegative})? resolveAlias(
    String alias,
  ) {
    final resolution = _byAlias[alias];
    if (resolution == null) return null;
    return (
      modifierId: resolution.modifierId,
      currencyId: resolution.currencyId,
      isNegative: resolution.isNegative,
    );
  }

  /// Formats a modifier for display.
  ///
  /// Looks up the format from game data first, falls back to generic
  /// formatting based on modifier name patterns if not found.
  String formatDescription({
    required String name,
    required num value,
    String? skillName,
    String? currencyName,
    String? actionName,
    String? categoryName,
    String? realmName,
    String? damageTypeName,
  }) {
    // Try direct lookup first
    var metadata = _byId[name];
    var effectiveValue = value;
    var effectiveCurrencyName = currencyName;

    // If not found, try alias resolution
    if (metadata == null) {
      final resolved = resolveAlias(name);
      if (resolved != null) {
        metadata = _byId[resolved.modifierId];
        // Aliases like "decreased*" represent negative values
        if (resolved.isNegative && value > 0) {
          effectiveValue = -value;
        }
        // Use alias's default currency if not provided
        if (effectiveCurrencyName == null && resolved.currencyId != null) {
          // Extract currency name from ID (e.g., "melvorD:GP" -> "GP")
          effectiveCurrencyName = resolved.currencyId!.split(':').last;
        }
      }
    }

    // Try to format from game data
    if (metadata != null) {
      final scopeDef = metadata.scopeForContext(
        hasSkill: skillName != null,
        hasCurrency: effectiveCurrencyName != null,
        hasAction: actionName != null,
        hasCategory: categoryName != null,
        hasRealm: realmName != null,
        hasDamageType: damageTypeName != null,
      );

      if (scopeDef != null) {
        final description = scopeDef.descriptionForValue(effectiveValue);
        if (description != null) {
          var result = description.text;

          // Replace placeholders (JSON uses ${placeholder} format)
          final absValue = effectiveValue.abs();
          result = result.replaceAll(r'${value}', absValue.toString());

          if (skillName != null) {
            result = result.replaceAll(r'${skillName}', skillName);
          }
          if (effectiveCurrencyName != null) {
            result = result.replaceAll(
              r'${currencyName}',
              effectiveCurrencyName,
            );
          }
          if (actionName != null) {
            result = result.replaceAll(r'${actionName}', actionName);
          }
          if (categoryName != null) {
            result = result.replaceAll(r'${categoryName}', categoryName);
            result = result.replaceAll(r'${subcategoryName}', categoryName);
          }
          if (realmName != null) {
            result = result.replaceAll(r'${realmName}', realmName);
          }
          if (damageTypeName != null) {
            result = result.replaceAll(r'${damageType}', damageTypeName);
          }

          return result;
        }
      }
    }

    // Fallback: generic formatting based on modifier name patterns
    return _formatFallback(
      name: name,
      value: effectiveValue,
      skillName: skillName,
      currencyName: effectiveCurrencyName,
    );
  }

  /// Generic fallback formatting based on modifier name patterns.
  String _formatFallback({
    required String name,
    required num value,
    String? skillName,
    String? currencyName,
  }) {
    final sign = value >= 0 ? '+' : '';
    final absValue = value.abs();
    final formattedName = formatModifierName(name);

    // Add context if available
    var context = '';
    if (skillName != null) {
      context = ' ($skillName)';
    } else if (currencyName != null) {
      context = ' ($currencyName)';
    }

    // Determine appropriate format based on modifier name patterns
    if (name.contains('Interval') || name.contains('interval')) {
      return '$sign${absValue}ms $formattedName$context';
    }
    if (name.startsWith('flat')) {
      return '$sign$absValue $formattedName$context';
    }
    // Most modifiers are percentages
    return '$sign$absValue% $formattedName$context';
  }
}

/// Internal class for alias resolution.
class _AliasResolution {
  const _AliasResolution({
    required this.modifierId,
    required this.isNegative,
    this.currencyId,
  });

  final String modifierId;
  final String? currencyId;
  final bool isNegative;
}
