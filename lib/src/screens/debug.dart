import 'package:flutter/material.dart';

import '../state.dart';
import '../widgets/navigation_drawer.dart';
import '../widgets/welcome_back_dialog.dart';

class DebugPage extends StatelessWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    final duration = const Duration(seconds: 10);
    return Scaffold(
      appBar: AppBar(title: const Text('Debug')),
      drawer: const AppNavigationDrawer(),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () =>
                  _showWelcomeBackDialog(context, duration: duration),
              child: Text(
                'Show Welcome Back Dialog (${duration.inSeconds} seconds)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWelcomeBackDialog(
    BuildContext context, {
    required Duration duration,
  }) async {
    // Dispatch action to advance by the given duration and get changes
    final ticks = ticksFromDuration(duration);
    final action = AdvanceTicksAction(ticks: ticks);
    await StoreProvider.dispatch<GlobalState>(context, action);
    final changes = action.changes ?? Changes.empty();
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => WelcomeBackDialog(changes: changes),
      );
    }
  }
}
