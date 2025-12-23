import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final Set<String> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      drawer: const AppNavigationDrawer(),
      body: StoreConnector<GlobalState, ShopViewModel>(
        converter: (store) => ShopViewModel(store.state),
        builder: (context, viewModel) {
          return ListView(children: _buildCategoryRows(context, viewModel));
        },
      ),
    );
  }

  List<Widget> _buildCategoryRows(
    BuildContext context,
    ShopViewModel viewModel,
  ) {
    final rows = <Widget>[];
    final purchasesByCategory = viewModel.purchasesByCategory;

    for (final entry in purchasesByCategory.entries) {
      final category = entry.key;
      final purchases = entry.value;
      final isCollapsed = _collapsedCategories.contains(category.id.toJson());

      // Category header
      rows.add(
        InkWell(
          onTap: () {
            setState(() {
              final categoryId = category.id.toJson();
              if (_collapsedCategories.contains(categoryId)) {
                _collapsedCategories.remove(categoryId);
              } else {
                _collapsedCategories.add(categoryId);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Style.categoryHeaderColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Icon(
                  isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                  size: 24,
                ),
                const SizedBox(width: 8),
                if (category.media != null)
                  CachedImage(assetPath: category.media!, size: 20)
                else
                  const Icon(Icons.category, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${purchases.length} items',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );

      // Items in category (if not collapsed)
      if (!isCollapsed) {
        rows.addAll(
          _buildPurchaseRowsForCategory(context, viewModel, purchases),
        );
      }
    }

    return rows;
  }

  List<Widget> _buildPurchaseRowsForCategory(
    BuildContext context,
    ShopViewModel viewModel,
    List<ShopPurchase> purchases,
  ) {
    final rows = <Widget>[];

    for (final purchase in purchases) {
      // Skip bank slots - they're handled separately with dynamic pricing
      if (purchase.cost.usesBankSlotPricing) continue;

      final unmetRequirements = viewModel.unmetSkillRequirements(purchase);
      final meetsAllReqs = unmetRequirements.isEmpty;
      final cost = purchase.cost.gpCost ?? 0;
      final canAfford = viewModel.gp >= cost;

      // Build description from purchase
      final description = _buildDescription(purchase);
      final requirementsString = unmetRequirements.isNotEmpty
          ? unmetRequirements
                .map((r) => 'Requires ${r.skill.name} level ${r.level}')
                .join('\n')
          : null;

      rows.add(
        _ShopItemRow(
          media: purchase.media,
          name: purchase.name,
          price: cost,
          description: description,
          canAfford: canAfford,
          levelRequirement: meetsAllReqs ? null : requirementsString,
          onTap: () => _showPurchaseDialog(
            context,
            name: purchase.name,
            cost: cost,
            description: description,
            levelRequirement: meetsAllReqs ? null : requirementsString,
            createAction: () => PurchaseShopItemAction(purchaseId: purchase.id),
          ),
        ),
      );
    }

    return rows;
  }

  String? _buildDescription(ShopPurchase purchase) {
    final parts = <String>[];

    // Add skill interval modifiers
    for (final mod in purchase.contains.skillIntervalModifiers) {
      final percent = mod.value < 0 ? '${mod.value}%' : '+${mod.value}%';
      parts.add('$percent ${mod.skill.name} time');
    }

    // Add bank space
    final bankSpace = purchase.contains.bankSpace;
    if (bankSpace != null) {
      parts.add('+$bankSpace bank space');
    }

    // Fall back to custom description if no modifiers
    if (parts.isEmpty && purchase.description != null) {
      return purchase.description;
    }

    return parts.isEmpty ? null : parts.join(', ');
  }

  void _showPurchaseDialog(
    BuildContext context, {
    required String name,
    required int cost,
    required ReduxAction<GlobalState> Function() createAction,
    String? description,
    String? levelRequirement,
  }) {
    final canConfirm = levelRequirement == null;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Purchase $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Purchase $name for ${approximateCreditString(cost)} GP?'),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(color: Style.successColor),
              ),
            ],
            if (levelRequirement != null) ...[
              const SizedBox(height: 8),
              Text(
                levelRequirement,
                style: const TextStyle(color: Style.errorColor),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: canConfirm
                ? () {
                    try {
                      context.dispatch(createAction());
                      Navigator.of(dialogContext).pop();
                    } on Exception catch (e) {
                      Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  }
                : null,
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class ShopViewModel {
  const ShopViewModel(this._state);

  final GlobalState _state;

  int get gp => _state.gp;
  int get nextBankSlotCost => _state.shop.nextBankSlotCost();

  ShopRegistry get _shopRegistry => _state.registries.shop;

  /// Get all visible purchases that can be shown in the shop.
  List<ShopPurchase> get visiblePurchases =>
      _shopRegistry.visiblePurchases(_state.shop.purchaseCounts);

  /// Get visible purchases grouped by category.
  /// Returns a map with categories as keys, preserving category order.
  Map<ShopCategory, List<ShopPurchase>> get purchasesByCategory {
    final result = <ShopCategory, List<ShopPurchase>>{};
    final purchases = visiblePurchases;

    // Group purchases by category, maintaining category order
    for (final category in _shopRegistry.categories) {
      final categoryPurchases = purchases
          .where((p) => p.category == category.id)
          .toList();
      if (categoryPurchases.isNotEmpty) {
        result[category] = categoryPurchases;
      }
    }

    return result;
  }

  /// Get skill level requirements that the player doesn't meet.
  List<SkillLevelRequirement> unmetSkillRequirements(ShopPurchase purchase) {
    final requirements = _shopRegistry.skillLevelRequirements(purchase);
    return requirements
        .where((r) => _state.skillState(r.skill).skillLevel < r.level)
        .toList();
  }

  /// Get the player's skill level for a skill.
  int skillLevel(Skill skill) => _state.skillState(skill).skillLevel;
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.name,
    required this.price,
    required this.canAfford,
    required this.onTap,
    this.media,
    this.description,
    this.levelRequirement,
  });

  /// The asset path for the purchase icon.
  final String? media;

  final String name;
  final int price;
  final bool canAfford;
  final VoidCallback onTap;

  /// Optional description shown below the name.
  final String? description;

  /// Optional level requirement text shown when requirement is not met.
  final String? levelRequirement;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (media != null)
              CachedImage(assetPath: media!)
            else
              const Icon(Icons.shopping_cart, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${approximateCreditString(price)} GP',
                    style: TextStyle(
                      color: canAfford ? Style.successColor : Style.errorColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (levelRequirement != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      levelRequirement!,
                      style: TextStyle(
                        color: Style.shopPurchasedColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
