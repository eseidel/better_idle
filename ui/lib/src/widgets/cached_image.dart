import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ui/src/services/image_cache_service.dart';
import 'package:ui/src/widgets/style.dart';

/// A widget that displays an image from the Melvor CDN with caching.
///
/// Shows a placeholder while loading and a fallback if the image fails to load
/// or if [assetPath] is null.
class CachedImage extends StatefulWidget {
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
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  File? _cachedFile;
  bool _isLoading = false;
  String? _lastAssetPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load image when dependencies change or on first build
    if (_lastAssetPath != widget.assetPath) {
      _lastAssetPath = widget.assetPath;
      _cachedFile = null;
      _isLoading = false;
      _loadImage();
    }
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _lastAssetPath = widget.assetPath;
      _cachedFile = null;
      _isLoading = false;
      _loadImage();
    }
  }

  void _loadImage() {
    final assetPath = widget.assetPath;
    if (assetPath == null) return;

    final service = context.imageCacheService;

    // Check if already cached.
    final cached = service.getCachedFile(assetPath);
    if (cached != null) {
      setState(() {
        _cachedFile = cached;
      });
      return;
    }

    // Start loading.
    setState(() {
      _isLoading = true;
    });

    service.ensureAsset(assetPath).then((file) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _cachedFile = file;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show fallback if no asset path.
    if (widget.assetPath == null) {
      return _buildFallback();
    }

    // Show cached image if available.
    if (_cachedFile != null) {
      return Image.file(
        _cachedFile!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback();
        },
      );
    }

    // Show loading or fallback.
    if (_isLoading) {
      return _buildPlaceholder();
    }

    return _buildFallback();
  }

  Widget _buildPlaceholder() {
    return widget.placeholder ??
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: Icon(
              Icons.hourglass_empty,
              size: widget.size * 0.6,
              color: Style.iconColorDefault,
            ),
          ),
        );
  }

  Widget _buildFallback() {
    return widget.fallback ??
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: Icon(
              Icons.help_outline,
              size: widget.size * 0.6,
              color: Style.iconColorDefault,
            ),
          ),
        );
  }
}
