import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/input_items_row.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A generic widget for displaying skill actions grouped by category.
///
/// Used by Smithing, Fletching, Herblore, and Runecrafting screens which share
/// the same layout: collapsible category headers with action cards underneath.
///
/// Type parameters:
/// - [C] - The category type (e.g., SmithingCategory, FletchingCategory)
/// - [A] - The action type (e.g., SmithingAction, FletchingAction)
class CategorizedActionList<C, A extends SkillAction> extends StatelessWidget {
  const CategorizedActionList({
    required this.actionsByCategory,
    required this.selectedAction,
    required this.collapsedCategories,
    required this.onSelect,
    required this.onToggleCategory,
    required this.categoryId,
    required this.categoryName,
    required this.categoryMedia,
    required this.actionProductId,
    this.skill,
    this.skillLevel,
    this.title = 'Available Actions',
    super.key,
  });

  final Map<C, List<A>> actionsByCategory;
  final A? selectedAction;
  final Set<MelvorId> collapsedCategories;
  final void Function(A) onSelect;
  final void Function(C) onToggleCategory;

  /// Extracts the ID from a category.
  final MelvorId Function(C) categoryId;

  /// Extracts the name from a category.
  final String Function(C) categoryName;

  /// Extracts the media path from a category.
  final String Function(C) categoryMedia;

  /// Extracts the product ID from an action.
  final MelvorId Function(A) actionProductId;

  /// The skill for showing lock icons. If null, locking is disabled.
  final Skill? skill;

  /// The current skill level. If null, all actions are shown as unlocked.
  final int? skillLevel;

  /// The title shown above the action list.
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...actionsByCategory.entries.map((entry) {
          final category = entry.key;
          final actions = entry.value;
          final isCollapsed = collapsedCategories.contains(
            categoryId(category),
          );

          // Split actions into unlocked and locked.
          final unlockedActions = <A>[];
          final lockedActions = <A>[];
          for (final action in actions) {
            final isUnlocked =
                skillLevel == null || skillLevel! >= action.unlockLevel;
            if (isUnlocked) {
              unlockedActions.add(action);
            } else {
              lockedActions.add(action);
            }
          }

          // Find the next locked action (lowest unlock level).
          A? nextLocked;
          if (lockedActions.isNotEmpty && skill != null) {
            nextLocked = lockedActions.reduce(
              (a, b) => a.unlockLevel <= b.unlockLevel ? a : b,
            );
          }

          final isFullyLocked = unlockedActions.isEmpty;

          // Build the visible action list: all unlocked + at most one locked.
          final visibleActions = [
            ...unlockedActions,
            if (nextLocked != null && !isFullyLocked) nextLocked,
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category header
              InkWell(
                onTap: isFullyLocked ? null : () => onToggleCategory(category),
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
                      if (!isFullyLocked)
                        Icon(
                          isCollapsed
                              ? Icons.arrow_right
                              : Icons.arrow_drop_down,
                          size: 24,
                        ),
                      if (isFullyLocked)
                        const Icon(
                          Icons.lock,
                          size: 20,
                          color: Style.textColorSecondary,
                        ),
                      const SizedBox(width: 8),
                      CachedImage(assetPath: categoryMedia(category), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        categoryName(category),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isFullyLocked
                              ? Style.textColorSecondary
                              : null,
                        ),
                      ),
                      if (isFullyLocked && nextLocked != null) ...[
                        const Spacer(),
                        Text(
                          'Level ${nextLocked.unlockLevel}',
                          style: const TextStyle(
                            color: Style.textColorSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Actions list (if not collapsed and not fully locked)
              if (!isCollapsed && !isFullyLocked)
                ...visibleActions.map((action) {
                  final isSelected = action.id == selectedAction?.id;
                  final isUnlocked =
                      skillLevel == null || skillLevel! >= action.unlockLevel;

                  if (!isUnlocked && skill != null) {
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
                            SkillImage(skill: skill!, size: 14),
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
                    actionProductId(action),
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
