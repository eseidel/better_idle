import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A dialog shown after opening one or more openable items.
/// Displays how many were opened and the combined drops received.
class OpenResultDialog extends StatelessWidget {
  const OpenResultDialog({
    required this.itemName,
    required this.result,
    super.key,
  });

  final String itemName;
  final OpenResult result;

  String get _openedText {
    final count = result.openedCount;
    final plural = count > 1 ? 's' : '';
    return 'Opened $count $itemName$plural';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Items Opened'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _openedText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Received:'),
            const SizedBox(height: 8),
            ...result.drops.entries.map((entry) {
              final itemName = entry.key;
              final count = entry.value;
              return Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Text(
                  '${approximateCountString(count)} $itemName',
                  style: const TextStyle(color: Colors.green),
                ),
              );
            }),
            if (result.error != null) ...[
              const SizedBox(height: 16),
              Text(
                result.error!,
                style: TextStyle(
                  color: Colors.orange[700],
                  fontStyle: FontStyle.italic,
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
}
