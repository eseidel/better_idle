import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/services/toast_service.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/count_badge_cell.dart';
import 'package:ui/src/widgets/currency_display.dart';
import 'package:ui/src/widgets/game_app_bar.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/navigation_drawer.dart';
import 'package:ui/src/widgets/open_result_dialog.dart';
import 'package:ui/src/widgets/style.dart';

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

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<Item> _selectedItems = {};

  void _onItemTap(ItemStack stack) {
    if (_isSelectionMode) {
      // Toggle selection
      setState(() {
        if (_selectedItems.contains(stack.item)) {
          _selectedItems.remove(stack.item);
          // Exit selection mode if no items selected
          if (_selectedItems.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedItems.add(stack.item);
        }
      });
    } else {
      // Normal single-select mode - open drawer
      setState(() {
        _selectedStack = stack;
      });
      // Use WidgetsBinding to ensure the drawer is built before opening
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scaffoldKey.currentState?.openEndDrawer();
      });
    }
  }

  void _onItemDoubleTap(ItemStack stack) {
    if (_isSelectionMode) return;
    context.dispatch(QuickEquipAction(stack: stack));
  }

  void _onItemLongPress(ItemStack stack) {
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
        _selectedItems.add(stack.item);
      });
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedItems.clear();
    });
  }

  Future<void> _showSellConfirmation() async {
    final inventory = context.state.inventory;
    // Build list of selected stacks (items with current counts from inventory)
    final selectedStacks = <ItemStack>[];
    for (final item in _selectedItems) {
      final stack = inventory.items.firstWhereOrNull((s) => s.item == item);
      if (stack != null) {
        selectedStacks.add(stack);
      }
    }

    if (selectedStacks.isEmpty) {
      _exitSelectionMode();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _SellConfirmationDialog(stacks: selectedStacks),
    );

    if (!mounted) return;
    if (confirmed ?? false) {
      // Perform the sale
      context.dispatch(SellMultipleItemsAction(stacks: selectedStacks));
      _exitSelectionMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellValue = totalSellValue(context.state.inventory);
    final state = context.state;
    final inventoryUsed = state.inventoryUsed;
    final inventoryCapacity = state.inventoryCapacity;
    final isWide = MediaQuery.sizeOf(context).width >= sidebarBreakpoint;

    // Handle back button in selection mode
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: _isSelectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                ),
                title: Text('${_selectedItems.length} selected'),
                actions: [
                  TextButton(
                    onPressed: _selectedItems.isNotEmpty
                        ? _showSellConfirmation
                        : null,
                    child: const Text(
                      'Sell',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              )
            : GameAppBar(title: const Text('Bank')),
        drawer: !isWide && !_isSelectionMode
            ? const AppNavigationDrawer()
            : null,
        endDrawer: !_isSelectionMode && _selectedStack != null
            ? ItemDetailsDrawer(stack: _selectedStack!)
            : null,
        body: Column(
          children: [
            if (!_isSelectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      'Space: $inventoryUsed/$inventoryCapacity',
                      style: inventoryUsed >= inventoryCapacity
                          ? const TextStyle(color: Style.errorColor)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    CurrencyDisplay(currency: Currency.gp, amount: sellValue),
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
                onItemDoubleTap: _onItemDoubleTap,
                onItemLongPress: _onItemLongPress,
                selectedItems: _isSelectionMode ? _selectedItems : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemGrid extends StatelessWidget {
  const ItemGrid({
    required this.stacks,
    required this.onItemTap,
    this.onItemDoubleTap,
    this.onItemLongPress,
    this.selectedItems,
    super.key,
  });

  final List<ItemStack> stacks;
  final void Function(ItemStack) onItemTap;
  final void Function(ItemStack)? onItemDoubleTap;
  final void Function(ItemStack)? onItemLongPress;
  final Set<Item>? selectedItems;

  // Cell dimensions: 64px square + 8px badge overlap = 64x72
  static const double _cellWidth = 64;
  static const double _cellHeight = 72;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _cellWidth,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: _cellWidth / _cellHeight,
      ),
      itemCount: stacks.length,
      itemBuilder: (context, index) {
        final stack = stacks[index];
        final isSelected = selectedItems?.contains(stack.item) ?? false;
        return StackCell(
          stack: stack,
          onTap: () => onItemTap(stack),
          onDoubleTap: onItemDoubleTap != null
              ? () => onItemDoubleTap!(stack)
              : null,
          onLongPress: onItemLongPress != null
              ? () => onItemLongPress!(stack)
              : null,
          isSelected: isSelected,
        );
      },
    );
  }
}

class StackCell extends StatelessWidget {
  const StackCell({
    required this.stack,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.isSelected = false,
    super.key,
  });

  final ItemStack stack;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  // Grid cell is 72px. Badge overlap is 8px, so inradius = 72 - 8 = 64.
  static const double _inradius = 64;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: stack.item.name,
      preferBelow: false,
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            CountBadgeCell(
              inradius: _inradius,
              onTap: onTap,
              backgroundColor: Style.cellBackgroundColor,
              borderColor: isSelected
                  ? Style.cellBorderColorSelected
                  : Style.cellBorderColorSuccess,
              count: stack.count,
              child: Center(
                child: ItemImage(item: stack.item, size: _inradius * 0.6),
              ),
            ),
            // Selection checkmark overlay
            if (isSelected)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Style.selectedColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
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
              // Show item modifiers if any
              if (itemData.modifiers.modifiers.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ItemModifiersDisplay(item: itemData),
              ],
              const SizedBox(height: 24),
              Text(
                'Gold Value:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              CurrencyDisplay(currency: Currency.gp, amount: itemData.sellsFor),
              // Show Claim button for mastery tokens
              if (itemData.masteryTokenSkillId != null) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _ClaimMasteryTokenSection(item: itemData, maxCount: maxCount),
              ],
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
              Row(
                children: [
                  Text(
                    'Total Value: ',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  CurrencyDisplay(currency: Currency.gp, amount: totalGpValue),
                ],
              ),
              // Show Equip button for consumable items
              if (itemData.isConsumable) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _EquipFoodSection(item: itemData, maxCount: maxCount),
              ],
              // Show Equip button for summoning tablets
              if (itemData.isSummonTablet) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _EquipSummonSection(item: itemData, maxCount: maxCount),
              ]
              // Show Equip button for other gear items
              else if (itemData.isEquippable) ...[
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
              // Show Upgrade button if upgrades available
              if (context.state.registries.itemUpgrades
                  .upgradesForItem(itemData.id)
                  .isNotEmpty) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _UpgradeSection(item: itemData),
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
    final state = context.state;
    final equipment = state.equipment;

    // Get valid slots from the item
    final validSlots = item.validSlots;

    // Find which slot this item is currently equipped in (if any)
    EquipmentSlot? currentlyEquippedSlot;
    for (final slot in validSlots) {
      if (equipment.gearInSlot(slot) == item) {
        currentlyEquippedSlot = slot;
        break;
      }
    }

    // Get unmet equipment requirements
    final unmetRequirements = state.unmetEquipRequirements(item);
    final canEquip = unmetRequirements.isEmpty;

    final slots = state.registries.equipmentSlots;
    String slotName(EquipmentSlot s) => slots[s]?.emptyName ?? s.jsonName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Equip Gear', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Valid slots: ${validSlots.map(slotName).join(', ')}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (currentlyEquippedSlot != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Currently equipped in: ${slotName(currentlyEquippedSlot)}',
              style: TextStyle(color: Style.textColorInfo),
            ),
          ),
        // Show unmet requirements if any
        if (unmetRequirements.isNotEmpty) ...[
          const SizedBox(height: 8),
          _EquipRequirementsDisplay(requirements: unmetRequirements),
        ],
        const SizedBox(height: 16),
        // Show an equip button for each valid slot
        for (final slot in validSlots) ...[
          _EquipSlotButton(
            item: item,
            slot: slot,
            equipment: equipment,
            canEquip: canEquip,
          ),
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
    required this.canEquip,
  });

  final Item item;
  final EquipmentSlot slot;
  final Equipment equipment;
  final bool canEquip;

  @override
  Widget build(BuildContext context) {
    final slotDef = context.state.registries.equipmentSlots[slot];
    final slotName = slotDef?.emptyName ?? slot.jsonName;
    final currentItem = equipment.gearInSlot(slot);
    final isAlreadyEquipped = currentItem == item;

    String buttonText;
    if (isAlreadyEquipped) {
      buttonText = '$slotName (Already equipped)';
    } else if (currentItem != null) {
      buttonText = '$slotName (Swap with ${currentItem.name})';
    } else {
      buttonText = 'Equip in $slotName';
    }

    // Disable if already equipped OR requirements not met
    final isDisabled = isAlreadyEquipped || !canEquip;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isDisabled
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

class _EquipSummonSection extends StatelessWidget {
  const _EquipSummonSection({required this.item, required this.maxCount});

  final Item item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final equipment = state.equipment;

    // Get unmet equipment requirements
    final unmetRequirements = state.unmetEquipRequirements(item);
    final canEquip = unmetRequirements.isEmpty;

    // Check what's in each summon slot
    final summon1Item = equipment.gearInSlot(EquipmentSlot.summon1);
    final summon1Count = equipment.summonCountInSlot(EquipmentSlot.summon1);
    final summon2Item = equipment.gearInSlot(EquipmentSlot.summon2);
    final summon2Count = equipment.summonCountInSlot(EquipmentSlot.summon2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Equip Summon', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'In inventory: ${approximateCountString(maxCount)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // Show unmet requirements if any
        if (unmetRequirements.isNotEmpty) ...[
          const SizedBox(height: 8),
          _EquipRequirementsDisplay(requirements: unmetRequirements),
        ],
        const SizedBox(height: 16),
        // Show current summon slots
        Text('Summon Slots:', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _SummonSlotRow(
          slotName: 'Slot 1',
          slot: EquipmentSlot.summon1,
          equippedItem: summon1Item,
          equippedCount: summon1Count,
          itemToEquip: item,
          canEquip: canEquip,
        ),
        const SizedBox(height: 8),
        _SummonSlotRow(
          slotName: 'Slot 2',
          slot: EquipmentSlot.summon2,
          equippedItem: summon2Item,
          equippedCount: summon2Count,
          itemToEquip: item,
          canEquip: canEquip,
        ),
      ],
    );
  }
}

class _SummonSlotRow extends StatelessWidget {
  const _SummonSlotRow({
    required this.slotName,
    required this.slot,
    required this.equippedItem,
    required this.equippedCount,
    required this.itemToEquip,
    required this.canEquip,
  });

  final String slotName;
  final EquipmentSlot slot;
  final Item? equippedItem;
  final int equippedCount;
  final Item itemToEquip;
  final bool canEquip;

  @override
  Widget build(BuildContext context) {
    final isEmpty = equippedItem == null;
    final isSameItem = equippedItem == itemToEquip;

    String buttonText;
    VoidCallback? onPressed;

    if (isEmpty) {
      buttonText = 'Equip';
    } else if (isSameItem) {
      buttonText = 'Add More';
    } else {
      buttonText = 'Replace';
    }

    onPressed = canEquip
        ? () {
            context.dispatch(EquipGearAction(item: itemToEquip, slot: slot));
            Navigator.of(context).pop();
          }
        : null;

    return Row(
      children: [
        // Slot icon/status
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Style.cellBackgroundColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Style.cellBorderColor),
          ),
          child: isEmpty
              ? const Center(
                  child: Icon(Icons.add, color: Colors.grey, size: 24),
                )
              : Center(child: ItemImage(item: equippedItem!, size: 36)),
        ),
        const SizedBox(width: 12),
        // Slot info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slotName,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (isEmpty)
                Text(
                  'Empty',
                  style: TextStyle(color: Style.textColorMuted, fontSize: 12),
                )
              else
                Text(
                  '${equippedItem!.name} x$equippedCount',
                  style: TextStyle(color: Style.textColorInfo, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Action button
        ElevatedButton(onPressed: onPressed, child: Text(buttonText)),
      ],
    );
  }
}

/// Displays unmet equipment requirements with a similar style to shop
/// requirements.
class _EquipRequirementsDisplay extends StatelessWidget {
  const _EquipRequirementsDisplay({required this.requirements});

  final List<ShopRequirement> requirements;

  @override
  Widget build(BuildContext context) {
    final color = Style.unmetRequirementColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Requirements not met:',
          style: TextStyle(color: color, fontSize: 12),
        ),
        const SizedBox(height: 4),
        ...requirements.map((req) {
          if (req is SkillLevelRequirement) {
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CachedImage(assetPath: req.skill.assetPath, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Level ${req.level}',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
            );
          } else {
            // Fallback for other requirement types
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                'Unknown requirement',
                style: TextStyle(color: color, fontSize: 12),
              ),
            );
          }
        }),
      ],
    );
  }
}

