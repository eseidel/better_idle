import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/double_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/recycle_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

/// Configuration for badge display in the action display.
enum BadgeStyle {
  /// No badges (e.g., Fishing, Cooking)
  none,

  /// Only double chance badge (e.g., Herblore, Runecrafting)
  doubleOnly,

  /// Both recycle and double chance badges
  /// (e.g., Smithing, Crafting, Fletching)
  recycleAndDouble,
}

/// A widget that displays a selected skill action's details.
///
/// This is a shared widget used by multiple skill screens (Smithing, Crafting,
/// Herblore, Runecrafting, Fletching, Cooking, Fishing) to display the
/// selected action's details including:
/// - Locked/unlocked state
/// - Action header (verb + name)
/// - Mastery progress
/// - Required inputs
/// - Produced outputs
/// - XP grants
/// - Duration
/// - Start/Stop button
class SkillActionDisplay extends StatelessWidget {
  const SkillActionDisplay({
    required this.action,
    required this.onStart,
    this.skill,
    this.skillLevel,
    this.headerText = 'Action',
    this.buttonText = 'Start',
    this.badgeStyle = BadgeStyle.none,
    this.showInputsOutputs = true,
    this.additionalContent,
    this.durationBuilder,
    this.productId,
    this.onInputItemTap,
    super.key,
  });

  final SkillAction action;
  final VoidCallback onStart;

  /// The skill for showing lock icons. If null, action is always unlocked.
  final Skill? skill;

  /// The current skill level. If null, action is always unlocked.
  final int? skillLevel;

  /// Header text shown above the action name (e.g., "Create", "Cook", "Brew").
  final String headerText;

  /// The button text when not active (e.g., "Create", "Cook", "Brew", "Fish").
  final String buttonText;

  /// What style of badges to show (recycle/double chance).
  final BadgeStyle badgeStyle;

  /// Whether to show inputs/outputs sections.
  final bool showInputsOutputs;

  /// Additional content to show after the outputs section.
  final Widget? additionalContent;

  /// Custom duration builder. If null, shows default duration.
  final Widget Function(SkillAction action)? durationBuilder;

  /// The product item ID to show with inventory count badge in the header.
  /// If null, no product icon is shown.
  final MelvorId? productId;

  /// Callback when an input item is tapped. Used to show purchase dialogs.
  final void Function(Item item)? onInputItemTap;

  bool get _isUnlocked =>
      skill == null || skillLevel == null || skillLevel! >= action.unlockLevel;

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
              SkillImage(skill: skill!, size: 16),
              Text(' Level ${action.unlockLevel}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, GlobalState state) {
    final headerColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headerText,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Style.textColorSecondary),
        ),
        Text(
          action.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );

    // If no productId, just show the centered header.
    if (productId == null) {
      return headerColumn;
    }

    // Show product icon with inventory count badge to the left.
    final productItem = state.registries.items.byId(productId!);
    final inventoryCount = state.inventory.countOfItem(productItem);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CountBadgeCell(
          count: inventoryCount > 0 ? inventoryCount : null,
          child: CachedImage(
            assetPath: productItem.media ?? '',
            size: TextBadgeCell.defaultInradius - 8,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: headerColumn),
        // Balance the layout with an invisible spacer.
        const SizedBox(width: TextBadgeCell.defaultInradius + 12),
      ],
    );
  }

  Widget _buildUnlocked(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(action.id);
    final selection = actionState.recipeSelection(action);
    final isActive = state.activeAction?.id == action.id;
    final canStart = state.canStartAction(action);

    // Get recipe-specific inputs and outputs
    final inputs = action.inputsForRecipe(selection);
    final outputs = action.outputsForRecipe(selection);

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
          // Header with optional product icon
          _buildHeader(context, state),
          const SizedBox(height: 12),

          // Badges
          if (badgeStyle != BadgeStyle.none) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (badgeStyle == BadgeStyle.recycleAndDouble) ...[
                  const RecycleChanceBadgeCell(chance: '0%'),
                  const SizedBox(width: 24),
                ],
                const DoubleChanceBadgeCell(chance: '0%'),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Recipe selector (if action has alternative recipes)
          if (selection case SelectedRecipe(:final index)) ...[
            _RecipeSelector(
              action: action,
              selectedIndex: index,
              itemRegistry: state.registries.items,
            ),
            const SizedBox(height: 12),
          ],

          // Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          if (showInputsOutputs) ...[
            // Requires section
            if (inputs.isNotEmpty) ...[
              const Text(
                'Requires:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ItemCountBadgesRow.required(
                items: inputs,
                onItemTap: onInputItemTap,
              ),
              const SizedBox(height: 8),

              // You Have section
              const Text(
                'You Have:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ItemCountBadgesRow.inventory(
                items: inputs,
                onItemTap: onInputItemTap,
              ),
              const SizedBox(height: 8),
            ],

            // Produces section
            if (outputs.isNotEmpty) ...[
              const Text(
                'Produces:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ItemCountBadgesRow.required(items: outputs),
              const SizedBox(height: 8),
            ],
          ],

          // Additional content (e.g., heals info for cooking)
          if (additionalContent != null) ...[
            additionalContent!,
            const SizedBox(height: 8),
          ],

          // Grants section
          const Text('Grants:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          XpBadgesRow(action: action),
          const SizedBox(height: 16),

          // Duration
          if (durationBuilder != null)
            durationBuilder!(action)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.access_time, size: 16),
                const SizedBox(width: 4),
                Text('${action.minDuration.inSeconds}s'),
              ],
            ),
          const SizedBox(height: 8),

          // Action button
          ElevatedButton(
            onPressed: canStart || isActive ? onStart : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Style.activeColor : null,
            ),
            child: Text(isActive ? 'Stop' : buttonText),
          ),
        ],
      ),
    );
  }
}

/// A dropdown widget for selecting between alternative recipes.
class _RecipeSelector extends StatelessWidget {
  const _RecipeSelector({
    required this.action,
    required this.selectedIndex,
    required this.itemRegistry,
  });

  final SkillAction action;
  final int selectedIndex;
  final ItemRegistry itemRegistry;

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
              child: _RecipeOption(recipe: recipe, itemRegistry: itemRegistry),
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
  const _RecipeOption({required this.recipe, required this.itemRegistry});

  final AlternativeRecipe recipe;
  final ItemRegistry itemRegistry;

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
            child: ItemCountBadgeCell(
              item: item,
              count: requiredCount,
              hasEnough: hasEnough,
              inradius: 24,
            ),
          );
        }),
      ],
    );
  }
}
