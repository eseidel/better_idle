import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog shown when the player dies.
/// Displays the death penalty result (what was lost or if they were lucky).
class YouDiedDialog extends StatelessWidget {
  const YouDiedDialog({
    required this.lostOnDeath,
    required this.registries,
    super.key,
  });

  /// Items lost on death (may be empty if player was lucky).
  final Counts<MelvorId> lostOnDeath;

  /// Registries for looking up item info.
  final Registries registries;

  @override
  Widget build(BuildContext context) {
    final wasLucky = lostOnDeath.isEmpty;

    return AlertDialog(
      title: const Column(
        children: [
          Icon(Icons.dangerous, size: 48, color: Style.errorColor),
          SizedBox(height: 8),
          Text('You Died!'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wasLucky) ...[
              const Text(
                'Luck was on your side today.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('You lost nothing.'),
            ] else ...[
              const Text(
                'You lost the following equipment:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Style.errorColor,
                ),
              ),
              const SizedBox(height: 16),
              ...lostOnDeath.entries.map((entry) {
                final item = registries.items.byId(entry.key);
                final count = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      ItemImage(item: item),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          count > 1 ? '${item.name} x$count' : item.name,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                );
              }),
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
}