class _SellConfirmationDialog extends StatelessWidget {
  const _SellConfirmationDialog({required this.stacks});

  final List<ItemStack> stacks;

  @override
  Widget build(BuildContext context) {
    final grandTotal = stacks.fold(0, (sum, stack) => sum + stack.sellsFor);

    return AlertDialog(
      title: const Text('Confirm Sale'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selling ${stacks.length} '
              'item${stacks.length == 1 ? '' : ' types'}:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stacks.length,
                itemBuilder: (context, index) {
                  final stack = stacks[index];
                  final unitPrice = stack.item.sellsFor;
                  final lineTotal = stack.sellsFor;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        ItemImage(item: stack.item, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stack.item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'x${approximateCountString(stack.count)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '@${approximateCountString(unitPrice)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Style.textColorMuted),
                        ),
                        const SizedBox(width: 8),
                        CurrencyDisplay(
                          currency: Currency.gp,
                          amount: lineTotal,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Total: ', style: Theme.of(context).textTheme.titleMedium),
                CurrencyDisplay(currency: Currency.gp, amount: grandTotal),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirm Sell'),
        ),
      ],
    );
  }
}

class _ClaimMasteryTokenSection extends StatefulWidget {
  const _ClaimMasteryTokenSection({required this.item, required this.maxCount});

