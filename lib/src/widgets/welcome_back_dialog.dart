import 'package:flutter/material.dart';

import '../state.dart';

/// A dialog shown when returning to the app after being away.
/// Displays the changes (inventory and XP) that occurred while away.
class WelcomeBackDialog extends StatelessWidget {
  const WelcomeBackDialog({required this.changes, super.key});

  final Changes changes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Welcome Back!'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('While you were away, you gained:'),
            const SizedBox(height: 16),
            if (changes.inventoryChanges.isNotEmpty) ...[
              const Text(
                'Items:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...changes.inventoryChanges.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('+${entry.value} ${entry.key}'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (changes.xpChanges.isNotEmpty) ...[
              const Text(
                'Experience:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...changes.xpChanges.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('+${entry.value} ${entry.key} xp'),
                ),
              ),
            ],
            if (changes.isEmpty) ...[
              const Text('Nothing new happened while you were away.'),
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
