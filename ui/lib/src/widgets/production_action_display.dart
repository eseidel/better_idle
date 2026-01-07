import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/double_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/duration_badge_cell.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/recycle_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

/// A generic action display widget for production-based skills.
///
/// Supports smithing, fletching, crafting, runecrafting, and herblore.
///
/// Layout:
/// - Row 1: 1/3 product icon with count, 2/3 "Action\nName" + badges
/// - Row 2: Mastery progress bar
/// - Row 3: Two columns - "Requires:" with items | "You Have:" with items
/// - Row 4: Two columns - "Produces:" with items | "Grants:" with XP badges
/// - Row 5: Action button with duration badge
/// - Row 6: Active progress bar (when active)
class ProductionActionDisplay extends StatelessWidget {
  const ProductionActionDisplay({
    required this.action,
    required this.productId,
    required this.skill,
    required this.onStart,
    required this.headerText,
    required this.buttonText,
    required this.showRecycleBadge,
    this.skillLevel,
    super.key,
  });

  final SkillAction action;
  final MelvorId productId;
  final Skill skill;
  final VoidCallback onStart;
  final String headerText;
  final String buttonText;
  final bool showRecycleBadge;
  final int? skillLevel;

  bool get _isUnlocked =>
      skillLevel == null || skillLevel! >= action.unlockLevel;

  @override
  Widget build(BuildContext context) {
    if (!_isUnlocked) {
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
              SkillImage(skill: skill, size: 16),
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

    final inputs = action.inputs;
    final outputs = action.outputs;

    // Get product for the icon
    final productItem = state.registries.items.byId(productId);
    final inventoryCount = state.inventory.countOfItem(productItem);

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
          // Row 1: Product icon (1/3) | Name + badges (2/3)
          _buildHeaderRow(context, productItem, inventoryCount),
          const SizedBox(height: 12),

          // Row 2: Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          // Row 3: Requires | You Have
          _buildRequiresHaveRow(context, inputs),
          const SizedBox(height: 12),

          // Row 4: Produces | Grants
          _buildProducesGrantsRow(context, outputs),
          const SizedBox(height: 16),

          // Row 5: Action button with duration
          _buildButtonRow(context, isActive, canStart),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context,
    Item productItem,
    int inventoryCount,
  ) {
    return Row(
      children: [
        // Fixed-size product icon with count badge
        CountBadgeCell(
          count: inventoryCount > 0 ? inventoryCount : null,
          inradius: 64,
          child: CachedImage(assetPath: productItem.media ?? '', size: 40),
        ),
        const SizedBox(width: 12),
        // Name and badges take remaining space, left-justified
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerText,
                style: const TextStyle(
                  fontSize: 14,
                  color: Style.textColorSecondary,
                ),
              ),
              Text(
                action.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (showRecycleBadge) ...[
                    const RecycleChanceBadgeCell(chance: '0%'),
                    const SizedBox(width: 16),
                  ],
                  const DoubleChanceBadgeCell(chance: '0%'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRequiresHaveRow(
    BuildContext context,
    Map<MelvorId, int> inputs,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Requires
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Requires:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (inputs.isEmpty)
                const Text(
                  'None',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                ItemCountBadgesRow.required(items: inputs),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right column: You Have
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You Have:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (inputs.isEmpty)
                const Text(
                  'N/A',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                ItemCountBadgesRow.inventory(items: inputs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProducesGrantsRow(
    BuildContext context,
    Map<MelvorId, int> outputs,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Produces
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Produces:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (outputs.isEmpty)
                const Text(
                  'None',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                ItemCountBadgesRow.required(items: outputs),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right column: Grants
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Grants:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              XpBadgesRow(action: action),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtonRow(BuildContext context, bool isActive, bool canStart) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: canStart || isActive ? onStart : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? Style.activeColor : null,
          ),
          child: Text(isActive ? 'Stop' : buttonText),
        ),
        const SizedBox(width: 16),
        DurationBadgeCell(seconds: action.minDuration.inSeconds),
      ],
    );
  }
}
