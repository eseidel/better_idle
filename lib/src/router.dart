import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/inventory.dart';
import 'screens/woodcutting.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/inventory',
  routes: <RouteBase>[
    GoRoute(path: '/', redirect: (context, state) => '/inventory'),
    GoRoute(
      path: '/inventory',
      name: 'inventory',
      builder: (context, _) => const InventoryPage(),
    ),
    GoRoute(
      path: '/woodcutting',
      name: 'woodcutting',
      builder: (context, _) => const WoodcuttingPage(),
    ),
  ],
);
