import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Returns an icon for a skill upgrade based on the skill it affects.
IconData _iconForSkill(Skill skill) {
  return switch (skill) {
    Skill.woodcutting => Icons.carpenter,
    Skill.fishing => Icons.phishing,
    Skill.mining => Icons.hardware,
    _ => Icons.shopping_cart,
  };
}

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      drawer: const AppNavigationDrawer(),
      body: StoreConnector<GlobalState, ShopViewModel>(
        converter: (store) => ShopViewModel(store.state),
        builder: (context, viewModel) {
          return ListView(
            children: [
              _ShopItemRow(
                icon: const Icon(Icons.account_balance),
                name: 'Bank Slot',
                price: viewModel.nextBankSlotCost,
                canAfford: viewModel.gp >= viewModel.nextBankSlotCost,
                onTap: () => _showPurchaseDialog(
                  context,
                  name: 'Bank Slot',
                  cost: viewModel.nextBankSlotCost,
                  createAction: PurchaseBankSlotAction.new,
                ),
              ),
              ..._buildUpgradeRows(context, viewModel),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildUpgradeRows(
    BuildContext context,
    ShopViewModel viewModel,
  ) {
    final rows = <Widget>[];
    final availableUpgrades = viewModel.availableUpgrades;

    for (final (purchase, skill) in availableUpgrades) {
      final requiredLevel = viewModel.skillLevelRequirement(purchase);
      final meetsLevelReq =
          requiredLevel == null || viewModel.skillLevel(skill) >= requiredLevel;
      final cost = purchase.cost.gpCost ?? 0;
      final canAfford = viewModel.gp >= cost;

      // Build description from modifiers
      final description = _buildDescription(purchase);
      final requirementsString = requiredLevel != null
          ? 'Requires ${skill.name} level $requiredLevel'
          : null;

      rows.add(
        _ShopItemRow(
          icon: Icon(_iconForSkill(skill)),
          name: purchase.name,
          price: cost,
          description: description,
          canAfford: canAfford,
          levelRequirement: meetsLevelReq ? null : requirementsString,
          onTap: () => _showPurchaseDialog(
            context,
            name: purchase.name,
            cost: cost,
            description: description,
            levelRequirement: meetsLevelReq ? null : requirementsString,
            createAction: () => PurchaseShopItemAction(purchaseId: purchase.id),
          ),
        ),
      );
    }

    return rows;
  }

  String? _buildDescription(ShopPurchase purchase) {
    final modifiers = purchase.contains.skillIntervalModifiers;
    if (modifiers.isEmpty) return null;

    final parts = <String>[];
    for (final mod in modifiers) {
      final percent = mod.value < 0 ? '${mod.value}%' : '+${mod.value}%';
      parts.add('$percent ${mod.skill.name} time');
    }
    return parts.join(', ');
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

  /// Get available skill upgrades that can be purchased.
  List<(ShopPurchase, Skill)> get availableUpgrades =>
      _shopRegistry.availableSkillUpgrades(_state.shop.purchaseCounts);

  /// Get the skill level requirement for a purchase.
  int? skillLevelRequirement(ShopPurchase purchase) =>
      _shopRegistry.skillLevelRequirement(purchase);

  /// Get the player's skill level for a skill.
  int skillLevel(Skill skill) => _state.skillState(skill).skillLevel;
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.icon,
    required this.name,
    required this.price,
    required this.canAfford,
    required this.onTap,
    this.description,
    this.levelRequirement,
  });

  final Widget icon;
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
            icon,
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
