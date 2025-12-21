import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A widget that displays an item's icon image with loading and fallback.
///
/// While the image is loading, displays a hourglass icon.
/// If the image fails to load or the item has no media path, shows fallback.
class ItemImage extends StatelessWidget {
  const ItemImage({required this.item, this.size = 32, super.key});

  /// The item whose icon to display.
  final Item item;

  /// The size of the image (width and height).
  final double size;

  @override
  Widget build(BuildContext context) {
    final media = item.media;
    if (media == null) {
      return _buildFallback();
    }
    return CachedImage(assetPath: media, size: size);
  }

  Widget _buildFallback() {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          Icons.help_outline,
          size: size * 0.6,
          color: Style.iconColorDefault,
        ),
      ),
    );
  }
}
