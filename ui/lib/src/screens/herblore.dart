import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/double_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/input_items_row.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class HerblorePage extends StatefulWidget {
  const HerblorePage({super.key});

  @override
  State<HerblorePage> createState() => _HerblorePageState();
}

class _HerblorePageState extends State<HerblorePage> {
  HerbloreAction? _selectedAction;
  final Set<MelvorId> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.herblore;
    final registries = context.state.registries;
    final actions = registries.actions
        .forSkill(skill)
        .whereType<HerbloreAction>()
        .toList();
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;
    final categories = registries.herbloreCategories;

    // Group actions by category
    final actionsByCategory = <HerbloreCategory, List<HerbloreAction>>{};
    for (final action in actions) {
      final category = action.categoryId != null
          ? categories.byId(action.categoryId!)
          : null;
      if (category != null) {
        actionsByCategory.putIfAbsent(category, () => []).add(action);
      }
    }

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Herblore')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
          const MasteryUnlocksButton(skill: skill),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (selectedAction != null)
                    _SelectedActionDisplay(
                      action: selectedAction,
                      skillLevel: skillLevel,
                      onStart: () {
                        context.dispatch(
                          ToggleActionAction(action: selectedAction),
                        );
                      },
                    )
                  else
                    _NoUnlockedActionsDisplay(skillLevel: skillLevel),
                  const SizedBox(height: 24),
                  _ActionList(
                    actionsByCategory: actionsByCategory,
                    selectedAction: selectedAction,
                    skillLevel: skillLevel,
                    collapsedCategories: _collapsedCategories,
                    onSelect: (action) {
                      setState(() {
                        _selectedAction = action;
                      });
                    },
                    onToggleCategory: (category) {
                      setState(() {
                        if (_collapsedCategories.contains(category.id)) {
                          _collapsedCategories.remove(category.id);
                        } else {
                          _collapsedCategories.add(category.id);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoUnlockedActionsDisplay extends StatelessWidget {
  const _NoUnlockedActionsDisplay({required this.skillLevel});

  final int skillLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColorLocked,
        border: Border.all(color: Style.textColorSecondary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock, size: 48, color: Style.textColorSecondary),
          const SizedBox(height: 8),
          const Text('No herblore actions unlocked yet'),
          Text('Current level: $skillLevel'),
        ],
      ),
    );
  }
}

class _SelectedActionDisplay extends StatelessWidget {
  const _SelectedActionDisplay({
    required this.action,
    required this.skillLevel,
    required this.onStart,
  });

  final HerbloreAction action;
  final int skillLevel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final isUnlocked = skillLevel >= action.unlockLevel;

    if (!isUnlocked) {
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
              const SkillImage(skill: Skill.herblore, size: 16),
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
    final isActive = state.activeAction?.id == action.id;
    final canStart = state.canStartAction(action);

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
          // Header: Brew + Action Name
          const Text(
            'Brew',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Style.textColorSecondary),
          ),
          Text(
            action.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Double chance (placeholder)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [DoubleChanceBadgeCell(chance: '0%')],
          ),
          const SizedBox(height: 12),

          // Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          // Requires section
          const Text(
            'Requires:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ItemCountBadgesRow.required(items: action.inputs),
          const SizedBox(height: 8),

          // You Have section
          const Text(
            'You Have:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ItemCountBadgesRow.inventory(items: action.inputs),
          const SizedBox(height: 8),

          // Produces section
          const Text(
            'Produces:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ItemCountBadgesRow.required(items: action.outputs),
          const SizedBox(height: 8),

          // Grants section
          const Text('Grants:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          XpBadgesRow(action: action),
          const SizedBox(height: 16),

          // Duration and Brew button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 16),
              const SizedBox(width: 4),
              Text('${action.minDuration.inSeconds}s'),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: canStart || isActive ? onStart : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Style.activeColor : null,
            ),
            child: Text(isActive ? 'Stop' : 'Brew'),
          ),
        ],
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actionsByCategory,
    required this.selectedAction,
    required this.skillLevel,
    required this.collapsedCategories,
    required this.onSelect,
    required this.onToggleCategory,
  });

  final Map<HerbloreCategory, List<HerbloreAction>> actionsByCategory;
  final HerbloreAction? selectedAction;
  final int skillLevel;
  final Set<MelvorId> collapsedCategories;
  final void Function(HerbloreAction) onSelect;
  final void Function(HerbloreCategory) onToggleCategory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Available Potions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...actionsByCategory.entries.map((entry) {
          final category = entry.key;
          final actions = entry.value;
          final isCollapsed = collapsedCategories.contains(category.id);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category header with collapse toggle
              InkWell(
                onTap: () => onToggleCategory(category),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Style.categoryHeaderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      CachedImage(assetPath: category.media, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        category.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Actions list (if not collapsed)
              if (!isCollapsed)
                ...actions.map((action) {
                  final isSelected = action.id == selectedAction?.id;
                  final isUnlocked = skillLevel >= action.unlockLevel;

                  if (!isUnlocked) {
                    return Card(
                      margin: const EdgeInsets.only(
                        left: 16,
                        top: 4,
                        bottom: 4,
                      ),
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
                            const SkillImage(skill: Skill.herblore, size: 14),
                            Text(
                              ' Level ${action.unlockLevel}',
                              style: const TextStyle(
                                color: Style.textColorSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final productItem = context.state.registries.items.byId(
                    action.productId,
                  );
                  return Card(
                    margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    color: isSelected ? Style.selectedColorLight : null,
                    child: ListTile(
                      leading: ItemImage(item: productItem),
                      title: Text(action.name),
                      subtitle: InputItemsRow(items: action.inputs),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Style.selectedColor,
                            )
                          : null,
                      onTap: () => onSelect(action),
                    ),
                  );
                }),
              const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }
}
