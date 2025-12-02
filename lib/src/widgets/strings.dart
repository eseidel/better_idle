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

/// Create an approximate string for the given [duration].
String approximateDuration(Duration duration) {
  final d = duration; // Save some typing.
  // We only support up to 24 hours of changes, so we can ignore days, etc.
  if (d.inHours.abs() > 0) {
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
