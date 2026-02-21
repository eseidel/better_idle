import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/input_items_row.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/production_action_display.dart';
import 'package:ui/src/widgets/skill_fab.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skill_overflow_menu.dart';
import 'package:ui/src/widgets/skill_progress.dart';
import 'package:ui/src/widgets/style.dart';

class RunecraftingPage extends StatefulWidget {
  const RunecraftingPage({super.key});

  @override
  State<RunecraftingPage> createState() => _RunecraftingPageState();
}

class _RunecraftingPageState extends State<RunecraftingPage>
    with SingleTickerProviderStateMixin {
  RunecraftingAction? _selectedAction;
  TabController? _tabController;
  List<RunecraftingCategory>? _categories;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initTabController();
  }

  void _initTabController() {
    final categories = context.state.registries.runecrafting.categories;
    // Only rebuild the controller if categories changed
    if (_categories == null || _categories!.length != categories.length) {
      _tabController?.dispose();
      _categories = categories;
      _tabController = TabController(length: categories.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const skill = Skill.runecrafting;
    final registries = context.state.registries;
    final actions = registries.runecrafting.actions;
    final categories = registries.runecrafting.categories;
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Group actions by category
    final actionsByCategory =
        <RunecraftingCategory, List<RunecraftingAction>>{};
    for (final action in actions) {
      final category = action.categoryId != null
          ? registries.runecrafting.categoryById(action.categoryId!)
          : null;
      if (category != null) {
        actionsByCategory.putIfAbsent(category, () => []).add(action);
      }
    }

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((RunecraftingAction a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    return GameScaffold(
      title: const Text('Runecrafting'),
      actions: const [SkillOverflowMenu(skill: skill)],
      floatingActionButton: const SkillFab(skill: skill),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          if (_tabController != null)
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: categories.map((category) {
                return Tab(
                  icon: CachedImage(assetPath: category.media, size: 24),
                  text: category.name,
                );
              }).toList(),
            ),
          Expanded(
            child: _tabController != null
                ? TabBarView(
                    controller: _tabController,
                    children: categories.map((category) {
                      final categoryActions = actionsByCategory[category] ?? [];
                      return _CategoryTab(
                        actions: categoryActions,
                        selectedAction: selectedAction,
                        skillLevel: skillLevel,
                        onSelectAction: (action) {
                          setState(() {
                            _selectedAction = action;
                          });
                        },
                      );
                    }).toList(),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}

/// Tab content showing recipes for a single runecrafting category.
class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelectAction,
  });

  final List<RunecraftingAction> actions;
  final RunecraftingAction? selectedAction;
  final int skillLevel;
  final void Function(RunecraftingAction) onSelectAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (selectedAction != null)
            ProductionActionDisplay(
              action: selectedAction!,
              productId: selectedAction!.productId,
              skill: Skill.runecrafting,
              headerText: 'Create',
              buttonText: 'Create',
              showRecycleBadge: false,
              skillLevel: skillLevel,
              onStart: () {
                context.dispatch(ToggleActionAction(action: selectedAction!));
              },
            ),
          const SizedBox(height: 24),
          _RecipeList(
            actions: actions,
            selectedAction: selectedAction,
            skillLevel: skillLevel,
            onSelect: onSelectAction,
          ),
        ],
      ),
    );
  }
}

/// List of recipes within a category tab.
class _RecipeList extends StatelessWidget {
  const _RecipeList({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelect,
  });

  final List<RunecraftingAction> actions;
  final RunecraftingAction? selectedAction;
  final int skillLevel;
  final void Function(RunecraftingAction) onSelect;

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: actions.map((action) {
        final isSelected = action.id == selectedAction?.id;
        final isUnlocked = skillLevel >= action.unlockLevel;

        if (!isUnlocked) {
          return Card(
            color: Style.cellBackgroundColorLocked,
            child: ListTile(
              leading: const Icon(Icons.lock, color: Style.textColorSecondary),
              title: Row(
                children: [
                  const Text(
                    'Unlocked at ',
                    style: TextStyle(color: Style.textColorSecondary),
                  ),
                  const SkillImage(skill: Skill.runecrafting, size: 14),
                  Text(
                    ' Level ${action.unlockLevel}',
                    style: const TextStyle(color: Style.textColorSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        final productItem = state.registries.items.byId(action.productId);
        return Card(
          color: isSelected ? Style.selectedColorLight : null,
          child: ListTile(
            leading: ItemImage(item: productItem),
            title: Text(action.name),
            subtitle: InputItemsRow(items: action.inputs),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Style.selectedColor)
                : null,
            onTap: () => onSelect(action),
          ),
        );
      }).toList(),
    );
  }
}
