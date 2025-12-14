import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class SmithingPage extends StatefulWidget {
  const SmithingPage({super.key});

  @override
  State<SmithingPage> createState() => _SmithingPageState();
}

class _SmithingPageState extends State<SmithingPage> {
  SkillAction? _selectedAction;

  @override
  Widget build(BuildContext context) {
    const skill = Skill.smithing;
    final actions = actionRegistry.forSkill(skill).toList();
    final skillState = context.state.skillState(skill);

    // Default to first action if none selected
    final selectedAction = _selectedAction ?? actions.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Smithing')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
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
    final actionState = state.actionState(action.name);
    final isActive = state.activeAction?.name == action.name;
    final canStart = state.canStartAction(action);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? Colors.orange.withValues(alpha: 0.1) : Colors.white,
        border: Border.all(
          color: isActive ? Colors.orange : Colors.grey,
          width: isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Create + Action Name
          const Text(
            'Create',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          Text(
            action.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Recycle and Double chance (placeholders)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ChanceIndicator(
                icon: Icons.recycling,
                label: 'Recycle',
                value: '0%',
              ),
              SizedBox(width: 24),
              _ChanceIndicator(
                icon: Icons.double_arrow,
                label: 'Double',
                value: '0%',
              ),
            ],
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
          _ItemList(items: action.inputs),
          const SizedBox(height: 8),

          // You Have section
          const Text(
            'You Have:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _InventoryItemList(items: action.inputs),
          const SizedBox(height: 8),

          // Produces section
          const Text(
            'Produces:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _ItemList(items: action.outputs),
          const SizedBox(height: 8),

          // Grants section
          const Text('Grants:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${action.xp} XP, 3 Mastery XP, 0.25% Pool XP'),
          const SizedBox(height: 16),

          // Duration and Create button
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
              backgroundColor: isActive ? Colors.orange : null,
            ),
            child: Text(isActive ? 'Stop' : 'Create'),
          ),
        ],
      ),
    );
  }
}

class _ChanceIndicator extends StatelessWidget {
  const _ChanceIndicator({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.grey),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items});

  final Map<String, int> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('None', style: TextStyle(color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.entries.map((entry) {
        return Text('${entry.value}x ${entry.key}');
      }).toList(),
    );
  }
}

class _InventoryItemList extends StatelessWidget {
  const _InventoryItemList({required this.items});

  final Map<String, int> items;

  @override
  Widget build(BuildContext context) {
    final inventory = context.state.inventory;

    if (items.isEmpty) {
      return const Text('None', style: TextStyle(color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.entries.map((entry) {
        final count = inventory.countByName(entry.key);
        final hasEnough = count >= entry.value;
        return Text(
          '$count ${entry.key}',
          style: TextStyle(color: hasEnough ? Colors.green : Colors.red),
        );
      }).toList(),
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
          'Available Actions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...actions.map((action) {
          final isSelected = action.name == selectedAction.name;
          return Card(
            color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
            child: ListTile(
              title: Text(action.name),
              subtitle: Text(
                action.inputs.entries
                    .map((e) => '${e.value}x ${e.key}')
                    .join(', '),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Colors.blue)
                  : null,
              onTap: () => onSelect(action),
            ),
          );
        }),
      ],
    );
  }
}
