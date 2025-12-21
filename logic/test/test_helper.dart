import 'package:logic/logic.dart';

/// Flag to ensure items are only initialized once.
bool _itemsInitialized = false;

/// Ensures the itemRegistry is initialized for tests.
///
/// This should be called in setUpAll() for any test file that uses itemRegistry.
/// It's safe to call multiple times; subsequent calls are no-ops.
Future<void> ensureItemsInitialized() async {
  if (_itemsInitialized) return;
  _itemsInitialized = true;

  final melvorData = await MelvorData.load();
  initializeItems(melvorData);
}
