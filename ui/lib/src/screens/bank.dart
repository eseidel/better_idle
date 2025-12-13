import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:logic/logic.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/strings.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class BankPage extends StatefulWidget {
  const BankPage({super.key});

  @override
  State<BankPage> createState() => _BankPageState();
}

int totalSellValue(Inventory inventory) {
  return inventory.items.fold(0, (sum, stack) => sum + stack.sellsFor);
}

class _BankPageState extends State<BankPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  ItemStack? _selectedStack;

  void _onItemTap(ItemStack stack) {
    setState(() {
      _selectedStack = stack;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final sellValue = totalSellValue(context.state.inventory);
    final state = context.state;
    final inventoryUsed = state.inventoryUsed;
    final inventoryCapacity = state.inventoryCapacity;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text('Bank')),
      drawer: const AppNavigationDrawer(),
      endDrawer: _selectedStack != null
          ? ItemDetailsDrawer(stack: _selectedStack!)
          : null,
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('Space: $inventoryUsed/$inventoryCapacity'),
              Text('Value: ${approximateCreditString(sellValue)} GP'),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        color: Colors.green,
        child: Stack(
          children: [
            // Item name centered
            Center(
              child: Text(
                ' ${stack.item.name}',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Count badge at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  approximateCountString(stack.count),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemDetailsDrawer extends StatefulWidget {
  const ItemDetailsDrawer({required this.stack, super.key});

  final ItemStack stack;

  @override
  State<ItemDetailsDrawer> createState() => _ItemDetailsDrawerState();
}

class _ItemDetailsDrawerState extends State<ItemDetailsDrawer> {
  double _sellCount = 0;
  int _lastKnownMaxCount = 0;

  @override
  void initState() {
    super.initState();
    _sellCount = widget.stack.count.toDouble();
    _lastKnownMaxCount = widget.stack.count;
  }

  int _getCurrentMaxCount(BuildContext context) {
    final currentItem = context.state.inventory.items.firstWhereOrNull(
      (i) => i.item == widget.stack.item,
    );
    return currentItem?.count ?? 0;
  }

  @override
  void didUpdateWidget(ItemDetailsDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the item prop changed, reset sell count to the new item's count
    if (oldWidget.stack.item != widget.stack.item) {
      setState(() {
        _sellCount = widget.stack.count.toDouble();
        _lastKnownMaxCount = widget.stack.count;
      });
      return;
    }

    // If the item count in the prop changed, update accordingly
    if (oldWidget.stack.count != widget.stack.count) {
      final newMaxCount = widget.stack.count;
      setState(() {
        _lastKnownMaxCount = newMaxCount;
        if (_sellCount > newMaxCount) {
          _sellCount = newMaxCount > 0 ? newMaxCount.toDouble() : 0;
        }
      });
    }

    // Clamp based on current state (may have changed from external actions)
    // Use post-frame callback since we need context which isn't available
    // in didUpdateWidget
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
      // Update tracking even if we don't need to clamp
      // (no setState needed for internal tracking)
      _lastKnownMaxCount = currentMaxCount;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get current item count from state (may have changed after selling)
    final currentItem = context.state.inventory.items.firstWhereOrNull(
      (i) => i.item == widget.stack.item,
    );

    if (currentItem == null) {
      // If we don't have the item in the inventory, don't show the drawer.
      // Could also throw an exception since this should never happen.
      return const SizedBox.shrink();
    }

    final maxCount = currentItem.count;

    final itemData = widget.stack.item;
    final sellCountInt = _sellCount.round();
    final totalGpValue = itemData.sellsFor * sellCountInt;

    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                widget.stack.item.name,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text(
                'Gold Value:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${approximateCreditString(itemData.sellsFor)} GP',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              Text('Sell Item', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Text(
                'Quantity: ${approximateCountString(sellCountInt)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Slider(
                value: _sellCount,
                max: maxCount > 0 ? maxCount.toDouble() : 1.0,
                divisions: maxCount > 0 ? maxCount : null,
                label: preciseNumberString(sellCountInt),
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
                              item: widget.stack.item,
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
                'Total Value: ${approximateCreditString(totalGpValue)} GP',
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
