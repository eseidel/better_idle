import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A bordered cell with rounded corners and an optional text badge.
class TextBadgeCell extends StatelessWidget {
  const TextBadgeCell({
    required this.child,
    this.onTap,
    this.radius = 8.0,
    this.backgroundColor = Style.transparentColor,
    this.borderColor,
    this.badgeBackgroundColor,
    this.text,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? badgeBackgroundColor;
  final String? text;

  Widget _buildTextBadge({required String text, required double badgeHeight}) {
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
    const badgeHeight = 16.0;
    const badgeOverlap = badgeHeight / 2;
    final effectiveBorderColor = borderColor ?? backgroundColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main container with InkWell inside, forced to be square
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(radius),
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(radius),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: effectiveBorderColor,
                            width: 2,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                  // Text badge overlapping the bottom border
                  if (text != null)
                    Positioned(
                      bottom: -badgeOverlap,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildTextBadge(
                          text: text!,
                          badgeHeight: badgeHeight,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Reserve space for the badge overlap
        if (text != null) const SizedBox(height: badgeOverlap),
      ],
    );
  }
}

/// A bordered cell with rounded corners and an optional count badge.
class CountBadgeCell extends StatelessWidget {
  const CountBadgeCell({
    required this.child,
    this.onTap,
    this.radius = 8.0,
    this.backgroundColor = Style.transparentColor,
    this.borderColor,
    this.badgeBackgroundColor,
    this.count,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? badgeBackgroundColor;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return TextBadgeCell(
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
