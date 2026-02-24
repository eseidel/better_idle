import 'package:meta/meta.dart';

/// The result of upgrading all potions in inventory.
@immutable
class PotionUpgradeResult {
  const PotionUpgradeResult({required this.totalUpgradesMade});

  /// How many individual upgrade operations were performed.
  final int totalUpgradesMade;

  /// Whether any upgrades were made.
  bool get hasUpgrades => totalUpgradesMade > 0;
}
