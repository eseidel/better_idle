class MelvorId {
  const MelvorId(this.fullId);

  /// Creates a MelvorId from a JSON string.
  factory MelvorId.fromJson(String json) => MelvorId(json);

  /// Creates a MelvorId from a JSON string, adding namespace if missing.
  static MelvorId? maybeFromJson(String? json) {
    if (json == null) return null;
    return MelvorId.fromJson(json);
  }

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
  String toJson() => fullId;

  final String fullId;

  String get namespace => fullId.substring(0, fullId.indexOf(':'));
  String get localId => fullId.substring(fullId.indexOf(':') + 1);

  /// Returns a human-readable name (underscores replaced with spaces).
  String get name => localId.replaceAll('_', ' ');
}
