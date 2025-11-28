import 'package:flutter/material.dart';

import '../state.dart';
import '../widgets/context_extensions.dart';
import '../widgets/navigation_drawer.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          const Text('Inventory'),
          const SizedBox(height: 16),
          Expanded(child: ItemGrid(stacks: context.state.inventory.items)),
        ],
      ),
    );
  }
}

class ItemGrid extends StatelessWidget {
  const ItemGrid({required this.stacks, super.key});

  final List<ItemStack> stacks;

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
          return StackCell(stack: stacks[index]);
        }
        return Container();
      },
    );
  }
}

class StackCell extends StatelessWidget {
  const StackCell({required this.stack, super.key});

  final ItemStack stack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      color: Colors.green,
      child: Text('${stack.count} ${stack.name}'),
    );
  }
}
