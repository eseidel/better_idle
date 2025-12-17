import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

extension UpgradeTypeIcon on UpgradeType {
  IconData get icon {
    return switch (this) {
      UpgradeType.axe => Icons.carpenter,
      UpgradeType.fishingRod => Icons.phishing,
      UpgradeType.pickaxe => Icons.hardware,
    };
  }
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
                onTap: () =>
                    _showPurchaseDialog(context, viewModel.nextBankSlotCost),
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

    for (final type in UpgradeType.values) {
      final upgrade = nextUpgrade(type, viewModel.upgradeLevel(type));
      if (upgrade != null) {
        final meetsLevelReq =
            viewModel.skillLevelFor(upgrade) >= upgrade.requiredLevel;
        final canAfford = viewModel.gp >= upgrade.cost;

        rows.add(
          _UpgradeItemRow(
            icon: Icon(type.icon),
            upgrade: upgrade,
            canAfford: canAfford,
            meetsLevelReq: meetsLevelReq,
            onTap: () => _showUpgradePurchaseDialog(
              context,
              upgrade,
              type,
              meetsLevelReq: meetsLevelReq,
            ),
          ),
        );
      }
    }

    return rows;
  }

  void _showPurchaseDialog(BuildContext context, int cost) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Purchase Bank Slot'),
        content: Text(
          'Purchase Bank Slot for ${approximateCreditString(cost)} GP?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              try {
                context.dispatch(PurchaseBankSlotAction());
                Navigator.of(dialogContext).pop();
              } on Exception catch (e) {
                // Show error if purchase fails (e.g., not enough GP)
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

  void _showUpgradePurchaseDialog(
    BuildContext context,
    SkillUpgrade upgrade,
    UpgradeType upgradeType, {
    required bool meetsLevelReq,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Purchase ${upgrade.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Purchase ${upgrade.name} for '
              '${approximateCreditString(upgrade.cost)} GP?',
            ),
            const SizedBox(height: 8),
            Text(
              upgrade.description,
              style: const TextStyle(color: Colors.green),
            ),
            if (!meetsLevelReq) ...[
              const SizedBox(height: 8),
              Text(
                'Requires ${upgrade.skill.name} level ${upgrade.requiredLevel}',
                style: const TextStyle(color: Colors.red),
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
            onPressed: meetsLevelReq
                ? () {
                    try {
                      context.dispatch(
                        PurchaseUpgradeAction(upgradeType: upgradeType),
                      );
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

  /// Get the current upgrade level for a given type.
  int upgradeLevel(UpgradeType type) => _state.shop.upgradeLevel(type);

  /// Get the player's skill level for an upgrade's required skill.
  int skillLevelFor(SkillUpgrade upgrade) =>
      _state.skillState(upgrade.skill).skillLevel;
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.icon,
    required this.name,
    required this.price,
    required this.canAfford,
    required this.onTap,
  });

  final Widget icon;
  final String name;
  final int price;
  final bool canAfford;
  final VoidCallback onTap;

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
                  const SizedBox(height: 4),
                  Text(
                    '${approximateCreditString(price)} GP',
                    style: TextStyle(
                      color: canAfford ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeItemRow extends StatelessWidget {
  const _UpgradeItemRow({
    required this.icon,
    required this.upgrade,
    required this.canAfford,
    required this.meetsLevelReq,
    required this.onTap,
  });

  final Widget icon;
  final SkillUpgrade upgrade;
  final bool canAfford;
  final bool meetsLevelReq;
  final VoidCallback onTap;

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
                  Text(
                    upgrade.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    upgrade.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${approximateCreditString(upgrade.cost)} GP',
                    style: TextStyle(
                      color: canAfford ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!meetsLevelReq) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Requires ${upgrade.skill.name} '
                      'level ${upgrade.requiredLevel}',
                      style: TextStyle(
                        color: Colors.orange.shade700,
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
