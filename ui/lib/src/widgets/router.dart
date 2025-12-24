import 'package:better_idle/src/screens/bank.dart';
import 'package:better_idle/src/screens/combat.dart';
import 'package:better_idle/src/screens/cooking.dart';
import 'package:better_idle/src/screens/crafting.dart';
import 'package:better_idle/src/screens/debug.dart';
import 'package:better_idle/src/screens/firemaking.dart';
import 'package:better_idle/src/screens/fishing.dart';
import 'package:better_idle/src/screens/fletching.dart';
import 'package:better_idle/src/screens/herblore.dart';
import 'package:better_idle/src/screens/mining.dart';
import 'package:better_idle/src/screens/runecrafting.dart';
import 'package:better_idle/src/screens/shop.dart';
import 'package:better_idle/src/screens/smithing.dart';
import 'package:better_idle/src/screens/thieving.dart';
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
      path: '/cooking',
      name: 'cooking',
      builder: (context, _) => const CookingPage(),
    ),
    GoRoute(
      path: '/mining',
      name: 'mining',
      builder: (context, _) => const MiningPage(),
    ),
    GoRoute(
      path: '/smithing',
      name: 'smithing',
      builder: (context, _) => const SmithingPage(),
    ),
    GoRoute(
      path: '/thieving',
      name: 'thieving',
      builder: (context, _) => const ThievingPage(),
    ),
    GoRoute(
      path: '/fletching',
      name: 'fletching',
      builder: (context, _) => const FletchingPage(),
    ),
    GoRoute(
      path: '/crafting',
      name: 'crafting',
      builder: (context, _) => const CraftingPage(),
    ),
    GoRoute(
      path: '/herblore',
      name: 'herblore',
      builder: (context, _) => const HerblorePage(),
    ),
    GoRoute(
      path: '/runecrafting',
      name: 'runecrafting',
      builder: (context, _) => const RunecraftingPage(),
    ),
    GoRoute(
      path: '/combat',
      name: 'combat',
      builder: (context, _) => const CombatPage(),
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
