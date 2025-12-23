import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/services/toast_service.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A grid widget that displays all items in the game.
/// Clicking an item adds it to the player's inventory.
class ItemCatalogGrid extends StatelessWidget {
  const ItemCatalogGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.state.registries.items.all;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 48,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ItemTile(item: item);
      },
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.name,
      child: Material(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            final state = context.state;
            if (!state.inventory.canAdd(
              item,
              capacity: state.inventoryCapacity,
            )) {
              toastService.showError('Inventory full');
              return;
            }
            context.dispatch(DebugAddItemAction(item: item));
            final stack = ItemStack(item, count: 1);
            toastService.showToast(const Changes.empty().adding(stack));
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: ItemImage(item: item),
          ),
        ),
      ),
    );
  }
}
