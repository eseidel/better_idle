import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';

/// A widget that displays a skill's icon image with loading and fallback.
///
/// While the image is loading, displays the skill's fallback icon.
/// If the image fails to load, shows the fallback icon.
class SkillImage extends StatelessWidget {
  const SkillImage({required this.skill, this.size = 32, super.key});

  /// The skill whose icon to display.
  final Skill skill;

  /// The size of the image (width and height).
  final double size;

  @override
  Widget build(BuildContext context) {
    return CachedImage(
      assetPath: skill.assetPath,
      size: size,
      placeholder: Icon(Icons.hourglass_empty, size: size),
      fallback: Icon(Icons.help_outline, size: size),
    );
  }
}
