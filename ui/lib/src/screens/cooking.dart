import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/double_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/duration_badge_cell.dart';
import 'package:better_idle/src/widgets/game_scaffold.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/recycle_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class CookingPage extends StatelessWidget {
  const CookingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.cooking;
    final state = context.state;
    final skillState = state.skillState(skill);

    return GameScaffold(
      title: const Text('Cooking'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SkillProgress(xp: skillState.xp),
            MasteryPoolProgress(xp: skillState.masteryPoolXp),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MasteryUnlocksButton(skill: skill),
                SkillMilestonesButton(skill: skill),
              ],
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _CookingAreaCard(area: CookingArea.fire),
                _CookingAreaCard(area: CookingArea.furnace),
                _CookingAreaCard(area: CookingArea.pot),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CookingAreaCard extends StatefulWidget {
  const _CookingAreaCard({required this.area});

  final CookingArea area;

  /// Maximum width for each cooking area card.
  static const double maxWidth = 400;

  @override
  State<_CookingAreaCard> createState() => _CookingAreaCardState();
}

class _CookingAreaCardState extends State<_CookingAreaCard> {
  CookingArea get area => widget.area;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final skillLevel = state.skillState(Skill.cooking).skillLevel;
    final areaState = state.cooking.areaState(area);

    // Get recipes for this area, sorted by level
    final recipes =
        state.registries.cooking.actions
            .where((a) => a.categoryId?.localId == area.name.capitalize())
            .toList()
          ..sort(
            (CookingAction a, CookingAction b) =>
                a.unlockLevel.compareTo(b.unlockLevel),
          );

    // Get unlocked recipes
    final unlockedRecipes = recipes
        .where((CookingAction r) => skillLevel >= r.unlockLevel)
        .toList();

    // Auto-select the first unlocked recipe if none is selected
    if (areaState.recipeId == null && unlockedRecipes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.dispatch(
          AssignCookingRecipeAction(area: area, recipe: unlockedRecipes.first),
        );
      });
    }

    // Get the currently assigned recipe
    final assignedRecipe = areaState.recipeId != null
        ? recipes.firstWhere(
            (CookingAction r) => r.id == areaState.recipeId,
            orElse: () => recipes.first,
          )
        : null;

    // Check if this area is actively cooking
    final activeActionId = state.currentActionId;
    CookingAction? activeCookingAction;
    if (activeActionId != null) {
      final action = state.registries.actionById(activeActionId);
      if (action is CookingAction) {
        activeCookingAction = action;
      }
    }
    final isActivelyCooking =
        activeCookingAction != null &&
        activeCookingAction.categoryId?.localId == area.name.capitalize();

    // Check if this area is passively cooking
    final isPassivelyCooking =
        !isActivelyCooking && areaState.isActive && activeCookingAction != null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _CookingAreaCard.maxWidth),
      child: _AreaStatusCard(
        area: area,
        areaState: areaState,
        assignedRecipe: assignedRecipe,
        isActivelyCooking: isActivelyCooking,
        isPassivelyCooking: isPassivelyCooking,
        skillLevel: skillLevel,
        recipes: recipes,
      ),
    );
  }
}

class _AreaStatusCard extends StatelessWidget {
  const _AreaStatusCard({
    required this.area,
    required this.areaState,
    required this.assignedRecipe,
    required this.isActivelyCooking,
    required this.isPassivelyCooking,
    required this.skillLevel,
    required this.recipes,
  });

  final CookingArea area;
  final CookingAreaState areaState;
  final CookingAction? assignedRecipe;
  final bool isActivelyCooking;
  final bool isPassivelyCooking;
  final int skillLevel;
  final List<CookingAction> recipes;

  /// Returns the cooking category for this area.
  CookingCategory? _getCategory(GlobalState state) {
    return state.registries.cooking.categoryById(area.categoryId);
  }

