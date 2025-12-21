extension type MelvorId._(String id) {
  MelvorId(this.id) : assert(id.contains(':'), 'Invalid Melvor ID: $id');

  String get realm => id.substring(0, id.indexOf(':'));
  String get idName => id.substring(id.indexOf(':') + 1);
  String get name => idName.replaceAll('_', ' ');
}
