import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/input_items_row.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class CookingPage extends StatefulWidget {
  const CookingPage({super.key});

  @override
  State<CookingPage> createState() => _CookingPageState();
}

class _CookingPageState extends State<CookingPage> {
  SkillAction? _selectedAction;

  @override
  Widget build(BuildContext context) {
    const skill = Skill.cooking;
    final actions = context.state.registries.actions.forSkill(skill).toList();
    final skillState = context.state.skillState(skill);

    // Default to first action if none selected
    final selectedAction = _selectedAction ?? actions.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Cooking')),
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
                  _SelectedActionDisplay(
                    action: selectedAction,
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _ActionList(
                    actions: actions,
                    selectedAction: selectedAction,
                    onSelect: (action) {
                      setState(() {
                        _selectedAction = action;
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

class _SelectedActionDisplay extends StatelessWidget {
  const _SelectedActionDisplay({required this.action, required this.onStart});

  final SkillAction action;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(action.id);
    final isActive = state.activeAction?.id == action.id;
    final canStart = state.canStartAction(action);

    // Get healing value from output item if it exists
    final outputId = action.outputs.keys.firstOrNull;
    final outputItem = outputId != null
        ? state.registries.items.byId(outputId)
        : null;
    final healsFor = outputItem?.healsFor;

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
          // Header: Cook + Action Name
          const Text(
            'Cook',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Style.textColorSecondary),
          ),
          Text(
            action.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
          if (healsFor != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.favorite, size: 16, color: Style.healColor),
                const SizedBox(width: 4),
                Text('Heals $healsFor HP'),
              ],
            ),
          ],
          const SizedBox(height: 8),

          // Grants section
          const Text('Grants:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          XpBadgesRow(action: action),
          const SizedBox(height: 16),

          // Duration and Cook button
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
            child: Text(isActive ? 'Stop' : 'Cook'),
          ),
        ],
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actions,
    required this.selectedAction,
    required this.onSelect,
  });

  final List<SkillAction> actions;
  final SkillAction selectedAction;
  final void Function(SkillAction) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Available Recipes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...actions.map((action) {
          final isSelected = action.name == selectedAction.name;
          final cookingAction = action as CookingAction;
          final productItem = context.state.registries.items.byId(
            cookingAction.productId,
          );
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
        }),
      ],
    );
  }
}
