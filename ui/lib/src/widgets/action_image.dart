import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Returns the media path for an action, if available.
/// Different action subclasses store media in different ways.
String? mediaForAction(SkillAction action) {
  // Check for specific action types that have media fields.
  if (action is WoodcuttingTree) return action.media;
  if (action is FishingAction) {
    final media = action.media;
    if (media.isNotEmpty) return media;
  }
  if (action is MiningAction) return action.media;
  if (action is ThievingAction) return action.media;
  if (action is AgilityObstacle) return 'assets/media/main/stamina.png';
  if (action is AstrologyAction) return action.media;
  if (action is AltMagicAction) return action.media;
  // For other action types, return null (no direct media).
  return null;
}

/// Returns the primary item ID for an action (output or input).
/// Used for looking up item images when the action has no direct media.
MelvorId? primaryItemIdForAction(SkillAction action) {
  // Check for actions with productId fields.
  if (action is FishingAction) return action.productId;
  if (action is CookingAction) return action.productId;
  if (action is FiremakingAction) return action.logId;
  if (action is SummoningAction) return action.productId;
  if (action is SmithingAction) return action.productId;
  if (action is FletchingAction) return action.productId;
  if (action is CraftingAction) return action.productId;
  if (action is HerbloreAction) return action.productId;
  if (action is RunecraftingAction) return action.productId;
  // Fall back to first output or input.
  if (action.outputs.isNotEmpty) return action.outputs.keys.first;
  if (action.inputs.isNotEmpty) return action.inputs.keys.first;
  return null;
}

/// Displays an image for an action, using its media path if available,
/// or falling back to the primary item image.
class ActionImage extends StatelessWidget {
  const ActionImage({required this.action, this.size = 24, super.key});

  final SkillAction action;
  final double size;

  @override
  Widget build(BuildContext context) {
    // First try direct media path from action.
    final media = mediaForAction(action);
    if (media != null && media.isNotEmpty) {
      return CachedImage(assetPath: media, size: size);
    }

    // Fall back to looking up the primary item's image.
    final itemId = primaryItemIdForAction(action);
    if (itemId != null) {
      final items = context.state.registries.items;
      final item = items.all.where((i) => i.id == itemId).firstOrNull;
      if (item != null) {
        return ItemImage(item: item, size: size);
      }
    }

    // Last resort: show a generic icon.
    return SizedBox(
      width: size,
      height: size,
      child: Icon(
        Icons.circle,
        size: size * 0.67,
        color: Style.iconColorDefault,
      ),
    );
  }
}
