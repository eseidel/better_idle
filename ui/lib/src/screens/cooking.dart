import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/double_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/input_items_row.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Cooking')),
      drawer: const AppNavigationDrawer(),
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
        state.registries.actions
            .forSkill(Skill.cooking)
            .whereType<CookingAction>()
            .where((a) => a.categoryId?.localId == area.name.capitalize())
            .toList()
          ..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));

    // Get unlocked recipes
    final unlockedRecipes = recipes
        .where((r) => skillLevel >= r.unlockLevel)
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
            (r) => r.id == areaState.recipeId,
            orElse: () => recipes.first,
          )
        : null;

    // Check if this area is actively cooking
    final activeActionState = state.activeAction;
    CookingAction? activeCookingAction;
    if (activeActionState != null) {
      final action = state.registries.actions.byId(activeActionState.id);
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
    return state.registries.cookingCategories.byId(area.categoryId);
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
                            const Icon(
                              Icons.favorite,
                              size: 16,
                              color: Style.healColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '+$healsFor Base Healing Value',
                              style: const TextStyle(color: Style.healColor),
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
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: recipes.length,
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            final isSelected = recipe.id == assignedRecipe?.id;
            final isUnlocked = skillLevel >= recipe.unlockLevel;

            if (!isUnlocked) {
              return Card(
                color: Style.cellBackgroundColorLocked,
                child: ListTile(
                  leading: const Icon(
                    Icons.lock,
                    color: Style.textColorSecondary,
                  ),
                  title: Row(
                    children: [
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
              );
            }

            final productItem = context.state.registries.items.byId(
              recipe.productId,
            );
            return Card(
              color: isSelected ? Style.selectedColorLight : null,
              child: ListTile(
                leading: ItemImage(item: productItem),
                title: Text(recipe.name),
                subtitle: InputItemsRow(items: recipe.inputs),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Style.selectedColor)
                    : null,
                onTap: () {
                  context.dispatch(
                    AssignCookingRecipeAction(area: area, recipe: recipe),
                  );
                  Navigator.of(context).pop();
                },
              ),
            );
          },
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

extension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
