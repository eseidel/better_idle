extension type MelvorId._(String id) {
  MelvorId(this.id);

  /// Creates a MelvorId from a JSON string.
  factory MelvorId.fromJson(String json) => MelvorId(json);

  /// Creates a MelvorId from a JSON string, adding namespace if missing.
  /// If the ID already contains a namespace (has ':'), it is used as-is.
  /// Otherwise, the provided [defaultNamespace] is prepended.
  factory MelvorId.fromJsonWithNamespace(
    String json, {
    required String defaultNamespace,
  }) {
    if (json.contains(':')) {
      return MelvorId(json);
    }
    return MelvorId('$defaultNamespace:$json');
  }

  /// Creates a MelvorId from a human-readable name.
  /// Converts "Normal Logs" to "melvorD:Normal_Logs".
  factory MelvorId.fromName(String name) =>
      MelvorId('melvorD:${name.replaceAll(' ', '_')}');

  /// Returns the underlying string for JSON serialization.
  String toJson() => id;

  /// Returns the realm prefix (e.g., "melvorD" from "melvorD:Normal_Logs").
  /// Returns empty string if no realm prefix is present.
  String get realm => id.substring(0, id.indexOf(':'));

  /// Returns the ID part after the colon (e.g., "Normal_Logs" from "melvorD:Normal_Logs").
  /// Returns the full ID if no colon is present.
  String get idName => id.substring(id.indexOf(':') + 1);

  /// Returns a human-readable name (underscores replaced with spaces).
  String get name => idName.replaceAll('_', ' ');
}
