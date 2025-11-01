import 'package:flutter/material.dart';

import '../router.dart';

/// The title screen for the game.
class TitleScreen extends StatelessWidget {
  /// Constructs a [TitleScreen]
  const TitleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Spacer(),
            Expanded(flex: 2, child: Text('Better Idle')),
            const Spacer(),
            ElevatedButton(
              onPressed: () => router.goNamed('inventory'),
              child: const Text('Inventory'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => router.goNamed('woodcutting'),
              child: const Text('Woodcutting'),
            ),
            const SizedBox(height: 16),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