  /// Returns true if this cooking area is available to use.
  /// Fire is always available, but furnace/pot require purchasing upgrades.
  bool _isAreaAvailable(GlobalState state) {
    final category = _getCategory(state);
    if (category == null) return false;
    // If no upgrade required, area is always available (fire)
    if (!category.upgradeRequired) return true;
    // Otherwise, check if player has purchased an upgrade
    final id = switch (area) {
      CookingArea.fire => state.highestCookingFireId,
      CookingArea.furnace => state.highestCookingFurnaceId,
      CookingArea.pot => state.highestCookingPotId,
    };
    return id != null;
  }

  /// Returns the display name for the cooking area equipment level.
  String _getCookingAreaName(GlobalState state) {
    final category = _getCategory(state);
    final id = switch (area) {
      CookingArea.fire => state.highestCookingFireId,
      CookingArea.furnace => state.highestCookingFurnaceId,
      CookingArea.pot => state.highestCookingPotId,
    };
    if (id == null) {
      // Use category name for base level (e.g., "Basic" for fire)
      // If upgradeRequired, show "No {displayName}" instead
      if (category != null && !category.upgradeRequired) {
        return category.name;
      }
      return 'No ${area.displayName}';
    }
    return state.registries.shop.byId(id)?.name ?? area.displayName;
  }

