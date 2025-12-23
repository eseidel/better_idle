import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/services/toast_service.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/open_result_dialog.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Space: $inventoryUsed/$inventoryCapacity',
                  style: inventoryUsed >= inventoryCapacity
                      ? const TextStyle(color: Style.errorColor)
                      : null,
                ),
                const SizedBox(width: 16),
                Text('Value: ${approximateCreditString(sellValue)} GP'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort inventory',
                  onPressed: () => context.dispatch(SortInventoryAction()),
                ),
              ],
            ),
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

  static const double _cellSize = 72;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _cellSize,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: stacks.length,
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
    return CountBadgeCell(
      onTap: onTap,
      backgroundColor: Style.cellBackgroundColor,
      borderColor: Style.cellBorderColorSuccess,
      count: stack.count,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Center(child: ItemImage(item: stack.item)),
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
        child: SingleChildScrollView(
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
              Row(
                children: [
                  ItemImage(item: widget.stack.item, size: 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.stack.item.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
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
              // Show Equip button for consumable items
              if (itemData.isConsumable) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _EquipFoodSection(item: itemData, maxCount: maxCount),
              ],
              // Show Equip button for gear items
              if (itemData.isEquippable) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _EquipGearSection(item: itemData),
              ],
              // Show Open button for openable items
              if (itemData.isOpenable) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _OpenItemSection(item: itemData, maxCount: maxCount),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EquipFoodSection extends StatefulWidget {
  const _EquipFoodSection({required this.item, required this.maxCount});

  final Item item;
  final int maxCount;

  @override
  State<_EquipFoodSection> createState() => _EquipFoodSectionState();
}

class _EquipFoodSectionState extends State<_EquipFoodSection> {
  double _equipCount = 1;

  @override
  void initState() {
    super.initState();
    _equipCount = widget.maxCount.toDouble();
  }

  @override
  void didUpdateWidget(_EquipFoodSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxCount != widget.maxCount) {
      if (_equipCount > widget.maxCount) {
        setState(() {
          _equipCount = widget.maxCount > 0 ? widget.maxCount.toDouble() : 1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final equipment = context.state.equipment;
    final canEquip = equipment.canEquipFood(widget.item);
    final equipCountInt = _equipCount.round().clamp(1, widget.maxCount);

    // Check if item is already equipped
    final existingSlot = equipment.foodSlotWithItem(widget.item);
    final existingCount = existingSlot >= 0
        ? equipment.foodSlots[existingSlot]?.count ?? 0
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Equip Food', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (widget.item.healsFor != null)
          Text(
            'Heals ${widget.item.healsFor} HP',
            style: TextStyle(color: Style.textColorSuccess),
          ),
        if (existingCount > 0)
          Text(
            'Currently equipped: $existingCount',
            style: TextStyle(color: Style.textColorInfo),
          ),
        const SizedBox(height: 16),
        Text(
          'Quantity: ${approximateCountString(equipCountInt)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Slider(
          value: _equipCount.clamp(1, widget.maxCount.toDouble()),
          min: 1,
          max: widget.maxCount > 0 ? widget.maxCount.toDouble() : 1.0,
          divisions: widget.maxCount > 1 ? widget.maxCount - 1 : null,
          label: preciseNumberString(equipCountInt),
          onChanged: widget.maxCount > 0
              ? (value) {
                  setState(() {
                    _equipCount = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canEquip && equipCountInt > 0
                ? () {
                    context.dispatch(
                      EquipFoodAction(item: widget.item, count: equipCountInt),
                    );
                    Navigator.of(context).pop();
                  }
                : null,
            child: Text(existingSlot >= 0 ? 'Add to Equipped' : 'Equip'),
          ),
        ),
        if (!canEquip)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'All food slots are full',
              style: TextStyle(color: Style.textColorError, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _OpenItemSection extends StatefulWidget {
  const _OpenItemSection({required this.item, required this.maxCount});

  final Item item;
  final int maxCount;

  @override
  State<_OpenItemSection> createState() => _OpenItemSectionState();
}

class _OpenItemSectionState extends State<_OpenItemSection> {
  double _openCount = 1;

  @override
  void initState() {
    super.initState();
    _openCount = widget.maxCount.toDouble();
  }

  @override
  void didUpdateWidget(_OpenItemSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxCount != widget.maxCount) {
      if (_openCount > widget.maxCount) {
        setState(() {
          _openCount = widget.maxCount > 0 ? widget.maxCount.toDouble() : 1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final openCountInt = _openCount.round().clamp(1, widget.maxCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Open Item', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Open to receive a random drop',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text(
          'Quantity: ${approximateCountString(openCountInt)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Slider(
          value: _openCount.clamp(1, widget.maxCount.toDouble()),
          min: 1,
          max: widget.maxCount > 0 ? widget.maxCount.toDouble() : 1.0,
          divisions: widget.maxCount > 1 ? widget.maxCount - 1 : null,
          label: preciseNumberString(openCountInt),
          onChanged: widget.maxCount > 0
              ? (value) {
                  setState(() {
                    _openCount = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              final itemName = widget.item.name;
              context.dispatch(
                OpenItemAction(
                  item: widget.item,
                  count: openCountInt,
                  onResult: (result) {
                    // Close the drawer first
                    Navigator.of(context).pop();

                    if (result.hasDrops) {
                      // Show dialog with results
                      showDialog<void>(
                        context: context,
                        builder: (context) => OpenResultDialog(
                          itemName: itemName,
                          result: result,
                        ),
                      );
                    } else if (result.error != null) {
                      // No items opened, show error toast
                      toastService.showError(result.error!);
                    }
                  },
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ],
    );
  }
}

class _EquipGearSection extends StatelessWidget {
  const _EquipGearSection({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final equipment = context.state.equipment;
    final validSlots = item.validSlots;

    // Find which slot this item is currently equipped in (if any)
    EquipmentSlot? currentlyEquippedSlot;
    for (final slot in validSlots) {
      if (equipment.gearInSlot(slot) == item) {
        currentlyEquippedSlot = slot;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Equip Gear', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Valid slots: ${validSlots.map((s) => s.displayName).join(', ')}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (currentlyEquippedSlot != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Currently equipped in: ${currentlyEquippedSlot.displayName}',
              style: TextStyle(color: Style.textColorInfo),
            ),
          ),
        const SizedBox(height: 16),
        // Show an equip button for each valid slot
        for (final slot in validSlots) ...[
          _EquipSlotButton(item: item, slot: slot, equipment: equipment),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _EquipSlotButton extends StatelessWidget {
  const _EquipSlotButton({
    required this.item,
    required this.slot,
    required this.equipment,
  });

  final Item item;
  final EquipmentSlot slot;
  final Equipment equipment;

  @override
  Widget build(BuildContext context) {
    final currentItem = equipment.gearInSlot(slot);
    final isAlreadyEquipped = currentItem == item;

    String buttonText;
    if (isAlreadyEquipped) {
      buttonText = '${slot.displayName} (Already equipped)';
    } else if (currentItem != null) {
      buttonText = '${slot.displayName} (Swap with ${currentItem.name})';
    } else {
      buttonText = 'Equip in ${slot.displayName}';
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isAlreadyEquipped
            ? null
            : () {
                context.dispatch(EquipGearAction(item: item, slot: slot));
                Navigator.of(context).pop();
              },
        child: Text(buttonText),
      ),
    );
  }
}
