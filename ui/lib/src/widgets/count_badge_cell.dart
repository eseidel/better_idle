import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A bordered cell with rounded corners and an optional count badge.
class CountBadgeCell extends StatelessWidget {
  const CountBadgeCell({
    required this.child,
    this.onTap,
    this.radius = 8.0,
    this.backgroundColor = Colors.transparent,
    this.borderColor,
    this.count,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color backgroundColor;
  final Color? borderColor;
  final int? count;

  Widget _buildCountBadge({required int count, required double badgeHeight}) {
    return Container(
      height: badgeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(badgeHeight / 2),
      ),
      child: Text(
        approximateCountString(count),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const badgeHeight = 16.0;
    const badgeOverlap = badgeHeight / 2;
    final effectiveBorderColor = borderColor ?? backgroundColor;

    return Padding(
      // Add padding at bottom to make room for the overlapping badge
      padding: count != null
          ? const EdgeInsets.only(bottom: badgeOverlap)
          : EdgeInsets.zero,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main container with InkWell inside
          Material(
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
          // Count badge overlapping the bottom border
          if (count != null)
            Positioned(
              bottom: -badgeOverlap,
              left: 0,
              right: 0,
              child: Center(
                child: _buildCountBadge(
                  count: count!,
                  badgeHeight: badgeHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
