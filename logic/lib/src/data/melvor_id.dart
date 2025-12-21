extension type MelvorId._(String id) {
  MelvorId(this.id);

  /// Returns the realm prefix (e.g., "melvorD" from "melvorD:Normal_Logs").
  /// Returns empty string if no realm prefix is present.
  String get realm => id.contains(':') ? id.substring(0, id.indexOf(':')) : '';

  /// Returns the ID part after the colon (e.g., "Normal_Logs" from "melvorD:Normal_Logs").
  /// Returns the full ID if no colon is present.
  String get idName => id.contains(':') ? id.substring(id.indexOf(':') + 1) : id;

  /// Returns a human-readable name (underscores replaced with spaces).
  String get name => idName.replaceAll('_', ' ');
}
