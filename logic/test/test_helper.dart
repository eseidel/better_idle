import 'package:logic/logic.dart';

/// Standard registries for tests. Must call [loadTestRegistries] first.
late Registries testRegistries;

/// Loads the test registries. Call this in setUpAll().
Future<void> loadTestRegistries() async {
  testRegistries = await loadRegistries();
}

/// Shorthand accessors for test registries.
ItemRegistry get testItems => testRegistries.items;
ActionRegistry get testActions => testRegistries.actions;
DropsRegistry get testDrops => testRegistries.drops;
