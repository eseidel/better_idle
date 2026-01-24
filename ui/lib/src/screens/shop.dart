import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
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

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: const Text('Shop'),
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
      final purchases = entry.value;
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

      // Get all costs (handles both fixed and bank slot pricing)
      final currencyCosts = purchase.cost.currencyCosts(
        bankSlotsPurchased: viewModel.bankSlotsPurchased,
      );
      final itemCosts = purchase.cost.items;

      // Check if player can afford all currencies and items
      final canAffordCurrency = viewModel.canAffordCosts(currencyCosts);
      final canAffordItems = viewModel.canAffordItemCosts(itemCosts);
      final canPurchase = meetsAllReqs && canAffordCurrency && canAffordItems;

      // Build description from purchase
      final descriptionSpan = _buildDescriptionSpan(purchase, viewModel);

      // Resolve item costs to (Item, quantity, canAfford) tuples
      final resolvedItemCosts = itemCosts.map((cost) {
        final item = viewModel.itemById(cost.itemId);
        final canAfford = viewModel.itemCount(cost.itemId) >= cost.quantity;
        return (item, cost.quantity, canAfford);
      }).toList();

      rows.add(
        _ShopItemRow(
          media: purchase.media,
          name: purchase.name,
          currencyCosts: currencyCosts,
          canAffordCosts: viewModel.canAffordEachCost(currencyCosts),
          itemCosts: resolvedItemCosts,
          descriptionSpan: descriptionSpan,
          unmetRequirements: unmetRequirements,
          dungeonRegistry: viewModel._state.registries.dungeons,
          onTap: canPurchase
              ? () => _showPurchaseDialog(
                  context,
                  name: purchase.name,
                  costWidget: _buildCostWidget(
                    currencyCosts,
                    resolvedItemCosts,
                  ),
                  descriptionSpan: descriptionSpan,
                  createAction: () =>
                      PurchaseShopItemAction(purchaseId: purchase.id),
                )
              : null,
        ),
      );
    }

    return rows;
  }

  Widget _buildCostWidget(
    List<(Currency, int)> currencyCosts,
    List<(Item, int, bool)> itemCosts,
  ) {
    final widgets = <Widget>[];

    // Add currency costs
    for (final (currency, amount) in currencyCosts) {
      widgets.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedImage(assetPath: currency.assetPath, size: 16),
            const SizedBox(width: 4),
            Text(approximateCreditString(amount)),
          ],
        ),
      );
    }

    // Add item costs
    for (final (item, quantity, _) in itemCosts) {
      widgets.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.media != null)
              CachedImage(assetPath: item.media, size: 16)
            else
              const Icon(Icons.inventory_2, size: 16),
            const SizedBox(width: 4),
            Text('$quantity'),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }

  /// Parses simple HTML in description text and converts to TextSpan.
  /// Handles:
  /// - <br> tags (line breaks)
  /// - <span class="text-warning"> tags (highlighted text in orange)
  InlineSpan _parseDescription(String description, {ShopPurchase? purchase}) {
    // First, substitute template variables like ${qty}, ${qty1}, ${qty2}, etc.
    var processedDescription = description;

    // TODO(eseidel): Consider adding a quantity selector.
    // Replace ${qty} with 1 (we always purchase quantity 1, no qty selector)
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

  /// Returns true if the player can afford all the given currency costs.
  bool canAffordCosts(List<(Currency, int)> costs) {
    for (final (currency, amount) in costs) {
      if (currencyBalance(currency) < amount) {
        return false;
      }
    }
    return true;
  }

  /// Returns a map of currency to whether the player can afford that cost.
  Map<Currency, bool> canAffordEachCost(List<(Currency, int)> costs) {
    final result = <Currency, bool>{};
    for (final (currency, amount) in costs) {
      result[currency] = currencyBalance(currency) >= amount;
    }
    return result;
  }

  /// Returns an item by its MelvorId.
  Item itemById(MelvorId id) => _state.registries.items.byId(id);

  /// Returns the player's count of an item in inventory.
  int itemCount(MelvorId itemId) {
    final item = _state.registries.items.byId(itemId);
    return _state.inventory.countOfItem(item);
  }

  /// Returns true if the player can afford all the given item costs.
  bool canAffordItemCosts(List<ItemCost> costs) {
    for (final cost in costs) {
      if (itemCount(cost.itemId) < cost.quantity) {
        return false;
      }
    }
    return true;
  }

  /// Returns a map of itemId to whether the player can afford that cost.
  Map<MelvorId, bool> canAffordEachItemCost(List<ItemCost> costs) {
    final result = <MelvorId, bool>{};
    for (final cost in costs) {
      result[cost.itemId] = itemCount(cost.itemId) >= cost.quantity;
    }
    return result;
  }
}

class _ShopItemRow extends StatelessWidget {
  const _ShopItemRow({
    required this.name,
    required this.currencyCosts,
    required this.canAffordCosts,
    required this.itemCosts,
    required this.dungeonRegistry,
    this.onTap,
    this.media,
    this.descriptionSpan,
    this.unmetRequirements = const [],
  });

  /// The asset path for the purchase icon.
  final String? media;

  final String name;

  /// List of (currency, amount) pairs for this purchase.
  final List<(Currency, int)> currencyCosts;

  /// Map of currency to whether the player can afford that cost.
  final Map<Currency, bool> canAffordCosts;

  /// List of item costs for this purchase, with resolved item data.
  final List<(Item, int, bool)> itemCosts; // (item, quantity, canAfford)

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
                  CostRow(
                    currencyCosts: currencyCosts,
                    canAffordCosts: canAffordCosts,
                    itemCosts: itemCosts,
                  ),
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
