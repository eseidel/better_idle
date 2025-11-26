import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/inventory.dart';
import 'screens/title.dart';
import 'screens/woodcutting.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: navigatorKey,
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'root',
      builder: (BuildContext context, GoRouterState state) {
        return const TitleScreen();
      },
      routes: [
        GoRoute(
          path: 'inventory',
          name: 'inventory',
          builder: (context, _) => const InventoryPage(),
        ),
        GoRoute(
          path: 'woodcutting',
          name: 'woodcutting',
          builder: (context, _) => const WoodcuttingPage(),
        ),
      ],
    ),
  ],
);
