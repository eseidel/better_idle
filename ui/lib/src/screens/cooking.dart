import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/input_items_row.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class CookingPage extends StatefulWidget {
  const CookingPage({super.key});

  @override
  State<CookingPage> createState() => _CookingPageState();
}

class _CookingPageState extends State<CookingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const skill = Skill.cooking;
    final state = context.state;
    final skillState = state.skillState(skill);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Fire'),
            Tab(text: 'Furnace'),
            Tab(text: 'Pot'),
          ],
        ),
      ),
      drawer: const AppNavigationDrawer(),
      body: Column(
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _CookingAreaTab(area: CookingArea.fire),
                _CookingAreaTab(area: CookingArea.furnace),
                _CookingAreaTab(area: CookingArea.pot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CookingAreaTab extends StatelessWidget {
  const _CookingAreaTab({required this.area});

  final CookingArea area;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final skillLevel = state.skillState(Skill.cooking).skillLevel;
    final areaState = state.cooking.areaState(area);

    // Get recipes for this area
    final recipes = state.registries.actions
        .forSkill(Skill.cooking)
        .whereType<CookingAction>()
        .where((a) => a.categoryId?.localId == area.name.capitalize())
        .toList();

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Area status card
          _AreaStatusCard(
            area: area,
            areaState: areaState,
            assignedRecipe: assignedRecipe,
            isActivelyCooking: isActivelyCooking,
            isPassivelyCooking: isPassivelyCooking,
            skillLevel: skillLevel,
          ),
          const SizedBox(height: 24),
          // Recipe list
          _RecipeList(
            area: area,
            recipes: recipes,
            assignedRecipe: assignedRecipe,
            skillLevel: skillLevel,
          ),
        ],
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
  });

  final CookingArea area;
  final CookingAreaState areaState;
  final CookingAction? assignedRecipe;
  final bool isActivelyCooking;
  final bool isPassivelyCooking;
  final int skillLevel;

  String _formatProgress() {
    if (areaState.progressTicksRemaining == null ||
        areaState.totalTicks == null) {
      return '';
    }
    final remaining = areaState.progressTicksRemaining!;
    final total = areaState.totalTicks!;
    final elapsed = total - remaining;
    final percent = (elapsed / total * 100).toStringAsFixed(0);
    return '$percent%';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    if (assignedRecipe == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.add_circle_outline, size: 48),
              const SizedBox(height: 8),
              Text(
                'Select a recipe below',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    final productItem = state.registries.items.byId(assignedRecipe!.productId);
    final healsFor = productItem.healsFor;

    // Check if player has inputs
    final hasInputs = assignedRecipe!.inputs.entries.every((entry) {
      final item = state.registries.items.byId(entry.key);
      return state.inventory.countOfItem(item) >= entry.value;
    });

    final canCook = skillLevel >= assignedRecipe!.unlockLevel && hasInputs;

    return Card(
      color: isActivelyCooking ? Style.selectedColorLight : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with recipe name and status
            Row(
              children: [
                ItemImage(item: productItem, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignedRecipe!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (isActivelyCooking)
                        const Text(
                          'Active',
                          style: TextStyle(
                            color: Style.successColor,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (isPassivelyCooking)
                        const Text(
                          'Passive (5x slower)',
                          style: TextStyle(
                            color: Style.warningColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    context.dispatch(ClearCookingRecipeAction(area: area));
                  },
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear recipe',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Stats
            Row(
              children: [
                if (healsFor != null) ...[
                  const Icon(Icons.favorite, size: 16, color: Style.healColor),
                  const SizedBox(width: 4),
                  Text('Heals $healsFor HP'),
                  const SizedBox(width: 16),
                ],
                const Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text('${assignedRecipe!.xp} XP'),
              ],
            ),
            const SizedBox(height: 8),
            // Inputs
            InputItemsRow(items: assignedRecipe!.inputs),
            // Progress bar (if cooking)
            if (areaState.isActive &&
                areaState.progressTicksRemaining != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: areaState.totalTicks != null
                          ? (areaState.totalTicks! -
                                    areaState.progressTicksRemaining!) /
                                areaState.totalTicks!
                          : 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_formatProgress()),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // Cook button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canCook
                    ? () {
                        if (isActivelyCooking) {
                          // Stop cooking
                          context.dispatch(StopCombatAction());
                        } else {
                          // Start cooking this area
                          context.dispatch(StartCookingAction(area: area));
                        }
                      }
                    : null,
                child: Text(isActivelyCooking ? 'Stop' : 'Cook'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeList extends StatelessWidget {
  const _RecipeList({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Available Recipes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...recipes.map((recipe) {
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
              },
            ),
          );
        }),
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
