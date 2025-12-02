import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/welcome_back_dialog.dart';
import 'package:flutter/material.dart';

class DebugPage extends StatelessWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    const duration = Duration(seconds: 30);
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
    final timeAway = action.timeAway;
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => WelcomeBackDialog(timeAway: timeAway),
      );
    }
  }
}
