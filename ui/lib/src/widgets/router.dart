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
import 'package:ui/src/screens/save_slots.dart';
import 'package:ui/src/screens/shop.dart';
import 'package:ui/src/screens/smithing.dart';
import 'package:ui/src/screens/statistics.dart';
import 'package:ui/src/screens/summoning.dart';
import 'package:ui/src/screens/thieving.dart';
import 'package:ui/src/screens/township.dart';
import 'package:ui/src/screens/woodcutting.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/navigation_drawer.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Shorthand for a simple named route with a const page widget.
GoRoute _route(String name, Widget page) =>
    GoRoute(path: '/$name', name: name, builder: (context, _) => page);

final GoRouter router = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/bank',
  routes: <RouteBase>[
    GoRoute(path: '/', redirect: (context, state) => '/bank'),
    ShellRoute(
      builder: (context, state, child) {
        return _ResponsiveShell(child: child);
      },
      routes: [
        _route('bank', const BankPage()),
        _route('woodcutting', const WoodcuttingPage()),
        _route('firemaking', const FiremakingPage()),
        _route('fishing', const FishingPage()),
        _route('cooking', const CookingPage()),
        _route('mining', const MiningPage()),
        _route('smithing', const SmithingPage()),
        _route('thieving', const ThievingPage()),
        _route('fletching', const FletchingPage()),
        _route('crafting', const CraftingPage()),
        _route('herblore', const HerblorePage()),
        _route('township', const TownshipPage()),
        _route('farming', const FarmingPage()),
        _route('runecrafting', const RunecraftingPage()),
        _route('combat', const CombatPage()),
        _route('agility', const AgilityPage()),
        _route('summoning', const SummoningPage()),
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
        _route('alt_magic', const AltMagicPage()),
        _route('shop', const ShopPage()),
        _route('debug', const DebugPage()),
        _route('statistics', const StatisticsPage()),
        _route('save_slots', const SaveSlotsPage()),
      ],
    ),
  ],
);

/// Shell widget that shows a persistent sidebar on wide screens.
///
/// On narrow screens this is a no-op pass-through; the child pages handle
/// their own drawer via [GameScaffold] / [AppNavigationDrawer].
class _ResponsiveShell extends StatelessWidget {
  const _ResponsiveShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= sidebarBreakpoint;
    if (!isWide) return child;

    return Row(
      children: [
        const SizedBox(
          width: sidebarWidth,
          child: Material(child: NavigationContent(isDrawer: false)),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ],
    );
  }
}
