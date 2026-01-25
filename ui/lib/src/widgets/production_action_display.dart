import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/count_badge_cell.dart';
import 'package:ui/src/widgets/double_chance_badge_cell.dart';
import 'package:ui/src/widgets/duration_badge_cell.dart';
import 'package:ui/src/widgets/item_count_badge_cell.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/recycle_chance_badge_cell.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';
import 'package:ui/src/widgets/xp_badges_row.dart';

/// A generic action display widget for production-based skills.
///
/// Supports smithing, fletching, crafting, runecrafting, herblore, and
/// summoning.
///
/// Layout:
/// - Row 1: 1/3 product icon with count, 2/3 "Action\nName" + effect + badges
/// - Row 2: Mastery progress bar
/// - Row 3: Recipe selector (if action has alternative recipes)
/// - Row 4: Two columns - "Requires:" with items | "You Have:" with items
/// - Row 5: Two columns - "Produces:" with items | "Grants:" with XP badges
/// - Row 6: Action button with duration badge
class ProductionActionDisplay extends StatelessWidget {
  const ProductionActionDisplay({
    required this.action,
    required this.productId,
    required this.skill,
    required this.onStart,
    required this.headerText,
    required this.buttonText,
    required this.showRecycleBadge,
    this.skillLevel,
    this.effectText,
    this.onInputItemTap,
    super.key,
  });

  final SkillAction action;
  final MelvorId productId;
  final Skill skill;
  final VoidCallback onStart;
  final String headerText;
  final String buttonText;
  final bool showRecycleBadge;
  final int? skillLevel;

  /// Optional effect text shown below the action name (e.g., for summoning).
  final String? effectText;

  /// Optional callback when an input item is tapped
  /// (e.g., for purchase dialog).
  final void Function(Item item)? onInputItemTap;

  bool get _isUnlocked =>
      skillLevel == null || skillLevel! >= action.unlockLevel;

  @override
  Widget build(BuildContext context) {
    if (!_isUnlocked) {
      return _buildLocked(context);
    }
    return _buildUnlocked(context);
  }

