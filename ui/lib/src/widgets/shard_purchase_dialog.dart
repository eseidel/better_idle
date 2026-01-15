import 'dart:math' as math;

import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/cost_row.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logic/logic.dart';

/// A dialog that shows available shop purchases for a specific item.
///
/// Used on the summoning page to allow purchasing shards directly
/// without navigating to the shop.
class ShardPurchaseDialog extends StatelessWidget {
  const ShardPurchaseDialog({required this.item, super.key});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final purchases = state.registries.shop.purchasesContainingItem(item.id);

    // Filter to visible purchases only
    final visiblePurchases = purchases.where((p) {
      // Check buy limit
      final owned = state.shop.purchaseCount(p.id);
      if (!p.isUnlimited && owned >= p.buyLimit) return false;

      // Check unlock requirements
      for (final req in p.unlockRequirements) {
        if (req is ShopPurchaseRequirement) {
          if (state.shop.purchaseCount(req.purchaseId) < req.count) {
            return false;
          }
        }
      }
      return true;
    }).toList();

    return AlertDialog(
      title: Row(
        children: [
          ItemImage(item: item, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('Buy ${item.name}')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: visiblePurchases.isEmpty
            ? const Text(
                'No purchases available for this item.',
                style: TextStyle(color: Style.textColorSecondary),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: visiblePurchases
                      .map((p) => _PurchaseOption(purchase: p, item: item))
                      .toList(),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PurchaseOption extends StatelessWidget {
  const _PurchaseOption({required this.purchase, required this.item});

  final ShopPurchase purchase;
  final Item item;

  /// Calculate how many times the player can afford this purchase.
  int _calculateMaxAffordable(GlobalState state) {
    final currencyCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: state.shop.bankSlotsPurchased,
    );
    final itemCosts = purchase.cost.items;

    var maxAffordable = 99999; // Reasonable upper limit

    // Check currency limits
    for (final (currency, amount) in currencyCosts) {
      if (amount > 0) {
        final balance = state.currency(currency);
        final canAfford = balance ~/ amount;
        maxAffordable = math.min(maxAffordable, canAfford);
      }
    }

    // Check item cost limits
    for (final cost in itemCosts) {
      if (cost.quantity > 0) {
        final costItem = state.registries.items.byId(cost.itemId);
        final owned = state.inventory.countOfItem(costItem);
        final canAfford = owned ~/ cost.quantity;
        maxAffordable = math.min(maxAffordable, canAfford);
      }
    }

    return math.max(0, maxAffordable);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    // Get the quantity of our target item from this purchase
    final itemQuantity = purchase.contains.items
        .where((cost) => cost.itemId == item.id)
        .fold(0, (sum, cost) => sum + cost.quantity);

    // Get base currency costs (for 1 purchase)
    final baseCurrencyCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: state.shop.bankSlotsPurchased,
    );

    // Check purchase requirements (skill levels, etc.)
    final unmetRequirements = <ShopRequirement>[];
    for (final req in [
      ...purchase.unlockRequirements,
      ...purchase.purchaseRequirements,
    ]) {
      if (!req.isMet(state)) {
        unmetRequirements.add(req);
      }
    }

    final maxAffordable = _calculateMaxAffordable(state);
    final meetsRequirements = unmetRequirements.isEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with item info
            Row(
              children: [
                if (purchase.media != null)
                  CachedImage(assetPath: purchase.media)
                else
                  ItemImage(item: item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        purchase.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '+$itemQuantity ${item.name} each',
                        style: const TextStyle(
                          color: Style.successColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Base cost display
            Row(
              children: [
                const Text('Cost: ', style: TextStyle(fontSize: 12)),
                CostRow(
                  currencyCosts: baseCurrencyCosts,
                  itemCosts: purchase.cost.items.map((cost) {
                    final costItem = state.registries.items.byId(cost.itemId);
                    return (costItem, cost.quantity, true);
                  }).toList(),
                  showAffordability: false,
                  iconSize: 14,
                  spacing: 8,
                ),
              ],
            ),

            if (unmetRequirements.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildRequirementsRow(unmetRequirements),
            ],

            const SizedBox(height: 12),

            // Quantity buttons
            if (meetsRequirements && maxAffordable > 0)
              _QuantityButtons(
                purchase: purchase,
                item: item,
                maxAffordable: maxAffordable,
                itemQuantityPerPurchase: itemQuantity,
              )
            else
              Text(
                maxAffordable == 0 ? 'Cannot afford' : 'Requirements not met',
                style: const TextStyle(
                  color: Style.textColorSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementsRow(List<ShopRequirement> requirements) {
    final color = Style.unmetRequirementColor;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: requirements.map((req) {
        if (req is SkillLevelRequirement) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CachedImage(assetPath: req.skill.assetPath, size: 14),
              const SizedBox(width: 4),
              Text(
                'Lv ${req.level}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}

class _QuantityButtons extends StatelessWidget {
  const _QuantityButtons({
    required this.purchase,
    required this.item,
    required this.maxAffordable,
    required this.itemQuantityPerPurchase,
  });

  final ShopPurchase purchase;
  final Item item;
  final int maxAffordable;
  final int itemQuantityPerPurchase;

  static const _presets = [1, 10, 100, 1000, 10000];

  @override
  Widget build(BuildContext context) {
    // Filter presets to only show affordable ones
    final availablePresets = _presets.where((q) => q <= maxAffordable).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Preset buttons
        for (final qty in availablePresets)
          _QuantityButton(
            label: _formatQuantity(qty),
            onPressed: () => _showConfirmDialog(context, qty),
          ),
        // Max button (if max is different from largest shown preset)
        if (maxAffordable > 0 &&
            (availablePresets.isEmpty ||
                maxAffordable != availablePresets.last))
          _QuantityButton(
            label: 'Max (${_formatQuantity(maxAffordable)})',
            onPressed: () => _showConfirmDialog(context, maxAffordable),
          ),
        // Custom button
        _QuantityButton(
          label: 'Custom',
          onPressed: () => _showCustomQuantityDialog(context),
          outlined: true,
        ),
      ],
    );
  }

  String _formatQuantity(int qty) {
    if (qty >= 1000) {
      return '${qty ~/ 1000}k';
    }
    return '$qty';
  }

  void _showCustomQuantityDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Max: $maxAffordable',
            suffixText: 'x $itemQuantityPerPurchase = items',
          ),
          onSubmitted: (value) {
            final qty = int.tryParse(value);
            if (qty != null && qty > 0 && qty <= maxAffordable) {
              Navigator.of(dialogContext).pop();
              _showConfirmDialog(context, qty);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final qty = int.tryParse(controller.text);
              if (qty != null && qty > 0 && qty <= maxAffordable) {
                Navigator.of(dialogContext).pop();
                _showConfirmDialog(context, qty);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog(BuildContext context, int quantity) {
    final state = context.state;

    // Calculate costs for the quantity
    final baseCurrencyCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: state.shop.bankSlotsPurchased,
    );
    final currencyCosts = baseCurrencyCosts
        .map((c) => (c.$1, c.$2 * quantity))
        .toList();
    final itemCosts = purchase.cost.items.map((cost) {
      final costItem = state.registries.items.byId(cost.itemId);
      return (costItem, cost.quantity * quantity, true);
    }).toList();

    final totalItems = itemQuantityPerPurchase * quantity;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Purchase ${purchase.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Buy $quantity x ${purchase.name}'),
            const SizedBox(height: 4),
            Text(
              '+$totalItems ${item.name}',
              style: const TextStyle(color: Style.successColor),
            ),
            const SizedBox(height: 12),
            const Text('Total cost:'),
            const SizedBox(height: 4),
            CostRow(
              currencyCosts: currencyCosts,
              itemCosts: itemCosts,
              showAffordability: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              try {
                // Execute purchase multiple times
                for (var i = 0; i < quantity; i++) {
                  context.dispatch(
                    PurchaseShopItemAction(purchaseId: purchase.id),
                  );
                }
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              } on Exception catch (e) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

/// Shows the shard purchase dialog for the given item.
void showShardPurchaseDialog(BuildContext context, Item item) {
  showDialog<void>(
    context: context,
    builder: (context) => ShardPurchaseDialog(item: item),
  );
}
