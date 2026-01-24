import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/style.dart';

/// A bordered cell with rounded corners and an optional text badge.
///
/// The cell is a square with side length [inradius]. The badge overlaps the
/// bottom edge, extending below by half the badge height. The total widget
/// height is [inradius] + [badgeOverlap] when a badge is shown.
class TextBadgeCell extends StatelessWidget {
  const TextBadgeCell({
    required this.child,
    this.inradius = defaultInradius,
    this.onTap,
    this.backgroundColor = Style.transparentColor,
    this.borderColor,
    this.badgeBackgroundColor,
    this.text,
    super.key,
  });

  /// Default inradius size for badge cells.
  static const double defaultInradius = 48;

  /// Small inradius size for compact badge cells.
  static const double smallInradius = 32;

  /// Large inradius size for prominent badge cells.
  static const double largeInradius = 64;

  /// Badge height constant.
  static const double badgeHeight = 16;

  /// How much the badge extends below the cell.
  static const double badgeOverlap = badgeHeight / 2;

  /// Border radius for the cell.
  static final BorderRadius borderRadius = BorderRadius.circular(8);

  final Widget child;
  final double inradius;
  final VoidCallback? onTap;
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
    final totalHeight = text != null ? inradius + badgeOverlap : inradius;

    return SizedBox(
      width: inradius,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main square cell
          SizedBox(
            width: inradius,
            height: inradius,
            child: Material(
              color: backgroundColor,
              borderRadius: borderRadius,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
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
    this.inradius = TextBadgeCell.defaultInradius,
    this.onTap,
    this.backgroundColor = Style.transparentColor,
    this.borderColor,
    this.badgeBackgroundColor,
    this.count,
    super.key,
  });

  final Widget child;
  final double inradius;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? badgeBackgroundColor;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return TextBadgeCell(
      inradius: inradius,
      onTap: onTap,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      badgeBackgroundColor: badgeBackgroundColor,
      text: count != null ? approximateCountString(count!) : null,
      child: child,
    );
  }
}
