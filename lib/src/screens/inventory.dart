import 'package:better_idle/src/data/items.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../state.dart';
import '../widgets/context_extensions.dart';
import '../widgets/navigation_drawer.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

int totalSellValue(Inventory inventory) {
  return inventory.items.fold(
    0,
    (sum, item) => sum + itemRegistry.byName(item.name).sellsFor * item.count,
  );
}

class _InventoryPageState extends State<InventoryPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  ItemStack? _selectedItem;

  void _onItemTap(ItemStack item) {
    setState(() {
      _selectedItem = item;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final sellValue = totalSellValue(context.state.inventory);
    final formatter = NumberFormat('#,##0');
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text('Inventory')),
      drawer: const AppNavigationDrawer(),
      endDrawer: _selectedItem != null
          ? ItemDetailsDrawer(item: _selectedItem!)
          : null,
      body: Column(
        children: [
          Text('Bank: ${formatter.format(sellValue)} GP'),
          Expanded(
            child: ItemGrid(
              stacks: context.state.inventory.items,
              onItemTap: _onItemTap,
            ),
          ),
        ],
      ),
    );
  }
}

class ItemGrid extends StatelessWidget {
  const ItemGrid({required this.stacks, required this.onItemTap, super.key});

  final List<ItemStack> stacks;
  final void Function(ItemStack) onItemTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: 16, // Fixed number of slots for illustration
      itemBuilder: (context, index) {
        if (index < stacks.length) {
          return StackCell(
            stack: stacks[index],
            onTap: () => onItemTap(stacks[index]),
          );
        }
        return Container();
      },
    );
  }
}

class StackCell extends StatelessWidget {
  const StackCell({required this.stack, required this.onTap, super.key});

  final ItemStack stack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0');
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        color: Colors.green,
        child: Center(
          child: Text('${formatter.format(stack.count)} ${stack.name}'),
        ),
      ),
    );
  }
}

class ItemDetailsDrawer extends StatelessWidget {
  const ItemDetailsDrawer({required this.item, super.key});

  final ItemStack item;

  @override
  Widget build(BuildContext context) {
    // Hardcoded gold value to 1 for all items
    const int goldValue = 1;

    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Item Details',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Text('Name:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(item.name, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              Text(
                'Gold Value:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('$goldValue', style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
