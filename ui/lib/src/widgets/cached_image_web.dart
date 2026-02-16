import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/style.dart';

/// A widget that displays an image from the Melvor CDN using network requests.
///
/// Web implementation — uses [Image.network] directly since the browser
/// handles HTTP caching.
class CachedImage extends StatelessWidget {
  const CachedImage({
    required this.assetPath,
    this.size = 32,
    this.placeholder,
    this.fallback,
    super.key,
  });

  /// The asset path relative to the CDN (e.g., "assets/media/bank/logs.png").
  /// If null, the fallback widget is shown immediately.
  final String? assetPath;

  /// The size of the image (width and height).
  final double size;

  /// Widget to show while loading. Defaults to an hourglass icon.
  final Widget? placeholder;

  /// Widget to show if loading fails. Defaults to a question mark icon.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (assetPath == null) {
      return _buildFallback();
    }

    return Image.network(
      '$cdnBase/$assetPath',
      width: size,
      height: size,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) => _buildFallback(),
    );
  }

  Widget _buildPlaceholder() {
    return placeholder ??
        SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              Icons.hourglass_empty,
              size: size * 0.6,
              color: Style.iconColorDefault,
            ),
          ),
        );
  }

  Widget _buildFallback() {
    return fallback ??
        SizedBox(
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
