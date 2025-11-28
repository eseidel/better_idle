import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'context_extensions.dart';
import 'router.dart';

/// A navigation drawer for the game that provides navigation to different screens.
class AppNavigationDrawer extends StatelessWidget {
  /// Constructs an [AppNavigationDrawer]
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;
    final gp = context.state.gp;
    final formatter = NumberFormat('#,##0');

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'Better Idle',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatter.format(gp)} GP',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Inventory'),
            selected: currentLocation == '/inventory',
            onTap: () {
              Navigator.pop(context);
              router.goNamed('inventory');
            },
          ),
          ListTile(
            leading: const Icon(Icons.forest),
            title: const Text('Woodcutting'),
            selected: currentLocation == '/woodcutting',
            onTap: () {
              Navigator.pop(context);
              router.goNamed('woodcutting');
            },
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Debug'),
            selected: currentLocation == '/debug',
            onTap: () {
              Navigator.pop(context);
              router.goNamed('debug');
            },
          ),
        ],
      ),
    );
  }
}
