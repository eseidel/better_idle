import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/cost_row.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/style.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final Set<String> _collapsedCategories = {};
  bool _showAffordableOnly = false;

  bool _canPurchase(ShopViewModel viewModel, ShopPurchase purchase) {
    final unmetRequirements = viewModel.unmetRequirements(purchase);
    if (unmetRequirements.isNotEmpty) return false;
    return viewModel._state.canAffordShopPurchase(purchase);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: const Text('Shop'),
      actions: [
        IconButton(
          icon: Icon(
            _showAffordableOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
          ),
          tooltip: 'Show affordable only',
          onPressed: () {
            setState(() {
              _showAffordableOnly = !_showAffordableOnly;
            });
          },
        ),
      ],
      body: StoreConnector<GlobalState, ShopViewModel>(
        converter: (store) => ShopViewModel(store.state),
        builder: (context, viewModel) {
          return ListView(children: _buildCategoryRows(context, viewModel));
        },
      ),
    );
  }

  List<Widget> _buildCategoryRows(
    BuildContext context,
    ShopViewModel viewModel,
  ) {
    final rows = <Widget>[];
    final purchasesByCategory = viewModel.purchasesByCategory;

    for (final entry in purchasesByCategory.entries) {
      final category = entry.key;
      var purchases = entry.value;

      if (_showAffordableOnly) {
        purchases = purchases.where((p) => _canPurchase(viewModel, p)).toList();
        if (purchases.isEmpty) continue;
      }

      final isCollapsed = _collapsedCategories.contains(category.id.toJson());

      // Category header
      rows.add(
        InkWell(
          onTap: () {
            setState(() {
              final categoryId = category.id.toJson();
              if (_collapsedCategories.contains(categoryId)) {
                _collapsedCategories.remove(categoryId);
              } else {
                _collapsedCategories.add(categoryId);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Style.categoryHeaderColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Icon(
                  isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                  size: 24,
                ),
                const SizedBox(width: 8),
                if (category.media != null)
                  CachedImage(assetPath: category.media, size: 20)
                else
                  const Icon(Icons.category, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${purchases.length} items',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );

      // Items in category (if not collapsed)
      if (!isCollapsed) {
        rows.addAll(
          _buildPurchaseRowsForCategory(context, viewModel, purchases),
        );
      }
    }

    return rows;
  }

  List<Widget> _buildPurchaseRowsForCategory(
    BuildContext context,
    ShopViewModel viewModel,
    List<ShopPurchase> purchases,
  ) {
    final rows = <Widget>[];

    for (final purchase in purchases) {
      final unmetRequirements = viewModel.unmetRequirements(purchase);
      final meetsAllReqs = unmetRequirements.isEmpty;

      final resolved = viewModel._state.resolveShopCost(purchase);
      final canPurchase = meetsAllReqs && resolved.canAfford;

      // Build description from purchase
      final descriptionSpan = _buildDescriptionSpan(purchase, viewModel);

      rows.add(
        _ShopItemRow(
          media: purchase.media,
          name: purchase.name,
          resolvedCost: resolved,
          descriptionSpan: descriptionSpan,
          unmetRequirements: unmetRequirements,
          dungeonRegistry: viewModel._state.registries.dungeons,
          onTap: canPurchase
              ? () {
                  final remaining = viewModel.remainingPurchases(purchase);
                  if (remaining > 1) {
                    _showBulkPurchaseDialog(
                      context,
                      viewModel: viewModel,
                      purchase: purchase,
                      descriptionSpan: descriptionSpan,
                    );
                  } else {
                    _showPurchaseDialog(
                      context,
                      name: purchase.name,
                      costWidget: CostRow.fromResolved(resolved),
                      descriptionSpan: descriptionSpan,
                      createAction: () =>
                          PurchaseShopItemAction(purchaseId: purchase.id),
                    );
                  }
                }
              : null,
        ),
      );
    }

    return rows;
  }

  /// Parses simple HTML in description text and converts to TextSpan.
  /// Handles:
  /// - <br> tags (line breaks)
  /// - <span class="text-warning"> tags (highlighted text in orange)
  InlineSpan _parseDescription(String description, {ShopPurchase? purchase}) {
    // First, substitute template variables like ${qty}, ${qty1}, ${qty2}, etc.
    var processedDescription = description;

    // Replace ${qty} with 1 (description shows per-unit values).
    processedDescription = processedDescription.replaceAll(r'${qty}', '1');

    if (purchase != null && purchase.contains.items.isNotEmpty) {
      for (var i = 0; i < purchase.contains.items.length; i++) {
        final quantity = purchase.contains.items[i].quantity;
        final qtyVar = '\${qty${i + 1}}';
        processedDescription = processedDescription.replaceAll(
          qtyVar,
          quantity.toString(),
        );
      }
    }

    final spans = <InlineSpan>[];
    final regex = RegExp(
      r'<br\s*/?>|<span class="text-warning">(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );

    var lastEnd = 0;
    for (final match in regex.allMatches(processedDescription)) {
      // Add text before this match
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(text: processedDescription.substring(lastEnd, match.start)),
        );
      }

      // Handle the matched tag
      final matchedText = match.group(0)!.toLowerCase();
      if (matchedText.startsWith('<br')) {
        // Add a newline
        spans.add(const TextSpan(text: '\n'));
      } else if (matchedText.contains('text-warning')) {
        // Add warning text (group 1 contains the content)
        final warningText = match.group(1);
        if (warningText != null) {
          spans.add(
            TextSpan(
              text: warningText,
              style: const TextStyle(color: Colors.orange),
            ),
          );
        }
      }

      lastEnd = match.end;
    }

    // Add any remaining text after the last match
    if (lastEnd < processedDescription.length) {
      spans.add(TextSpan(text: processedDescription.substring(lastEnd)));
    }

    // If no spans were created, return a simple TextSpan
    if (spans.isEmpty) {
      return TextSpan(text: processedDescription);
    }

    // If only one span and it's plain text, return it directly
    if (spans.length == 1 && spans[0] is TextSpan) {
      return spans[0];
    }

    return TextSpan(children: spans);
  }

  InlineSpan? _buildDescriptionSpan(
    ShopPurchase purchase,
    ShopViewModel viewModel,
  ) {
    // Prefer custom description if available
    // (e.g., Magic Pot has detailed modifier info)
    if (purchase.description != null) {
      return _parseDescription(purchase.description!, purchase: purchase);
    }

    // Handle itemCharges purchases
    final itemCharges = purchase.contains.itemCharges;
    if (itemCharges != null) {
      final item = viewModel.itemById(itemCharges.itemId);
      final chargeCount = itemCharges.quantity;
      final itemDescription = item.description ?? item.name;

      return TextSpan(text: '+$chargeCount charges: $itemDescription');
    }

    // Otherwise build description from modifiers we understand
    final parts = <String>[];

    // Add skill interval modifiers
    final modifiers = purchase.contains.modifiers;
    for (final skillId in modifiers.skillIntervalSkillIds) {
      final skill = Skill.fromId(skillId);
      final value = modifiers.skillIntervalForSkill(skillId);
      final percent = value < 0 ? '$value%' : '+$value%';
      parts.add('$percent ${skill.name} time');
    }

    // Add bank space
    final bankSpace = purchase.contains.bankSpace;
    if (bankSpace != null) {
      parts.add('+$bankSpace bank space');
    }

    // If no auto-generated description, check if purchase contains a single
    // item with a custom description (e.g., Feathers)
    if (parts.isEmpty && purchase.contains.items.length == 1) {
      final itemId = purchase.contains.items.first.itemId;
      final item = viewModel.itemById(itemId);
      if (item.description != null) {
        return _parseDescription(item.description!);
      }
    }

    if (parts.isEmpty) return null;
    return TextSpan(text: parts.join(', '));
  }

  void _showBulkPurchaseDialog(
    BuildContext context, {
    required ShopViewModel viewModel,
    required ShopPurchase purchase,
    InlineSpan? descriptionSpan,
  }) {
    final maxAffordable = viewModel.maxAffordable(purchase);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _BulkPurchaseDialog(
        purchase: purchase,
        maxAffordable: maxAffordable,
        descriptionSpan: descriptionSpan,
        onConfirm: (int quantity) {
          try {
            context.dispatch(
              PurchaseShopItemAction(purchaseId: purchase.id, count: quantity),
            );
            Navigator.of(dialogContext).pop();
          } on Exception catch (e) {
            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(e.toString())));
          }
        },
      ),
    );
  }

  void _showPurchaseDialog(
    BuildContext context, {
    required String name,
    required Widget costWidget,
    required ReduxAction<GlobalState> Function() createAction,
    InlineSpan? descriptionSpan,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Purchase $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Purchase $name for '),
                costWidget,
                const Text('?'),
              ],
            ),
            if (descriptionSpan != null) ...[
              const SizedBox(height: 8),
              Text.rich(
                descriptionSpan,
                style: const TextStyle(color: Style.successColor),
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
            onPressed: () {
              try {
                context.dispatch(createAction());
                Navigator.of(dialogContext).pop();
              } on Exception catch (e) {
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
  const ShopViewModel(this._state);

  final GlobalState _state;

  int get gp => _state.gp;
  int get bankSlotsPurchased => _state.shop.bankSlotsPurchased;

  ShopRegistry get _shopRegistry => _state.registries.shop;

  /// Get all visible purchases that can be shown in the shop.
  List<ShopPurchase> get visiblePurchases =>
      _shopRegistry.visiblePurchases(_state.shop.purchaseCounts);

  /// Get visible purchases grouped by category.
  /// Returns a map with categories as keys, preserving category order.
  Map<ShopCategory, List<ShopPurchase>> get purchasesByCategory {
    final result = <ShopCategory, List<ShopPurchase>>{};
    final purchases = visiblePurchases;

    // Group purchases by category, maintaining category order
    for (final category in _shopRegistry.categories) {
      final categoryPurchases = purchases
          .where((p) => p.category == category.id)
          .toList();
      if (categoryPurchases.isNotEmpty) {
        result[category] = categoryPurchases;
      }
    }

    return result;
  }

  /// Get all requirements that the player doesn't meet.
  List<ShopRequirement> unmetRequirements(ShopPurchase purchase) {
    final unmet = <ShopRequirement>[];

    // Check all unlock and purchase requirements
    final allReqs = [
      ...purchase.unlockRequirements,
      ...purchase.purchaseRequirements,
    ];

    for (final req in allReqs) {
      if (!req.isMet(_state)) {
        unmet.add(req);
      }
    }

    return unmet;
  }

  /// Get the player's skill level for a skill.
  int skillLevel(Skill skill) => _state.skillState(skill).skillLevel;

  /// Returns the player's balance for a currency.
  int currencyBalance(Currency currency) => _state.currency(currency);

  /// Returns an item by its MelvorId.
  Item itemById(MelvorId id) => _state.registries.items.byId(id);

  /// Returns the player's count of an item in inventory.
  int itemCount(MelvorId itemId) {
    final item = _state.registries.items.byId(itemId);
    return _state.inventory.countOfItem(item);
  }

  /// Returns how many more times this purchase can be bought.
  /// Returns a large number for unlimited items.
  int remainingPurchases(ShopPurchase purchase) {
    if (purchase.isUnlimited) return 99999;
    return purchase.buyLimit - _state.shop.purchaseCount(purchase.id);
  }

  /// Calculate how many times the player can afford this purchase.
  int maxAffordable(ShopPurchase purchase) {
    if (purchase.cost.hasDynamicPricing) {
      return _maxAffordableDynamic(purchase);
    }

    final currencyCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: bankSlotsPurchased,
    );
    final itemCosts = purchase.cost.items;

    var max = 99999;

    for (final (currency, amount) in currencyCosts) {
      if (amount > 0) {
        max = math.min(max, currencyBalance(currency) ~/ amount);
      }
    }

    for (final cost in itemCosts) {
      if (cost.quantity > 0) {
        max = math.min(max, itemCount(cost.itemId) ~/ cost.quantity);
      }
    }

    return math.min(max, remainingPurchases(purchase)).clamp(0, 99999);
  }

  /// For dynamic pricing (bank slots), iterate to find max affordable.
  int _maxAffordableDynamic(ShopPurchase purchase) {
    var balance = _state.gp;
    var slots = bankSlotsPurchased;
    var count = 0;
    final remaining = remainingPurchases(purchase);
    while (count < remaining) {
      final cost = calculateBankSlotCost(slots);
      if (balance < cost) break;
      balance -= cost;
      slots++;
      count++;
    }
    return count;
  }
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.name,
    required this.resolvedCost,
    required this.dungeonRegistry,
    this.onTap,
    this.media,
    this.descriptionSpan,
    this.unmetRequirements = const [],
  });

  /// The asset path for the purchase icon.
  final String? media;

  final String name;

  /// Resolved cost with per-part affordability for display.
  final ResolvedShopCost resolvedCost;

  /// Called when tapped. Null if the item cannot be purchased.
  final VoidCallback? onTap;

  /// Optional description shown below the name (as rich text).
  final InlineSpan? descriptionSpan;

  /// Requirements the player hasn't met yet.
  final List<ShopRequirement> unmetRequirements;

  /// Registry for looking up dungeon data.
  final DungeonRegistry dungeonRegistry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (media != null)
              CachedImage(assetPath: media)
            else
              const Icon(Icons.shopping_cart, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  if (descriptionSpan != null) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      descriptionSpan!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (unmetRequirements.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildRequirementsRow(),
                  ],
                  const SizedBox(height: 4),
                  CostRow.fromResolved(resolvedCost),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementsRow() {
    final color = Style.unmetRequirementColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: unmetRequirements.map((req) {
        if (req is SkillLevelRequirement) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Requires ', style: TextStyle(color: color, fontSize: 12)),
              CachedImage(assetPath: req.skill.assetPath, size: 14),
              const SizedBox(width: 4),
              Text(
                'Level ${req.level}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          );
        } else if (req is DungeonCompletionRequirement) {
          // Look up dungeon from registry
          final dungeon = dungeonRegistry.byId(req.dungeonId);
          final dungeonName = dungeon.name;
          final completionText = req.count == 1 ? 'once' : '${req.count} times';

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Complete ', style: TextStyle(color: color, fontSize: 12)),
              if (dungeon.media != null) ...[
                CachedImage(assetPath: dungeon.media, size: 14),
                const SizedBox(width: 4),
              ],
              Text(
                '$dungeonName $completionText',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          );
        } else if (req is TownshipTaskRequirement) {
          final taskText = req.count == 1 ? 'task' : 'tasks';
          return Text(
            'Complete ${req.count} Township $taskText',
            style: TextStyle(color: color, fontSize: 12),
          );
        } else if (req is CompletionRequirement) {
          return Text(
            'Requires ${req.percent}% game completion',
            style: TextStyle(color: color, fontSize: 12),
          );
        } else if (req is SlayerTaskRequirement) {
          final categoryName = req.category.name.replaceAll('_', ' ');
          final taskText = req.count == 1 ? 'task' : 'tasks';
          return Text(
            'Complete ${req.count} $categoryName Slayer $taskText',
            style: TextStyle(color: color, fontSize: 12),
          );
        } else if (req is TownshipBuildingRequirement) {
          final buildingName = req.buildingId.name.replaceAll('_', ' ');
          final buildingText = req.count == 1 ? 'building' : 'buildings';
          return Text(
            'Build ${req.count} $buildingName $buildingText',
            style: TextStyle(color: color, fontSize: 12),
          );
        } else if (req is AllSkillLevelsRequirement) {
          return Text(
            'Requires all skills at level ${req.level}',
            style: TextStyle(color: color, fontSize: 12),
          );
        }
        // Unknown requirement type, skip it
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}

/// Dialog for purchasing multiple units of a shop item.
class _BulkPurchaseDialog extends StatefulWidget {
  const _BulkPurchaseDialog({
    required this.purchase,
    required this.maxAffordable,
    required this.onConfirm,
    this.descriptionSpan,
  });

  final ShopPurchase purchase;
  final int maxAffordable;
  final void Function(int quantity) onConfirm;
  final InlineSpan? descriptionSpan;

  @override
  State<_BulkPurchaseDialog> createState() => _BulkPurchaseDialogState();
}

class _BulkPurchaseDialogState extends State<_BulkPurchaseDialog> {
  int _selectedQuantity = 1;

  static const _presets = [1, 10, 100, 1000, 10000];

  List<(Currency, int)> _totalCurrencyCosts() {
    final state = context.state;
    final purchase = widget.purchase;

    if (purchase.cost.hasDynamicPricing) {
      // For dynamic pricing, sum individual costs.
      final slots = state.shop.bankSlotsPurchased;
      final total = List.generate(
        _selectedQuantity,
        (i) => calculateBankSlotCost(slots + i),
      ).fold(0, (a, b) => a + b);
      return [(Currency.gp, total)];
    }

    final baseCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: state.shop.bankSlotsPurchased,
    );
    return baseCosts.map((c) => (c.$1, c.$2 * _selectedQuantity)).toList();
  }

  List<(Item, int, bool)> _totalItemCosts() {
    final state = context.state;
    return widget.purchase.cost.items.map((cost) {
      final item = state.registries.items.byId(cost.itemId);
      final totalQty = cost.quantity * _selectedQuantity;
      final canAfford = state.inventory.countOfItem(item) >= totalQty;
      return (item, totalQty, canAfford);
    }).toList();
  }

  String _formatQuantity(int qty) {
    if (qty >= 1000) return '${qty ~/ 1000}k';
    return '$qty';
  }

  void _showCustomQuantityDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: InputDecoration(hintText: 'Max: ${widget.maxAffordable}'),
          onSubmitted: (value) {
            final qty = int.tryParse(value);
            if (qty != null && qty > 0 && qty <= widget.maxAffordable) {
              Navigator.of(dialogContext).pop();
              setState(() => _selectedQuantity = qty);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final qty = int.tryParse(controller.text);
              if (qty != null && qty > 0 && qty <= widget.maxAffordable) {
                Navigator.of(dialogContext).pop();
                setState(() => _selectedQuantity = qty);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availablePresets = _presets
        .where((q) => q <= widget.maxAffordable)
        .toList();

    return AlertDialog(
      title: Text('Purchase ${widget.purchase.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.descriptionSpan != null) ...[
            Text.rich(
              widget.descriptionSpan!,
              style: const TextStyle(color: Style.successColor),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'Quantity:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final qty in availablePresets)
                ChoiceChip(
                  label: Text(_formatQuantity(qty)),
                  selected: _selectedQuantity == qty,
                  onSelected: (_) => setState(() => _selectedQuantity = qty),
                ),
              if (widget.maxAffordable > 0 &&
                  (availablePresets.isEmpty ||
                      widget.maxAffordable != availablePresets.last))
                ChoiceChip(
                  label: Text('Max (${_formatQuantity(widget.maxAffordable)})'),
                  selected: _selectedQuantity == widget.maxAffordable,
                  onSelected: (_) =>
                      setState(() => _selectedQuantity = widget.maxAffordable),
                ),
              ActionChip(
                label: const Text('Custom'),
                onPressed: _showCustomQuantityDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Total cost:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          CostRow(
            currencyCosts: _totalCurrencyCosts(),
            itemCosts: _totalItemCosts(),
            showAffordability: false,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => widget.onConfirm(_selectedQuantity),
          child: Text('Buy ${_formatQuantity(_selectedQuantity)}'),
        ),
      ],
    );
  }
}
