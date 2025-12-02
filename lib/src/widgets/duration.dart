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
