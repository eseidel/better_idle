import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/shop.dart';
import 'package:meta/meta.dart';

/// An item upgrade recipe.
@immutable
class ItemUpgrade {
  const ItemUpgrade({
    required this.upgradedItemId,
    required this.itemCosts,
    required this.currencyCosts,
    required this.rootItemIds,
    required this.isDowngrade,
  });

  /// Parses an ItemUpgrade from JSON.
  factory ItemUpgrade.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final upgradedItemId = MelvorId.fromJsonWithNamespace(
      json['upgradedItemID'] as String,
      defaultNamespace: namespace,
    );
    final itemCostsJson = json['itemCosts'] as List<dynamic>? ?? [];
    final itemCosts = itemCostsJson
        .map(
          (e) => ItemCost.fromJson(
            e as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();
    final currencyCostsJson = json['currencyCosts'] as List<dynamic>?;
    final currencyCosts = CurrencyCosts.fromJson(currencyCostsJson);
    final rootItemIdsJson = json['rootItemIDs'] as List<dynamic>? ?? [];
    final rootItemIds = rootItemIdsJson
        .map(
          (e) => MelvorId.fromJsonWithNamespace(
            e as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();
    final isDowngrade = json['isDowngrade'] as bool? ?? false;

    return ItemUpgrade(
      upgradedItemId: upgradedItemId,
      itemCosts: itemCosts,
      currencyCosts: currencyCosts,
      rootItemIds: rootItemIds,
      isDowngrade: isDowngrade,
    );
  }

  /// Creates a potion upgrade (3x lower tier → 1x higher tier).
  factory ItemUpgrade.potionUpgrade({
    required MelvorId lowerTierItemId,
    required MelvorId higherTierItemId,
  }) {
    return ItemUpgrade(
      upgradedItemId: higherTierItemId,
      itemCosts: [ItemCost(itemId: lowerTierItemId, quantity: 3)],
      currencyCosts: CurrencyCosts.empty,
      rootItemIds: [lowerTierItemId],
      isDowngrade: false,
    );
  }

  /// The item produced by this upgrade.
  final MelvorId upgradedItemId;

  /// Items consumed by this upgrade.
  final List<ItemCost> itemCosts;

  /// Currency costs for this upgrade.
  final CurrencyCosts currencyCosts;

  /// The root items in this upgrade chain.
  final List<MelvorId> rootItemIds;

  /// Whether this is a downgrade operation.
  final bool isDowngrade;
}

/// Registry of all item upgrades.
@immutable
class ItemUpgradeRegistry {
  const ItemUpgradeRegistry(this._upgrades);

  /// Creates an empty registry for tests.
  static const empty = ItemUpgradeRegistry([]);

  final List<ItemUpgrade> _upgrades;

  /// All upgrades in the registry.
  List<ItemUpgrade> get all => _upgrades;

  /// Gets all upgrades that use a given item as input.
  List<ItemUpgrade> upgradesForItem(MelvorId itemId) {
    return _upgrades
        .where((u) => u.itemCosts.any((c) => c.itemId == itemId))
        .toList();
  }
}

/// Parses item upgrades from data files.
ItemUpgradeRegistry parseItemUpgrades(
  List<Map<String, dynamic>> dataFiles,
  ItemRegistry items,
) {
  final upgrades = <ItemUpgrade>[];

  // Parse explicit upgrades from JSON
  for (final json in dataFiles) {
    final namespace = json['namespace'] as String;
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) continue;

    final upgradesJson = data['itemUpgrades'] as List<dynamic>? ?? [];
    for (final upgradeJson in upgradesJson) {
      upgrades.add(
        ItemUpgrade.fromJson(
          upgradeJson as Map<String, dynamic>,
          namespace: namespace,
        ),
      );
    }
  }

  // Generate potion upgrades from item tiers
  upgrades.addAll(_generatePotionUpgrades(items));

  return ItemUpgradeRegistry(upgrades);
}

/// Generates potion upgrade recipes from item tier data.
///
/// Potions follow a 3x lower tier → 1x higher tier upgrade pattern.
List<ItemUpgrade> _generatePotionUpgrades(ItemRegistry items) {
  final upgrades = <ItemUpgrade>[];

  // Group potions by base name (without tier suffix)
  final potionsByBase = <String, List<Item>>{};
  for (final item in items.all) {
    if (item.type != 'Potion') continue;
    final tier = item.potionTier;
    if (tier == null) continue;

    // Extract base name by removing tier suffix
    final baseName = _getPotionBaseName(item.id);
    potionsByBase.putIfAbsent(baseName, () => []).add(item);
  }

  // Create upgrades for each tier transition
  for (final potions in potionsByBase.values) {
    // Sort by tier
    potions.sort((a, b) => (a.potionTier ?? 0).compareTo(b.potionTier ?? 0));

    // Create upgrade from each tier to the next
    for (var i = 0; i < potions.length - 1; i++) {
      final lower = potions[i];
      final higher = potions[i + 1];
      upgrades.add(
        ItemUpgrade.potionUpgrade(
          lowerTierItemId: lower.id,
          higherTierItemId: higher.id,
        ),
      );
    }
  }

  return upgrades;
}

/// Extracts the base name from a potion ID (without tier suffix).
String _getPotionBaseName(MelvorId id) {
  final localId = id.localId;
  // Remove tier suffixes: _I, _II, _III, _IV
  if (localId.endsWith('_IV')) return localId.substring(0, localId.length - 3);
  if (localId.endsWith('_III')) return localId.substring(0, localId.length - 4);
  if (localId.endsWith('_II')) return localId.substring(0, localId.length - 3);
  if (localId.endsWith('_I')) return localId.substring(0, localId.length - 2);
  return localId;
}
