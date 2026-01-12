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
