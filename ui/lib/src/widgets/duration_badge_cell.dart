import 'package:flutter/material.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/count_badge_cell.dart';
import 'package:ui/src/widgets/style.dart';

/// A small square widget displaying a timer icon with a duration badge.
///
/// Shows a timer icon centered on a background with a border. The duration
/// in seconds is displayed in a pill-shaped badge overlapping the bottom
/// border.
class DurationBadgeCell extends StatelessWidget {
  const DurationBadgeCell({
    required this.seconds,
    this.inradius = TextBadgeCell.defaultInradius,
    super.key,
  });

  final int seconds;

  /// The size of the cell (width and height). Defaults to 48.
  final double inradius;

  @override
  Widget build(BuildContext context) {
    final iconSize = inradius * 28 / TextBadgeCell.defaultInradius;
    return TextBadgeCell(
      backgroundColor: Style.durationBadgeBackgroundColor,
      text: '${seconds}s',
      inradius: inradius,
      child: Center(
        child: CachedImage(
          assetPath: 'assets/media/main/timer.png',
          size: iconSize,
        ),
      ),
    );
  }
}