  Widget _buildLocked(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColorLocked,
        border: Border.all(color: Style.textColorSecondary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, size: 48, color: Style.textColorSecondary),
          const SizedBox(height: 8),
          Text(
            action.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Unlocked at '),
              SkillImage(skill: skill, size: 16),
              Text(' Level ${action.unlockLevel}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnlocked(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(action.id);
    final selection = actionState.recipeSelection(action);
    final isActive = state.isActionActive(action);
    final canStart = state.canStartAction(action);

    // Use recipe-specific inputs/outputs when action has alternatives
    final inputs = action.inputsForRecipe(selection);
    final outputs = action.outputsForRecipe(selection);

    // Get product for the icon
    final productItem = state.registries.items.byId(productId);
    final inventoryCount = state.inventory.countOfItem(productItem);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? Style.activeColorLight
            : Style.containerBackgroundLight,
        border: Border.all(
          color: isActive ? Style.activeColor : Style.iconColorDefault,
          width: isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Product icon (1/3) | Name + effect + badges (2/3)
          _buildHeaderRow(context, productItem, inventoryCount),
          const SizedBox(height: 12),

          // Row 2: Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          // Row 3: Recipe selector (if action has alternative recipes)
          if (selection case SelectedRecipe(:final index)) ...[
            _RecipeSelector(
              action: action,
              selectedIndex: index,
              itemRegistry: state.registries.items,
              onItemTap: onInputItemTap,
            ),
            const SizedBox(height: 12),
          ],

          // Row 4: Requires | You Have
          _buildRequiresHaveRow(context, inputs),
          const SizedBox(height: 12),

          // Row 5: Produces | Grants
          _buildProducesGrantsRow(context, outputs),
          const SizedBox(height: 16),

          // Row 6: Action button with duration
          _buildButtonRow(context, isActive, canStart),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context,
    Item productItem,
    int inventoryCount,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed-size product icon with count badge
        CountBadgeCell(
          count: inventoryCount > 0 ? inventoryCount : null,
          inradius: 64,
          child: CachedImage(assetPath: productItem.media ?? '', size: 40),
        ),
        const SizedBox(width: 12),
        // Name, effect text, and badges take remaining space
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerText,
                style: const TextStyle(
                  fontSize: 14,
                  color: Style.textColorSecondary,
                ),
              ),
              Text(
                action.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Effect text (e.g., for summoning familiars)
              if (effectText != null) ...[
                const SizedBox(height: 4),
                Text(
                  effectText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Style.textColorSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (showRecycleBadge) ...[
                    const RecycleChanceBadgeCell(chance: '0%'),
                    const SizedBox(width: 16),
                  ],
                  const DoubleChanceBadgeCell(chance: '0%'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRequiresHaveRow(
    BuildContext context,
    Map<MelvorId, int> inputs,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Requires
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Requires:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (inputs.isEmpty)
                const Text(
                  'None',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                ItemCountBadgesRow.required(
                  items: inputs,
                  onItemTap: onInputItemTap,
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right column: You Have
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You Have:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (inputs.isEmpty)
                const Text(
                  'N/A',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                ItemCountBadgesRow.inventory(
                  items: inputs,
                  onItemTap: onInputItemTap,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProducesGrantsRow(
    BuildContext context,
    Map<MelvorId, int> outputs,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Produces
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Produces:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (outputs.isEmpty)
                const Text(
                  'None',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                ItemCountBadgesRow.required(items: outputs),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right column: Grants
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Grants:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              XpBadgesRow(action: action),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtonRow(BuildContext context, bool isActive, bool canStart) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: canStart || isActive ? onStart : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? Style.activeColor : null,
          ),
          child: Text(isActive ? 'Stop' : buttonText),
        ),
        const SizedBox(width: 16),
        DurationBadgeCell(seconds: action.minDuration.inSeconds),
      ],
    );
  }
}

/// A dropdown widget for selecting between alternative recipes.
class _RecipeSelector extends StatelessWidget {
  const _RecipeSelector({
    required this.action,
    required this.selectedIndex,
    required this.itemRegistry,
    this.onItemTap,
  });

  final SkillAction action;
  final int selectedIndex;
  final ItemRegistry itemRegistry;
  final void Function(Item item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    final recipes = action.alternativeRecipes!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recipe:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        DropdownButton<int>(
          value: selectedIndex,
          isExpanded: true,
          items: List.generate(recipes.length, (index) {
            final recipe = recipes[index];
            return DropdownMenuItem(
              value: index,
              child: _RecipeOption(
                recipe: recipe,
                itemRegistry: itemRegistry,
                onItemTap: onItemTap,
              ),
            );
          }),
          onChanged: (newIndex) {
            if (newIndex != null && newIndex != selectedIndex) {
              context.dispatch(
                SetRecipeAction(actionId: action.id, recipeIndex: newIndex),
              );
            }
          },
        ),
      ],
    );
  }
}

/// A single recipe option showing item badges with inventory status.
class _RecipeOption extends StatelessWidget {
  const _RecipeOption({
    required this.recipe,
    required this.itemRegistry,
    this.onItemTap,
  });

  final AlternativeRecipe recipe;
  final ItemRegistry itemRegistry;
  final void Function(Item item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    if (recipe.inputs.isEmpty) {
      return const Text('Unknown');
    }

    final state = context.state;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show item badges for inputs with inventory status
        ...recipe.inputs.entries.map((entry) {
          final item = itemRegistry.byId(entry.key);
          final requiredCount = entry.value;
          final inventoryCount = state.inventory.countOfItem(item);
          final hasEnough = inventoryCount >= requiredCount;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: onItemTap != null ? () => onItemTap!(item) : null,
              child: ItemCountBadgeCell(
                item: item,
                count: requiredCount,
                hasEnough: hasEnough,
                inradius: 24,
              ),
            ),
          );
        }),
      ],
    );
  }
}