  /// Returns the asset path for the cooking area icon.
  String _getCookingAreaIconPath(GlobalState state) {
    final category = _getCategory(state);
    final id = switch (area) {
      CookingArea.fire => state.highestCookingFireId,
      CookingArea.furnace => state.highestCookingFurnaceId,
      CookingArea.pot => state.highestCookingPotId,
    };
    // Use category media for base level, otherwise use default cooking icon
    if (id == null && category != null) {
      return category.media;
    }
    return 'assets/media/skills/cooking/cooking.png';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row: Fire icon + name, Select Recipe button
        _buildHeader(context, state),
        const SizedBox(height: 16),
        // Recipe details card (only if recipe assigned)
        if (assignedRecipe != null)
          _buildRecipeCard(context, state)
        else
          _buildEmptyRecipeCard(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, GlobalState state) {
    return Row(
      children: [
        // Fire/Furnace/Pot icon
        CachedImage(assetPath: _getCookingAreaIconPath(state), size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _getCookingAreaName(state),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        // Select Recipe button
        ElevatedButton(
          onPressed: _isAreaAvailable(state)
              ? () {
                  showRecipeSelectionDialog(
                    context: context,
                    area: area,
                    recipes: recipes,
                    assignedRecipe: assignedRecipe,
                    skillLevel: skillLevel,
                  );
                }
              : null,
          child: const Text('Select Recipe to Cook'),
        ),
      ],
    );
  }

  Widget _buildEmptyRecipeCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Select a recipe to start cooking',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Style.textColorSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeCard(BuildContext context, GlobalState state) {
    final recipe = assignedRecipe!;
    final productItem = state.registries.items.byId(recipe.productId);
    final healsFor = productItem.healsFor;
    final actionState = state.actionState(recipe.id);

    // Check if player has inputs
    final hasInputs = recipe.inputs.entries.every((entry) {
      final item = state.registries.items.byId(entry.key);
      return state.inventory.countOfItem(item) >= entry.value;
    });

    final canCook = skillLevel >= recipe.unlockLevel && hasInputs;

    // Get inventory count of the product
    final productCount = state.inventory.countOfItem(productItem);

    return Card(
      color: isActivelyCooking ? Style.activeColorLight : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Product icon + name + healing value
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product icon with count badge (left)
                CountBadgeCell(
                  count: productCount > 0 ? productCount : null,
                  backgroundColor: Style.xpBadgeBackgroundColor,
                  child: Center(child: ItemImage(item: productItem)),
                ),
                const SizedBox(width: 16),
                // Name and healing value (center)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${recipe.baseQuantity}x ${recipe.name}',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      if (healsFor != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CachedImage(
                              assetPath:
                                  'assets/media/skills/hitpoints/hitpoints.png',
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '+$healsFor',
                                    style: const TextStyle(
                                      color: Style.healColor,
                                    ),
                                  ),
                                  const TextSpan(text: ' Base Healing Value'),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Requires section
            const Text(
              'Requires:',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Center(child: ItemCountBadgesRow.required(items: recipe.inputs)),
            const SizedBox(height: 16),

            // Grants section
            const Text(
              'Grants:',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Center(child: XpBadgesRow(action: recipe)),
            const SizedBox(height: 16),

            // Mastery progress
            MasteryProgressCell(masteryXp: actionState.masteryXp),
            const SizedBox(height: 16),

            // You Have section
            const Text(
              'You Have:',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Center(child: ItemCountBadgesRow.inventory(items: recipe.inputs)),
            const SizedBox(height: 16),

            // Bonuses section
            const Text(
              'Bonuses:',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Preserve (recycle) chance
                RecycleChanceBadgeCell(chance: '0%'),
                SizedBox(width: 8),
                // Double chance
                DoubleChanceBadgeCell(chance: '0%'),
                SizedBox(width: 8),
                // Perfect cook chance
                _PerfectCookChanceBadgeCell(chance: '0%'),
                SizedBox(width: 8),
                // Cook success chance
                _CookSuccessChanceBadgeCell(chance: '75%'),
              ],
            ),
            const SizedBox(height: 16),

            // Active Cook / Passive Cook buttons
            Row(
              children: [
                Expanded(
                  child: _CookButton(
                    label: 'Active Cook',
                    duration: recipe.minDuration,
                    isActive: isActivelyCooking,
                    isEnabled: canCook,
                    color: Style.successColor,
                    onPressed: () {
                      if (isActivelyCooking) {
                        context.dispatch(StopCombatAction());
                      } else {
                        context.dispatch(StartCookingAction(area: area));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CookButton(
                    label: 'Passive Cook',
                    duration: recipe.minDuration * 5,
                    isActive: isPassivelyCooking,
                    isEnabled: canCook && !isActivelyCooking,
                    color: Style.selectedColor,
                    onPressed: () {
                      // Passive cooking starts when another area is active
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge cell showing perfect cook chance with a star icon.
class _PerfectCookChanceBadgeCell extends StatelessWidget {
  const _PerfectCookChanceBadgeCell({required this.chance});

  final String chance;

  @override
  Widget build(BuildContext context) {
    const iconSize = TextBadgeCell.defaultInradius * 0.6;

    return TextBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      text: chance,
      child: const Center(
        child: Icon(Icons.star, size: iconSize, color: Colors.amber),
      ),
    );
  }
}

/// Badge cell showing cook success chance with a checkmark icon.
class _CookSuccessChanceBadgeCell extends StatelessWidget {
  const _CookSuccessChanceBadgeCell({required this.chance});

  final String chance;

  @override
  Widget build(BuildContext context) {
    const iconSize = TextBadgeCell.defaultInradius * 0.6;

    return TextBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      text: chance,
      child: const Center(
        child: Icon(
          Icons.check_circle,
          size: iconSize,
          color: Style.successColor,
        ),
      ),
    );
  }
}

/// A cook button with a duration badge overlay.
class _CookButton extends StatelessWidget {
  const _CookButton({
    required this.label,
    required this.duration,
    required this.isActive,
    required this.isEnabled,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Duration duration;
  final bool isActive;
  final bool isEnabled;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final seconds = duration.inMilliseconds / 1000;
    final durationText = '${seconds.toStringAsFixed(2)}s';

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isEnabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? color : color.withValues(alpha: 0.7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(label),
          ),
        ),
        // Duration badge positioned below the button
        Positioned(
          bottom: -10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Style.badgeBackgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              durationText,
              style: const TextStyle(
                color: Style.badgeTextColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows a dialog for selecting a recipe to cook in a specific area.
Future<void> showRecipeSelectionDialog({
  required BuildContext context,
  required CookingArea area,
  required List<CookingAction> recipes,
  required CookingAction? assignedRecipe,
  required int skillLevel,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _RecipeSelectionDialog(
      area: area,
      recipes: recipes,
      assignedRecipe: assignedRecipe,
      skillLevel: skillLevel,
    ),
  );
}

class _RecipeSelectionDialog extends StatelessWidget {
  const _RecipeSelectionDialog({
    required this.area,
    required this.recipes,
    required this.assignedRecipe,
    required this.skillLevel,
  });

  final CookingArea area;
  final List<CookingAction> recipes;
  final CookingAction? assignedRecipe;
  final int skillLevel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Select ${area.displayName} Recipe'),
      content: SizedBox(
        width: 800,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: recipes.map((recipe) {
              return _RecipeCard(
                recipe: recipe,
                area: area,
                isSelected: recipe.id == assignedRecipe?.id,
                isUnlocked: skillLevel >= recipe.unlockLevel,
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// A card displaying a cooking recipe in the selection dialog.
class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.area,
    required this.isSelected,
    required this.isUnlocked,
  });

  final CookingAction recipe;
  final CookingArea area;
  final bool isSelected;
  final bool isUnlocked;

  static const double _cardWidth = 380;

  @override
  Widget build(BuildContext context) {
    if (!isUnlocked) {
      return SizedBox(
        width: _cardWidth,
        child: Card(
          color: Style.cellBackgroundColorLocked,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.lock, color: Style.textColorSecondary),
                const SizedBox(width: 8),
                const Text(
                  'Unlocked at ',
                  style: TextStyle(color: Style.textColorSecondary),
                ),
                const SkillImage(skill: Skill.cooking, size: 14),
                Text(
                  ' Level ${recipe.unlockLevel}',
                  style: const TextStyle(color: Style.textColorSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final state = context.state;
    final productItem = state.registries.items.byId(recipe.productId);
    final healsFor = productItem.healsFor;
    final actionState = state.actionState(recipe.id);
    final masteryProgress = xpProgressForXp(actionState.masteryXp);
    final perAction = xpPerAction(
      state,
      recipe,
      state.createActionModifierProvider(recipe),
    );
    final durationSeconds = recipe.minDuration.inSeconds;

    return SizedBox(
      width: _cardWidth,
      child: Card(
        color: isSelected ? Style.selectedColorLight : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Title + Select button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${recipe.baseQuantity} x ${recipe.name}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Style.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () {
                      context.dispatch(
                        AssignCookingRecipeAction(area: area, recipe: recipe),
                      );
                      Navigator.of(context).pop();
                    },
                    child: const Text('Select'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Main content row: Image with mastery + details
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product image with mastery below
                  Column(
                    children: [
                      ItemImage(item: productItem, size: 64),
                      const SizedBox(height: 8),
                      // Mastery level with trophy
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${masteryProgress.level}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(
                        '(${_formatPercent(masteryProgress.progress)})',
                        style: const TextStyle(
                          color: Style.textColorSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Details column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Duration badge + Output item badge
                        Row(
                          children: [
                            DurationBadgeCell(
                              seconds: durationSeconds,
                              inradius: TextBadgeCell.smallInradius,
                            ),
                            const SizedBox(width: 8),
                            ItemCountBadgeCell(
                              item: productItem,
                              count: recipe.baseQuantity,
                              inradius: TextBadgeCell.smallInradius,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Skill XP + Healing value
                        Row(
                          children: [
                            const SkillImage(skill: Skill.cooking, size: 14),
                            const SizedBox(width: 4),
                            Text('${perAction.xp} Skill XP'),
                          ],
                        ),
                        if (healsFor != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const CachedImage(
                                assetPath:
                                    'assets/media/skills/hitpoints/hitpoints.png',
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '+$healsFor',
                                      style: const TextStyle(
                                        color: Style.healColor,
                                      ),
                                    ),
                                    const TextSpan(text: ' Base Healing Value'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatPercent(double progress) {
  return '${(progress * 100).toStringAsFixed(2)}%';
}

extension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
