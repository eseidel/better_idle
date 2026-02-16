import 'package:flutter/widgets.dart';
import 'package:logic/logic.dart';

/// Holds the platform-specific cache and image service configuration.
///
/// On native platforms, [wrapChild] adds an ImageCacheServiceProvider.
/// On web, [wrapChild] is a no-op pass-through.
class CacheServices {
  CacheServices({
    required this.cache,
    required Widget Function(Widget) wrapChild,
    required void Function() dispose,
  }) : _wrapChild = wrapChild,
       _dispose = dispose;

  final Cache cache;
  final Widget Function(Widget) _wrapChild;
  final void Function() _dispose;

  Widget wrapChild(Widget child) => _wrapChild(child);
  void dispose() => _dispose();
}
