import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/equipment_slots.dart';
import 'package:ui/src/widgets/expandable_fab.dart';
import 'package:ui/src/widgets/quick_equip_dialog.dart';

/// An expandable FAB for skill pages with Quick Equip and Equipment
/// actions.
class SkillFab extends StatelessWidget {
  const SkillFab({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return ExpandableFab(
      actions: [
        ExpandableFabAction(
          icon: Icons.grid_view,
          label: 'Equipment',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const EquipmentGridDialog(),
          ),
        ),
        ExpandableFabAction(
          icon: Icons.shield,
          label: 'Quick Equip',
          onPressed: () => showQuickEquipDialog(context, skill),
        ),
      ],
    );
  }
}
