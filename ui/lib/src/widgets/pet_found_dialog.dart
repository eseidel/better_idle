import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A celebratory dialog shown when the player finds a pet.
class PetFoundDialog extends StatelessWidget {
  const PetFoundDialog({
    required this.pet,
    required this.modifierMetadata,
    super.key,
  });

  final Pet pet;
  final ModifierMetadataRegistry modifierMetadata;

  @override
  Widget build(BuildContext context) {
    final descriptions = _formatModifiers(pet, modifierMetadata);

    return AlertDialog(
      title: Column(
        children: [
          CachedImage(assetPath: pet.media, size: 80),
          const SizedBox(height: 12),
          const Text('Pet Found!'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pet.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (descriptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final desc in descriptions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 14,
                      color: Style.textColorSuccess,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }

  List<String> _formatModifiers(Pet pet, ModifierMetadataRegistry registry) {
    final descriptions = <String>[];
    for (final mod in pet.modifiers.modifiers) {
      for (final entry in mod.entries) {
        String? skillName;
        String? currencyName;
        final scope = entry.scope;
        if (scope != null) {
          if (scope.skillId != null) {
            skillName = Skill.fromId(scope.skillId!).name;
          }
          if (scope.currencyId != null) {
            currencyName = Currency.fromId(scope.currencyId!).name;
          }
        }
        descriptions.add(
          registry.formatDescription(
            name: mod.name,
            value: entry.value,
            skillName: skillName,
            currencyName: currencyName,
          ),
        );
      }
    }
    return descriptions;
  }
}
