import 'package:intl/intl.dart';

String _rounded(int whole, int part, int units, String unitName) {
  var absWhole = whole.abs();
  final partial = part / units;
  final sign = whole.sign;
  if (partial >= 0.5) {
    absWhole += 1;
  }
  // zero uses pluralization in english
  final plural = absWhole == 1 ? '' : 's';
  return '${sign * absWhole} $unitName$plural';
}

/// Create an approximate string for the given tick count.
///
/// This is a convenience wrapper around [approximateDuration] that converts
/// ticks to a Duration first. One tick = 100ms.
String approximateDurationFromTicks(int ticks) {
  // 1 tick = 100ms, so ticks * 100 = milliseconds
  return approximateDuration(Duration(milliseconds: ticks * 100));
}

/// Formats a tick count as duration with ticks in parentheses.
///
/// Example: "29 days (24,933,018 ticks)"
String durationStringWithTicks(int ticks) {
  final duration = approximateDurationFromTicks(ticks);
  final tickStr = preciseNumberString(ticks);
  return '$duration ($tickStr ticks)';
}

/// Formats a signed tick delta as duration with ticks in parentheses.
///
/// Example: "+11 minutes (+6,601 ticks)" or "-11 minutes (-6,601 ticks)"
String signedDurationStringWithTicks(int ticks) {
  final duration = approximateDurationFromTicks(ticks.abs());
  final sign = ticks >= 0 ? '+' : '-';
  final tickStr = preciseNumberString(ticks.abs());
  return '$sign$duration ($sign$tickStr ticks)';
}

/// Create an approximate string for the given [duration].
/// Rounds to the nearest unit and shows a single unit (e.g., "2 days").
String approximateDuration(Duration duration) {
  final d = duration; // Save some typing.
  if (d.inDays.abs() > 0) {
    final absDays = d.inDays.abs();
    final absHours = d.inHours.abs() - (absDays * 24);
    return _rounded(d.inDays, absHours, 24, 'day');
  } else if (d.inHours.abs() > 0) {
    final absHours = d.inHours.abs();
    final absMinutes = d.inMinutes.abs() - (absHours * 60);
    return _rounded(d.inHours, absMinutes, 60, 'hour');
  } else if (d.inMinutes.abs() > 0) {
    final absMinutes = d.inMinutes.abs();
    final absSeconds = d.inSeconds.abs() - (absMinutes * 60);
    return _rounded(d.inMinutes, absSeconds, 60, 'minute');
  } else {
    final absSeconds = d.inSeconds.abs();
    final absMilliseconds = d.inMilliseconds.abs() - (absSeconds * 1000);
    return _rounded(d.inSeconds, absMilliseconds, 1000, 'second');
  }
}

/// Formats a duration as a compact string showing two units of precision.
/// Examples: "3d 12h", "5h 30m", "45m", "30s"
String compactDuration(Duration duration) {
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;

  if (days > 0) {
    return hours > 0 ? '${days}d ${hours}h' : '${days}d';
  } else if (hours > 0) {
    return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
  } else if (minutes > 0) {
    return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  } else {
    return '${seconds}s';
  }
}

/// Formats a tick count as a compact duration string.
/// Examples: "3d 12h", "5h 30m", "45m"
String compactDurationFromTicks(int ticks) {
  return compactDuration(Duration(milliseconds: ticks * 100));
}

/// The correct string for a credit value.  Does not include the "GP" suffix.
String approximateCreditString(int value) {
  // For now these are identical, but they may diverge in the future.
  return approximateCountString(value);
}

/// The correct string for a count value.
String approximateCountString(int value) {
  final formatter = NumberFormat('#,###');
  if (value >= 1000000) {
    final millions = value ~/ 1000000;
    return '${formatter.format(millions)}M';
  } else if (value >= 10000) {
    final thousands = value ~/ 1000;
    return '${formatter.format(thousands)}K';
  }
  return formatter.format(value);
}

/// The correct string for a precise number value.
String preciseNumberString(int value) => NumberFormat('#,##0').format(value);

String signedCountString(int value) {
  if (value == 0) {
    return '0';
  }
  if (value > 0) {
    return '+${approximateCountString(value)}';
  }
  // Negative values already have a minus sign.
  return approximateCountString(value);
}

/// Formats a decimal value (0.0-1.0) as a percentage string.
/// Example: 0.5 → "50%"
String percentToString(double value) {
  return '${(value * 100).toStringAsFixed(0)}%';
}

/// Formats a percentage value (0-100) as a percentage string.
/// Example: 80.0 → "80%"
String percentValueToString(num value) {
  return '${value.toStringAsFixed(0)}%';
}

String signedPercentToString(double value) {
  if (value > 0) {
    return '+${percentToString(value)}';
  }
  return percentToString(value);
}

/// Formats a modifier name from camelCase to readable format.
///
/// Examples:
/// - "skillXP" → "Skill XP"
/// - "currencyGain" → "Currency Gain"
/// - "masteryXP" → "Mastery XP"
String formatModifierName(String name) {
  final result = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final char = name[i];
    // Add space before uppercase letters (but not at the start)
    if (i > 0 && char.toUpperCase() == char && char.toLowerCase() != char) {
      result.write(' ');
    }
    result.write(i == 0 ? char.toUpperCase() : char);
  }
  return result.toString();
}