  final Item item;
  final int maxCount;

  @override
  State<_ClaimMasteryTokenSection> createState() =>
      _ClaimMasteryTokenSectionState();
}

class _ClaimMasteryTokenSectionState extends State<_ClaimMasteryTokenSection> {
  double _claimCount = 1;

  @override
  void initState() {
    super.initState();
    _claimCount = widget.maxCount.toDouble();
  }

  @override
  void didUpdateWidget(_ClaimMasteryTokenSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxCount != widget.maxCount) {
      if (_claimCount > widget.maxCount) {
        setState(() {
          _claimCount = widget.maxCount > 0 ? widget.maxCount.toDouble() : 1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skill = Skill.fromId(widget.item.masteryTokenSkillId!);

    final state = context.state;
    final maxPoolXp = maxMasteryPoolXpForSkill(state.registries, skill);
    final currentPoolXp = state.skillState(skill).masteryPoolXp;
    final xpPerToken = state.masteryTokenXpPerClaim(skill);
    final claimable = state.claimableMasteryTokenCount(skill);
    final poolFull = currentPoolXp >= maxPoolXp;
    final maxClaim = claimable.clamp(1, widget.maxCount);
    final claimCountInt = _claimCount.round().clamp(1, maxClaim);
    final totalXp = xpPerToken * claimCountInt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Claim Mastery Token',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Adds ${preciseNumberString(xpPerToken)} XP per token to '
          '${skill.name} mastery pool '
          '(${preciseNumberString(currentPoolXp)}'
          ' / ${preciseNumberString(maxPoolXp)})',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (poolFull)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Mastery pool is full',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Quantity: ${approximateCountString(claimCountInt)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Slider(
          value: _claimCount.clamp(1, widget.maxCount.toDouble()),
          min: 1,
          max: widget.maxCount > 0 ? widget.maxCount.toDouble() : 1.0,
          divisions: widget.maxCount > 1 ? widget.maxCount - 1 : null,
          label: preciseNumberString(claimCountInt),
          onChanged: widget.maxCount > 0
              ? (value) {
                  setState(() {
                    _claimCount = value;
                  });
                }
              : null,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: claimable > 0 && claimCountInt > 0
                ? () {
                    context.dispatch(
                      ClaimMasteryTokensAction(
                        skill: skill,
                        count: claimCountInt,
                      ),
                    );
                    Navigator.of(context).pop();
                  }
                : null,
            child: const Text('Claim'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Total XP: ${preciseNumberString(totalXp)}',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _UpgradeSection extends StatefulWidget {
  const _UpgradeSection({required this.item});

  final Item item;

  @override
  State<_UpgradeSection> createState() => _UpgradeSectionState();
}

class _UpgradeSectionState extends State<_UpgradeSection> {
  ItemUpgrade? _selectedUpgrade;
  double _upgradeCount = 1;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final upgrades = state.registries.itemUpgrades.upgradesForItem(
      widget.item.id,
    );

    if (upgrades.isEmpty) return const SizedBox.shrink();

    // If only one upgrade, auto-select it
    final upgrade =
        _selectedUpgrade ?? (upgrades.length == 1 ? upgrades.first : null);

    // Show upgrade picker if multiple upgrades available and none selected
    if (upgrade == null && upgrades.length > 1) {
      return _buildUpgradePicker(context, upgrades);
    }

    if (upgrade == null) return const SizedBox.shrink();

    final maxAffordable = state.maxAffordableUpgrades(upgrade);
    final upgradeCountInt = _upgradeCount.round().clamp(0, maxAffordable);
    final outputItem = state.registries.items.byId(upgrade.upgradedItemId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upgrade Item', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        // Show what we're upgrading to
        Row(
          children: [
            ItemImage(item: outputItem),
            const SizedBox(width: 8),
            Expanded(child: Text(outputItem.name)),
          ],
        ),
        const SizedBox(height: 8),
        // Show costs
        _buildCostDisplay(context, upgrade, upgradeCountInt),
        const SizedBox(height: 16),
        // Quantity slider (only if max > 1)
        if (maxAffordable > 1) ...[
          Text(
            'Quantity: ${approximateCountString(upgradeCountInt)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Slider(
            value: _upgradeCount.clamp(1, maxAffordable.toDouble()),
            min: 1,
            max: maxAffordable.toDouble(),
            divisions: maxAffordable > 1 ? maxAffordable - 1 : null,
            label: preciseNumberString(upgradeCountInt),
            onChanged: (v) => setState(() => _upgradeCount = v),
          ),
          const SizedBox(height: 16),
        ],
        // Upgrade button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: maxAffordable > 0
                ? () {
                    context.dispatch(
                      UpgradeItemAction(
                        upgrade: upgrade,
                        count: upgradeCountInt,
                      ),
                    );
                    Navigator.of(context).pop();
                  }
                : null,
            child: Text(
              upgradeCountInt > 1
                  ? 'Upgrade x${approximateCountString(upgradeCountInt)}'
                  : 'Upgrade',
            ),
          ),
        ),
        // Show if multiple upgrades available
        if (upgrades.length > 1) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _selectedUpgrade = null),
            child: const Text('Choose different upgrade'),
          ),
        ],
      ],
    );
  }

  Widget _buildUpgradePicker(BuildContext context, List<ItemUpgrade> upgrades) {
    final state = context.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upgrade Item', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Choose an upgrade:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ...upgrades.map((upgrade) {
          final outputItem = state.registries.items.byId(
            upgrade.upgradedItemId,
          );
          final maxAffordable = state.maxAffordableUpgrades(upgrade);
          return ListTile(
            leading: ItemImage(item: outputItem),
            title: Text(outputItem.name),
            subtitle: Text(
              maxAffordable > 0
                  ? 'Can make: ${approximateCountString(maxAffordable)}'
                  : 'Cannot afford',
            ),
            enabled: maxAffordable > 0,
            onTap: () => setState(() {
              _selectedUpgrade = upgrade;
              _upgradeCount = 1;
            }),
          );
        }),
      ],
    );
  }

  Widget _buildCostDisplay(
    BuildContext context,
    ItemUpgrade upgrade,
    int count,
  ) {
    final state = context.state;
    final costs = <Widget>[];

    // Item costs
    for (final cost in upgrade.itemCosts) {
      final item = state.registries.items.byId(cost.itemId);
      final required = cost.quantity * count;
      final available = state.inventory.countById(cost.itemId);
      final canAfford = available >= required;

      costs.add(
        Row(
          children: [
            ItemImage(item: item, size: 24),
            const SizedBox(width: 8),
            Text(
              '${approximateCountString(required)} ${item.name}',
              style: TextStyle(
                color: canAfford ? null : Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(have ${approximateCountString(available)})',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Style.textColorMuted),
            ),
          ],
        ),
      );
    }

    // Currency costs
    final gpCost = upgrade.currencyCosts.gpCost * count;
    if (gpCost > 0) {
      final canAfford = state.gp >= gpCost;
      costs.add(
        Row(
          children: [
            CurrencyDisplay(
              currency: Currency.gp,
              amount: gpCost,
              canAfford: canAfford,
              size: 24,
            ),
            const SizedBox(width: 4),
            Text(
              '(have ${approximateCreditString(state.gp)})',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Style.textColorMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cost:', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        ...costs,
      ],
    );
  }
}

/// Displays an item's modifiers as formatted text.
class _ItemModifiersDisplay extends StatelessWidget {
  const _ItemModifiersDisplay({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final registry = context.state.registries.modifierMetadata;
    final descriptions = _formatModifiers(item, registry);

    if (descriptions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final desc in descriptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              desc,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Style.textColorSuccess),
            ),
          ),
      ],
    );
  }

  List<String> _formatModifiers(Item item, ModifierMetadataRegistry registry) {
    final descriptions = <String>[];

    for (final mod in item.modifiers.modifiers) {
      for (final entry in mod.entries) {
        // Extract scope information for formatting
        String? skillName;
        String? currencyName;
        final scope = entry.scope;
        if (scope != null) {
          if (scope.skillId != null) {
            skillName = Skill.fromId(scope.skillId!).name;
          }
          if (scope.currencyId != null) {
            currencyName = Currency.fromId(scope.currencyId!).name;
          }
        }

        descriptions.add(
          registry.formatDescription(
            name: mod.name,
            value: entry.value,
            skillName: skillName,
            currencyName: currencyName,
          ),
        );
      }
    }

    return descriptions;
  }
}
