/// Converts a JSON list to a typed list, or returns null if the input is null.
///
/// Example:
/// ```dart
/// final consumesOn = maybeList<ConsumesOn>(
///   json['consumesOn'],
///   (e) => ConsumesOn.fromJson(e),
/// );
/// ```
List<T>? maybeList<T>(dynamic json, T Function(Map<String, dynamic>) fromJson) {
  if (json == null) return null;
  return (json as List<dynamic>)
      .map((e) => fromJson(e as Map<String, dynamic>))
      .toList();
}

Map<K, V>? maybeMap<K, V>(
  dynamic json, { // Assumes Map<String, dynamic> for simplicity.
  K Function(String)? toKey,
  V Function(dynamic)? toValue,
}) {
  if (json == null) return null;
  final keyFromJson = toKey ?? (String key) => key as K;
  final valueFromJson = toValue ?? (dynamic value) => value as V;
  return (json as Map<String, dynamic>?)?.map(
    (key, value) => MapEntry(keyFromJson(key), valueFromJson(value)),
  );
}
