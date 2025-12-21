import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/skills.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

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
      placeholder: _buildFallback(),
      fallback: _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          skill.icon,
          size: size * 0.6,
          color: Style.iconColorDefault,
        ),
      ),
    );
  }
}
