import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:flutter/material.dart';

/// A widget that displays a page header image with loading and fallback.
///
/// Used for non-skill pages like Shop and Bank.
class PageImage extends StatelessWidget {
  const PageImage({
    required this.pageId,
    required this.fallbackIcon,
    this.size = 24,
    super.key,
  });

  /// The page ID (e.g., "bank", "shop").
  final String pageId;

  /// The icon to show as fallback while loading or on error.
  final IconData fallbackIcon;

  /// The size of the image (width and height).
  final double size;

  String get _assetPath => 'assets/media/main/${pageId}_header.png';

  @override
  Widget build(BuildContext context) {
    return CachedImage(
      assetPath: _assetPath,
      size: size,
      placeholder: _buildFallback(),
      fallback: _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(fallbackIcon, size: size * 0.6, color: Colors.grey),
      ),
    );
  }
}
