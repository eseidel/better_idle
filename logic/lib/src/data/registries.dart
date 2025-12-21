import 'dart:io';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_data.dart';

class Registries {
  Registries(this.items, this.actions, this.drops);

  final ItemRegistry items;
  final ActionRegistry actions;
  final DropsRegistry drops;
}

Registries? _registries;

/// Ensures the registries are initialized.
///
/// This should be called during app startup or in setUpAll() for tests.
/// It's safe to call multiple times; subsequent calls are no-ops.
Future<Registries> loadRegistries({Directory? cacheDir}) async {
  if (_registries != null) return _registries!;
  final melvorData = await MelvorData.load(cacheDir: cacheDir);
  _registries = Registries(
    initializeItems(melvorData),
    ActionRegistry(loadActions(melvorData)),
    DropsRegistry(skillDrops, globalDrops),
  );
  return _registries!;
}

// /// Returns the loaded registries. Throws if not yet loaded.
// Registries get registries {
//   if (_registries == null) {
//     throw StateError('Registries not loaded. Call loadRegistries() first.');
//   }
//   return _registries!;
// }

ItemRegistry initializeItems(MelvorData data) {
  final items = <Item>[];
  for (final name in data.itemNames) {
    final json = data.lookupItem(name);
    if (json != null) {
      items.add(Item.fromJson(json));
    }
  }
  return ItemRegistry(items);
}
