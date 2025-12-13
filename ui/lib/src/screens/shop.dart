import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/strings.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      drawer: const AppNavigationDrawer(),
      body: StoreConnector<GlobalState, ShopViewModel>(
        converter: (store) => ShopViewModel(
          gp: store.state.gp,
          nextBankSlotCost: store.state.shop.nextBankSlotCost(),
        ),
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
            ],
          );
        },
      ),
    );
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
}

class ShopViewModel {
  const ShopViewModel({required this.gp, required this.nextBankSlotCost});

  final int gp;
  final int nextBankSlotCost;
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
