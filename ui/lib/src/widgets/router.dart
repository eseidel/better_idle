import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/screens/agility.dart';
import 'package:ui/src/screens/alt_magic.dart';
import 'package:ui/src/screens/astrology.dart';
import 'package:ui/src/screens/bank.dart';
import 'package:ui/src/screens/combat.dart';
import 'package:ui/src/screens/constellation_detail.dart';
import 'package:ui/src/screens/cooking.dart';
import 'package:ui/src/screens/crafting.dart';
import 'package:ui/src/screens/debug.dart';
import 'package:ui/src/screens/farming.dart';
import 'package:ui/src/screens/firemaking.dart';
import 'package:ui/src/screens/fishing.dart';
import 'package:ui/src/screens/fletching.dart';
import 'package:ui/src/screens/herblore.dart';
import 'package:ui/src/screens/mining.dart';
import 'package:ui/src/screens/runecrafting.dart';
import 'package:ui/src/screens/shop.dart';
import 'package:ui/src/screens/smithing.dart';
import 'package:ui/src/screens/statistics.dart';
import 'package:ui/src/screens/summoning.dart';
import 'package:ui/src/screens/thieving.dart';
import 'package:ui/src/screens/township.dart';
import 'package:ui/src/screens/woodcutting.dart';

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
      path: '/township',
      name: 'township',
      builder: (context, _) => const TownshipPage(),
    ),
    GoRoute(
      path: '/farming',
      name: 'farming',
      builder: (context, _) => const FarmingPage(),
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
      path: '/agility',
      name: 'agility',
      builder: (context, _) => const AgilityPage(),
    ),
    GoRoute(
      path: '/summoning',
      name: 'summoning',
      builder: (context, _) => const SummoningPage(),
    ),
    GoRoute(
      path: '/astrology',
      name: 'astrology',
      builder: (context, _) => const AstrologyPage(),
      routes: [
        GoRoute(
          path: ':constellationId',
          name: 'constellation',
          builder: (context, state) {
            final id = state.pathParameters['constellationId']!;
            final melvorId = MelvorId.fromJson(id);
            return ConstellationDetailPage(constellationId: melvorId);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/alt_magic',
      name: 'alt_magic',
      builder: (context, _) => const AltMagicPage(),
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
    GoRoute(
      path: '/statistics',
      name: 'statistics',
      builder: (context, _) => const StatisticsPage(),
    ),
  ],
);
