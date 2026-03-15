import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/item_count_row.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog shown after opening one or more openable items.
/// Displays how many were opened and the combined drops received.
/// Each drop row slides in from the left with a staggered delay.
class OpenResultDialog extends StatefulWidget {
  const OpenResultDialog({
    required this.itemName,
    required this.result,
    super.key,
  });

  final String itemName;
  final OpenResult result;

  @override
  State<OpenResultDialog> createState() => _OpenResultDialogState();
}

class _OpenResultDialogState extends State<OpenResultDialog>
    with TickerProviderStateMixin {
  static const _staggerDelay = Duration(milliseconds: 200);
  static const _slideDuration = Duration(milliseconds: 300);

  late final List<AnimationController> _controllers;
  late final List<Animation<Offset>> _slideAnimations;
  late final List<Animation<double>> _fadeAnimations;

  @override
  void initState() {
    super.initState();
    final dropCount = widget.result.drops.length;
    _controllers = List.generate(dropCount, (i) {
      return AnimationController(vsync: this, duration: _slideDuration);
    });
    _slideAnimations = _controllers.map((c) {
      return Tween<Offset>(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeOut));
    }).toList();
    _fadeAnimations = _controllers.map((c) {
      return CurvedAnimation(parent: c, curve: Curves.easeOut);
    }).toList();

    unawaited(_startAnimations());
  }

  Future<void> _startAnimations() async {
    for (final controller in _controllers) {
      unawaited(controller.forward());
      await Future<void>.delayed(_staggerDelay);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _openedText {
    final count = widget.result.openedCount;
    final plural = count > 1 ? 's' : '';
    return 'Opened $count ${widget.itemName}$plural';
  }

  @override
  Widget build(BuildContext context) {
    final dropEntries = widget.result.drops.entries.toList();
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
            for (var i = 0; i < dropEntries.length; i++)
              SlideTransition(
                position: _slideAnimations[i],
                child: FadeTransition(
                  opacity: _fadeAnimations[i],
                  child: ItemCountRow(
                    item: dropEntries[i].key,
                    count: dropEntries[i].value,
                    countColor: Style.successColor,
                  ),
                ),
              ),
            if (widget.result.error != null) ...[
              const SizedBox(height: 16),
              Text(
                widget.result.error!,
                style: TextStyle(
                  color: Style.shopPurchasedColor,
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
