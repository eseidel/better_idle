import 'package:better_idle/src/screens/bank.dart';
import 'package:better_idle/src/screens/debug.dart';
import 'package:better_idle/src/screens/firemaking.dart';
import 'package:better_idle/src/screens/fishing.dart';
import 'package:better_idle/src/screens/mining.dart';
import 'package:better_idle/src/screens/shop.dart';
import 'package:better_idle/src/screens/woodcutting.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/bank',
  routes: <RouteBase>[
    GoRoute(path: '/', redirect: (context, state) => '/bank'),
    GoRoute(
      path: '/bank',
      name: 'bank',
      builder: (context, _) => const BankPage(),
    ),
    GoRoute(
      path: '/woodcutting',
      name: 'woodcutting',
      builder: (context, _) => const WoodcuttingPage(),
    ),
    GoRoute(
      path: '/firemaking',
      name: 'firemaking',
      builder: (context, _) => const FiremakingPage(),
    ),
    GoRoute(
      path: '/fishing',
      name: 'fishing',
      builder: (context, _) => const FishingPage(),
    ),
    GoRoute(
      path: '/mining',
      name: 'mining',
      builder: (context, _) => const MiningPage(),
    ),
    GoRoute(
      path: '/shop',
      name: 'shop',
      builder: (context, _) => const ShopPage(),
    ),
    GoRoute(
      path: '/debug',
      name: 'debug',
      builder: (context, _) => const DebugPage(),
    ),
  ],
);
