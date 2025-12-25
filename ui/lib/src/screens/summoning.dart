import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/input_items_row.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_action_display.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class SummoningPage extends StatefulWidget {
  const SummoningPage({super.key});

  @override
  State<SummoningPage> createState() => _SummoningPageState();
}

class _SummoningPageState extends State<SummoningPage> {
  SkillAction? _selectedAction;

  @override
  Widget build(BuildContext context) {
    const skill = Skill.summoning;
    final state = context.state;
    final actions = state.registries.actions
        .forSkill(skill)
        .cast<SummoningAction>()
        .toList();
    final skillState = state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Sort by level, then by tier
    actions.sort((a, b) {
      final tierCompare = a.tier.compareTo(b.tier);
      if (tierCompare != 0) return tierCompare;
      return a.unlockLevel.compareTo(b.unlockLevel);
    });

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : actions.first);

    return Scaffold(
      appBar: AppBar(title: const Text('Summoning')),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SkillActionDisplay(
                    action: selectedAction,
                    skill: skill,
                    skillLevel: skillLevel,
                    headerText: 'Create',
                    buttonText: 'Create',
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
                    skillLevel: skillLevel,
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

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelect,
  });

  final List<SummoningAction> actions;
  final SkillAction selectedAction;
  final int skillLevel;
  final void Function(SummoningAction) onSelect;

  @override
  Widget build(BuildContext context) {
    // Group actions by tier
    final tier1 = actions.where((a) => a.tier == 1).toList();
    final tier2 = actions.where((a) => a.tier == 2).toList();
    final tier3 = actions.where((a) => a.tier == 3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tier1.isNotEmpty) ...[
          const _TierHeader(tier: 1),
          ..._buildActionCards(context, tier1),
        ],
        if (tier2.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _TierHeader(tier: 2),
          ..._buildActionCards(context, tier2),
        ],
        if (tier3.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _TierHeader(tier: 3),
          ..._buildActionCards(context, tier3),
        ],
      ],
    );
  }

  List<Widget> _buildActionCards(
    BuildContext context,
    List<SummoningAction> tierActions,
  ) {
    return tierActions.map((action) {
      final isSelected = action.name == selectedAction.name;
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
                const SkillImage(skill: Skill.summoning, size: 14),
                Text(
                  ' Level ${action.unlockLevel}',
                  style: const TextStyle(color: Style.textColorSecondary),
                ),
              ],
            ),
            onTap: () => onSelect(action),
          ),
        );
      }

      final productItem = context.state.registries.items.byId(action.productId);
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
    }).toList();
  }
}

class _TierHeader extends StatelessWidget {
  const _TierHeader({required this.tier});

  final int tier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Tier $tier Familiars',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
