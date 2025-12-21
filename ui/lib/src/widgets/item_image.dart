import 'dart:io';

import 'package:better_idle/src/services/image_cache_service.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A widget that displays an item's icon image with loading and fallback.
///
/// While the image is loading, displays a hourglass icon.
/// If the image fails to load or the item has no media path, shows fallback.
class ItemImage extends StatefulWidget {
  const ItemImage({required this.item, this.size = 32, super.key});

  /// The item whose icon to display.
  final Item item;

  /// The size of the image (width and height).
  final double size;

  @override
  State<ItemImage> createState() => _ItemImageState();
}

class _ItemImageState extends State<ItemImage> {
  File? _cachedFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(ItemImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _cachedFile = null;
      _isLoading = false;
      _loadImage();
    }
  }

  void _loadImage() {
    final media = widget.item.media;
    if (media == null) {
      return;
    }

    // Check if already cached.
    final cached = imageCacheService.getCachedFile(media);
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

    imageCacheService.ensureAsset(media).then((file) {
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
      return _buildLoading();
    }

    return _buildFallback();
  }

  Widget _buildLoading() {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Icon(
          Icons.hourglass_empty,
          size: widget.size * 0.6,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: Icon(
          Icons.help_outline,
          size: widget.size * 0.6,
          color: Colors.grey,
        ),
      ),
    );
  }
}
