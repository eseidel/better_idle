import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

/// A navigation drawer for the game that provides navigation to different screens.
class AppNavigationDrawer extends StatelessWidget {
  /// Constructs an [AppNavigationDrawer]
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(
              'Better Idle',
              style: TextStyle(color: Colors.white, fontSize: 24),
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
