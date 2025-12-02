import 'package:better_idle/src/screens/debug.dart';
import 'package:better_idle/src/screens/inventory.dart';
import 'package:better_idle/src/screens/woodcutting.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    GoRoute(
      path: '/debug',
      name: 'debug',
      builder: (context, _) => const DebugPage(),
    ),
  ],
);
