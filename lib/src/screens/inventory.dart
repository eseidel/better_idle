import 'package:better_idle/src/data/items.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/redux_actions.dart';
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
    final state = context.state;
    final inventoryUsed = state.inventoryUsed;
    final inventoryCapacity = state.inventoryCapacity;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text('Inventory')),
      drawer: const AppNavigationDrawer(),
      endDrawer: _selectedItem != null
          ? ItemDetailsDrawer(item: _selectedItem!)
          : null,
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('Bank: ${formatter.format(sellValue)} GP'),
              Text('Capacity: $inventoryUsed/$inventoryCapacity'),
            ],
          ),
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
      itemCount: stacks.length, // Only show actual items, no empty cells
      itemBuilder: (context, index) {
        return StackCell(
          stack: stacks[index],
          onTap: () => onItemTap(stacks[index]),
        );
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

class ItemDetailsDrawer extends StatefulWidget {
  const ItemDetailsDrawer({required this.item, super.key});

  final ItemStack item;

  @override
  State<ItemDetailsDrawer> createState() => _ItemDetailsDrawerState();
}

class _ItemDetailsDrawerState extends State<ItemDetailsDrawer> {
  double _sellCount = 0;
  int _lastKnownMaxCount = 0;

  @override
  void initState() {
    super.initState();
    _sellCount = widget.item.count.toDouble();
    _lastKnownMaxCount = widget.item.count;
  }

  int _getCurrentMaxCount(BuildContext context) {
    final currentItem = context.state.inventory.items.firstWhereOrNull(
      (i) => i.name == widget.item.name,
    );
    return currentItem?.count ?? 0;
  }

  @override
  void didUpdateWidget(ItemDetailsDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the item prop changed, reset sell count to the new item's count
    if (oldWidget.item.name != widget.item.name) {
      setState(() {
        _sellCount = widget.item.count.toDouble();
        _lastKnownMaxCount = widget.item.count;
      });
      return;
    }

    // If the item count in the prop changed, update accordingly
    if (oldWidget.item.count != widget.item.count) {
      final newMaxCount = widget.item.count;
      setState(() {
        _lastKnownMaxCount = newMaxCount;
        if (_sellCount > newMaxCount) {
          _sellCount = newMaxCount > 0 ? newMaxCount.toDouble() : 0;
        }
      });
    }

    // Clamp based on current state (may have changed from external actions)
    // Use post-frame callback since we need context which isn't available in didUpdateWidget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentMaxCount = _getCurrentMaxCount(context);
      if (currentMaxCount < _lastKnownMaxCount &&
          _sellCount > currentMaxCount) {
        setState(() {
          _sellCount = currentMaxCount > 0 ? currentMaxCount.toDouble() : 0;
          _lastKnownMaxCount = currentMaxCount;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // When dependencies change (Redux state updated), check if we need to clamp
    final currentMaxCount = _getCurrentMaxCount(context);

    // Only update if the max count decreased below our sell count
    if (currentMaxCount < _lastKnownMaxCount && _sellCount > currentMaxCount) {
      setState(() {
        _sellCount = currentMaxCount > 0 ? currentMaxCount.toDouble() : 0;
        _lastKnownMaxCount = currentMaxCount;
      });
    } else if (currentMaxCount != _lastKnownMaxCount) {
      // Update tracking even if we don't need to clamp (no setState needed for internal tracking)
      _lastKnownMaxCount = currentMaxCount;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get current item count from state (may have changed after selling)
    final currentItem = context.state.inventory.items.firstWhereOrNull(
      (i) => i.name == widget.item.name,
    );

    if (currentItem == null) {
      // If we don't have the item in the inventory, don't show the drawer.
      // Could also throw an exception since this should never happen.
      return const SizedBox.shrink();
    }

    final maxCount = currentItem.count;

    final itemData = itemRegistry.byName(widget.item.name);
    final formatter = NumberFormat('#,##0');
    final sellCountInt = _sellCount.round();
    final totalGpValue = itemData.sellsFor * sellCountInt;

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
              Text(
                widget.item.name,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text(
                'Gold Value:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${formatter.format(itemData.sellsFor)} GP',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Text('Sell Item', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Text(
                'Quantity: ${formatter.format(sellCountInt)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Slider(
                value: _sellCount,
                min: 0,
                max: maxCount > 0 ? maxCount.toDouble() : 1.0,
                divisions: maxCount > 0 ? maxCount : null,
                label: formatter.format(sellCountInt),
                onChanged: maxCount > 0
                    ? (value) {
                        setState(() {
                          _sellCount = value;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: sellCountInt > 0
                      ? () {
                          context.dispatch(
                            SellItemAction(
                              itemName: widget.item.name,
                              count: sellCountInt,
                            ),
                          );
                          Navigator.of(context).pop();
                        }
                      : null,
                  child: const Text('Sell'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Total Value: ${formatter.format(totalGpValue)} GP',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
