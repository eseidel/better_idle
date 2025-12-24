import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A bordered cell with rounded corners and an optional text badge.
///
/// The cell is a square with side length [apothem]. The badge overlaps the
/// bottom edge, extending below by half the badge height. The total widget
/// height is [apothem] + [badgeOverlap] when a badge is shown.
class TextBadgeCell extends StatelessWidget {
  const TextBadgeCell({
    required this.child,
    this.apothem = defaultApothem,
    this.onTap,
    this.radius = 8.0,
    this.backgroundColor = Style.transparentColor,
    this.borderColor,
    this.badgeBackgroundColor,
    this.text,
    super.key,
  });

  /// Default apothem size for badge cells.
  static const double defaultApothem = 48;

  /// Small apothem size for compact badge cells.
  static const double smallApothem = 32;

  /// Large apothem size for prominent badge cells.
  static const double largeApothem = 64;

  /// Badge height constant.
  static const double badgeHeight = 16;

  /// How much the badge extends below the cell.
  static const double badgeOverlap = badgeHeight / 2;

  final Widget child;
  final double apothem;
  final VoidCallback? onTap;
  final double radius;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? badgeBackgroundColor;
  final String? text;

  Widget _buildTextBadge({required String text}) {
    return Container(
      height: badgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: badgeBackgroundColor ?? Style.badgeBackgroundColor,
        borderRadius: BorderRadius.circular(badgeHeight / 2),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          style: const TextStyle(
            color: Style.badgeTextColor,
            fontSize: 9,
            fontWeight: FontWeight.w300,
            height: 1,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? backgroundColor;
    final totalHeight = text != null ? apothem + badgeOverlap : apothem;

    return SizedBox(
      width: apothem,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main square cell
          SizedBox(
            width: apothem,
            height: apothem,
            child: Material(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(radius),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: effectiveBorderColor, width: 2),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
          // Text badge overlapping the bottom border
          if (text != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(child: _buildTextBadge(text: text!)),
            ),
        ],
      ),
    );
  }
}

/// A bordered cell with rounded corners and an optional count badge.
class CountBadgeCell extends StatelessWidget {
  const CountBadgeCell({
    required this.child,
    this.apothem = TextBadgeCell.defaultApothem,
    this.onTap,
    this.radius = 8.0,
    this.backgroundColor = Style.transparentColor,
    this.borderColor,
    this.badgeBackgroundColor,
    this.count,
    super.key,
  });

  final Widget child;
  final double apothem;
  final VoidCallback? onTap;
  final double radius;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? badgeBackgroundColor;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return TextBadgeCell(
      apothem: apothem,
      onTap: onTap,
      radius: radius,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      badgeBackgroundColor: badgeBackgroundColor,
      text: count != null ? approximateCountString(count!) : null,
      child: child,
    );
  }
}