/// Known modifier display patterns.
///
/// Maps modifier names to their display format.
/// The format string can contain:
/// - {value} - the modifier value
/// - {skill} - the skill name (from scope)
/// - {currency} - the currency name (from scope)
/// - {action} - the action name (from scope)
const _modifierFormats = <String, String>{
  // Currency modifiers
  'currencyGain': '{sign}{value}% Global {currency} (except Item Sales)',
  'currencyGainFromCombat': '{sign}{value}% {currency} from Combat',
  'currencyGainFromMonsterDrops':
      '{sign}{value}% {currency} from Monster Drops',
  'currencyGainFromLogSales': '{sign}{value}% {currency} from Log Sales',
  'flatCurrencyGainFromMonsterDrops':
      '{sign}{value} Flat {currency} from Drops',

  // XP modifiers
  'skillXP': '{sign}{value}% {skill} Skill XP',
  'masteryXP': '{sign}{value}% {skill} Mastery XP',
  'nonCombatSkillXP': '{sign}{value}% Non-Combat Skill XP',

  // Interval modifiers
  'skillInterval': '{sign}{value}% {skill} Interval',

  // Preservation/cost modifiers
  'skillPreservationChance': '{sign}{value}% {skill} Preservation',

  // Doubling modifiers
  'skillItemDoublingChance': '{sign}{value}% {skill} Item Doubling',
  'doubleItemsSkill': '{sign}{value}% Chance to Double {skill} Items',
  'globalItemDoublingChance': '{sign}{value}% Global Item Doubling',

  // Combat modifiers
  'maxHitpoints': '{sign}{value}% Maximum Hitpoints',
  'flatMaxHitpoints': '{sign}{value} Maximum Hitpoints',
  'damageDealt': '{sign}{value}% Damage Dealt',
  'damageTaken': '{sign}{value}% Damage Taken',
  'attackInterval': '{sign}{value}% Attack Interval',
  'flatAttackInterval': '{sign}{value}ms Attack Interval',
  'lifesteal': '{sign}{value}% Lifesteal',
  'meleeAccuracyRating': '{sign}{value}% Melee Accuracy',
  'rangedAccuracyRating': '{sign}{value}% Ranged Accuracy',
  'magicAccuracyRating': '{sign}{value}% Magic Accuracy',
  'meleeEvasion': '{sign}{value}% Melee Evasion',
  'rangedEvasion': '{sign}{value}% Ranged Evasion',
  'magicEvasion': '{sign}{value}% Magic Evasion',
  'evasion': '{sign}{value}% Evasion',
  'resistance': '{sign}{value}% Resistance',
  'flatResistance': '{sign}{value} Resistance',
  'hitpointRegeneration': '{sign}{value}% HP Regeneration',

  // Other common modifiers
  'bankSpace': '{sign}{value} Bank Slots',
};

/// Formats a modifier entry for display.
///
/// Takes the modifier name, value, and optional scope information to produce
/// a human-readable description like "+3% Global GP (except Item Sales)".
///
/// [name] - The modifier key (e.g., "currencyGain")
/// [value] - The numeric value
/// [skillName] - Optional skill name from scope
/// [currencyName] - Optional currency name from scope
/// [actionName] - Optional action name from scope
String formatModifierDescription({
  required String name,
  required num value,
  String? skillName,
  String? currencyName,
  String? actionName,
}) {
  final sign = value >= 0 ? '+' : '';
  final absValue = value.abs();

  // Check for known format pattern
  final format = _modifierFormats[name];
  if (format != null) {
    var result = format
        .replaceAll('{sign}', sign)
        .replaceAll('{value}', absValue.toString());

    // Replace optional scope placeholders
    if (skillName != null) {
      result = result.replaceAll('{skill}', skillName);
    } else {
      // Remove {skill} placeholder if no skill name provided
      result = result.replaceAll('{skill} ', '').replaceAll(' {skill}', '');
    }

    if (currencyName != null) {
      result = result.replaceAll('{currency}', currencyName);
    } else {
      // Default to "GP" if no currency specified
      result = result.replaceAll('{currency}', 'GP');
    }

    if (actionName != null) {
      result = result.replaceAll('{action}', actionName);
    } else {
      result = result.replaceAll('{action} ', '').replaceAll(' {action}', '');
    }

    return result;
  }

  // Fallback: use formatted modifier name
  final formattedName = formatModifierName(name);

  // Add context if available
  var context = '';
  if (skillName != null) {
    context = ' ($skillName)';
  } else if (currencyName != null) {
    context = ' ($currencyName)';
  }

  // Determine appropriate prefix based on modifier name patterns
  if (name.contains('Interval') || name.contains('interval')) {
    return '$sign${absValue}ms $formattedName$context';
  }
  if (name.startsWith('flat')) {
    return '$sign$absValue $formattedName$context';
  }
  // Most modifiers are percentages
  return '$sign$absValue% $formattedName$context';
}
