import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Displays attack style options based on the currently equipped weapon type.
///
/// If no weapon is equipped, shows melee styles.
/// If a ranged weapon is equipped, shows ranged styles.
/// If a magic weapon is equipped, shows magic styles.
class AttackStyleSelector extends StatelessWidget {
  const AttackStyleSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final currentStyle = state.attackStyle;

    // Determine combat type based on equipped weapon
    final weapon = state.equipment.gearInSlot(EquipmentSlot.weapon);
    final combatType = weapon?.attackType?.combatType ?? CombatType.melee;
    final availableStyles = combatType.attackStyles;

    // If current style doesn't match weapon type, we'll show it anyway
    // but highlight it as mismatched
    final styleMatchesWeapon = currentStyle.combatType == combatType;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Attack Style',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${combatType.name})',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Style.textColorSecondary,
                  ),
                ),
              ],
            ),
            if (!styleMatchesWeapon) ...[
              const SizedBox(height: 4),
              Text(
                'Current style (${currentStyle.name}) '
                'does not match weapon type',
                style: TextStyle(
                  fontSize: 12,
                  color: Style.textColorWarning,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in availableStyles)
                  _AttackStyleChip(
                    style: style,
                    isSelected: style == currentStyle,
                    onTap: () => context.dispatch(
                      SetAttackStyleAction(attackStyle: style),
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

class _AttackStyleChip extends StatelessWidget {
  const _AttackStyleChip({
    required this.style,
    required this.isSelected,
    required this.onTap,
  });

  final AttackStyle style;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Style.selectedColorLight : null,
          border: Border.all(
            color: isSelected ? Style.selectedColor : Style.cellBorderColor,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkillImage(skill: style.primarySkill, size: 20),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  style.displayName,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  style.xpDescription,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Style.textColorSecondary,
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

extension on AttackStyle {
  /// Returns the primary skill that gains XP from this attack style.
  Skill get primarySkill => switch (this) {
    AttackStyle.stab => Skill.attack,
    AttackStyle.slash => Skill.strength,
    AttackStyle.block => Skill.defence,
    AttackStyle.accurate => Skill.ranged,
    AttackStyle.rapid => Skill.ranged,
    AttackStyle.longRange => Skill.ranged,
    AttackStyle.standard => Skill.magic,
    AttackStyle.defensive => Skill.magic,
  };

  /// Returns a user-friendly display name.
  String get displayName => switch (this) {
    AttackStyle.stab => 'Stab',
    AttackStyle.slash => 'Slash',
    AttackStyle.block => 'Block',
    AttackStyle.accurate => 'Accurate',
    AttackStyle.rapid => 'Rapid',
    AttackStyle.longRange => 'Long Range',
    AttackStyle.standard => 'Standard',
    AttackStyle.defensive => 'Defensive',
  };

  /// Returns a short description of XP distribution.
  String get xpDescription => switch (this) {
    AttackStyle.stab => 'Attack XP',
    AttackStyle.slash => 'Strength XP',
    AttackStyle.block => 'Defence XP',
    AttackStyle.accurate => 'Ranged XP (+3 acc)',
    AttackStyle.rapid => 'Ranged XP (faster)',
    AttackStyle.longRange => 'Ranged + Def XP',
    AttackStyle.standard => 'Magic XP',
    AttackStyle.defensive => 'Magic + Def XP',
  };
}
