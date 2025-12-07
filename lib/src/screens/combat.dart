import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:flutter/material.dart';

class CombatPage extends StatelessWidget {
  const CombatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Combat')),
      drawer: const AppNavigationDrawer(),
      body: const Center(
        child: Text('Combat coming soon...'),
      ),
    );
  }
}
