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
