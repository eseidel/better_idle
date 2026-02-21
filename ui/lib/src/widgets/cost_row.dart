import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A widget that displays a row of costs (currencies and items) with
/// color-coding based on whether each cost can be afforded.
class CostRow extends StatelessWidget {
  const CostRow({
    super.key,
    this.currencyCosts = const [],
    this.canAffordCosts = const {},
    this.itemCosts = const [],
    this.emptyText = 'Free',
    this.showAffordability = true,
    this.spacing = 12,
    this.iconSize = 16,
  });

  /// Creates a [CostRow] from a [ResolvedShopCost].
  CostRow.fromResolved(
    ResolvedShopCost resolved, {
    super.key,
    this.emptyText = 'Free',
    this.showAffordability = true,
    this.spacing = 12,
    this.iconSize = 16,
  }) : currencyCosts = resolved.currencyCosts,
       canAffordCosts = resolved.canAffordCurrencyMap,
       itemCosts = resolved.itemCosts;

  /// List of (currency, amount) pairs.
  final List<(Currency, int)> currencyCosts;

  /// Map of currency to whether the player can afford that cost.
  /// Only used when [showAffordability] is true.
  final Map<Currency, bool> canAffordCosts;

  /// List of (item, quantity, canAfford) tuples.
  final List<(Item, int, bool)> itemCosts;

  /// Text to display when there are no costs.
  final String emptyText;

  /// Whether to color-code costs based on affordability.
  final bool showAffordability;

  /// Spacing between cost items.
  final double spacing;

  /// Size of the currency/item icons.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (currencyCosts.isEmpty && itemCosts.isEmpty) {
      return Text(
        emptyText,
        style: const TextStyle(
          color: Style.successColor,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final widgets = <Widget>[];

    // Add currency costs
    for (final (currency, amount) in currencyCosts) {
      final canAfford = canAffordCosts[currency] ?? true;
      final color = showAffordability
          ? (canAfford ? Style.successColor : Style.unmetRequirementColor)
          : null;
      widgets.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedImage(assetPath: currency.assetPath, size: iconSize),
            const SizedBox(width: 4),
            Text(
              approximateCreditString(amount),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    // Add item costs
    for (final (item, quantity, canAfford) in itemCosts) {
      final color = showAffordability
          ? (canAfford ? Style.successColor : Style.unmetRequirementColor)
          : null;
      widgets.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.media != null)
              CachedImage(assetPath: item.media, size: iconSize)
            else
              Icon(Icons.inventory_2, size: iconSize, color: color),
            const SizedBox(width: 4),
            Text(
              '$quantity',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }
}
