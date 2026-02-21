import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/page_image.dart';
import 'package:ui/src/widgets/router.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skills.dart';
import 'package:ui/src/widgets/style.dart';

/// Provides the navigation display mode to descendant widgets.
///
/// When [isDrawer] is true, navigation items call [Navigator.pop] before
/// routing (to close the drawer overlay). When false (permanent sidebar),
/// they navigate directly.
class NavigationMode extends InheritedWidget {
  const NavigationMode({
    required this.isDrawer,
    required super.child,
    super.key,
  });

  final bool isDrawer;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<NavigationMode>()
            ?.isDrawer ??
        true;
  }

  /// Closes the drawer (if open) and navigates to the named route.
  static void navigateTo(BuildContext context, String routeName) {
    if (of(context)) Navigator.pop(context);
    router.goNamed(routeName);
  }

  @override
  bool updateShouldNotify(NavigationMode oldWidget) =>
      isDrawer != oldWidget.isDrawer;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Style.textColorSecondary,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Style.textColorSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A navigation tile for non-skill pages (Bank, Shop, etc.).
///
/// This must be a separate widget (not an inline ListTile) so that its
/// [build] context is below [NavigationMode] in the widget tree. Without
/// this, [NavigationMode.of] falls back to `true` and calls
/// [Navigator.pop] on the permanent sidebar, causing a nav stack underflow.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.routeName,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String routeName;
  final Widget title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: leading,
      title: title,
      trailing: trailing,
      selected: currentLocation == '/$routeName',
      onTap: () => NavigationMode.navigateTo(context, routeName),
    );
  }
}

class SkillTile extends StatelessWidget {
  const SkillTile({required this.skill, super.key, this.selected = false});

  final Skill skill;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;
    final routeName = skill.routeName;
    final activeSkill = context.state.activeSkill();
    final isActiveSkill = activeSkill == skill;
    final isSelected = selected || currentLocation == '/$routeName';
    final skillState = context.state.skillState(skill);
    final level = skillState.skillLevel;

    const valueStyle = TextStyle(color: Style.currencyValueColor);
    final slayerCoins = context.state.currency(Currency.slayerCoins);
    final titleWidget = switch (skill) {
      Skill.hitpoints => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: skill.name),
            TextSpan(text: ' (${context.state.playerHp})', style: valueStyle),
          ],
        ),
      ),
      Skill.prayer => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${skill.name} '),
            TextSpan(text: '${context.state.prayerPoints}', style: valueStyle),
          ],
        ),
      ),
      Skill.slayer => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${skill.name} '),
          CachedImage(assetPath: Currency.slayerCoins.assetPath, size: 16),
          const SizedBox(width: 2),
          Text(approximateCreditString(slayerCoins), style: valueStyle),
        ],
      ),
      _ => Text(skill.name),
    };

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: SkillImage(skill: skill, size: 24),
      title: titleWidget,
      trailing: Text('$level / $maxLevel'),
      selected: isSelected,
      tileColor: isActiveSkill && !isSelected ? Style.activeColorLight : null,
      onTap: () => NavigationMode.navigateTo(context, routeName),
    );
  }
}

/// The navigation list content, usable both inside a [Drawer] and as a
/// permanent sidebar.
class NavigationContent extends StatelessWidget {
  const NavigationContent({super.key, this.isDrawer = true});

  final bool isDrawer;

  @override
  Widget build(BuildContext context) {
    final gp = context.state.gp;
    final state = context.state;
    final inventoryUsed = state.inventoryUsed;
    final inventoryCapacity = state.inventoryCapacity;

    return NavigationMode(
      isDrawer: isDrawer,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, isDrawer ? 48 : 16, 16, 16),
            color: Style.drawerHeaderColor,
            child: const Text(
              'Better Idle',
              style: TextStyle(color: Style.textColorPrimary, fontSize: 24),
            ),
          ),
          _NavTile(
            routeName: 'shop',
            leading: const PageImage(
              pageId: 'shop',
              fallbackIcon: Icons.shopping_cart,
            ),
            title: const Text('Shop'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachedImage(assetPath: Currency.gp.assetPath, size: 16),
                const SizedBox(width: 2),
                Text(
                  approximateCreditString(gp),
                  style: const TextStyle(color: Style.currencyValueColor),
                ),
              ],
            ),
          ),
          _NavTile(
            routeName: 'bank',
            leading: const PageImage(
              pageId: 'bank',
              fallbackIcon: Icons.inventory_2,
            ),
            title: const Text('Bank'),
            trailing: Text('$inventoryUsed / $inventoryCapacity'),
          ),
          _SectionHeader(title: 'Combat', trailing: 'Lv. ${state.combatLevel}'),
          const SkillTile(skill: Skill.attack),
          const SkillTile(skill: Skill.strength),
          const SkillTile(skill: Skill.defence),
          const SkillTile(skill: Skill.hitpoints),
          const SkillTile(skill: Skill.ranged),
          const SkillTile(skill: Skill.magic),
          const SkillTile(skill: Skill.prayer),
          const SkillTile(skill: Skill.slayer),
          const _SectionHeader(title: 'Passive'),
          const SkillTile(skill: Skill.farming),
          const SkillTile(skill: Skill.town),
          const _SectionHeader(title: 'Skills'),
          const SkillTile(skill: Skill.woodcutting),
          const SkillTile(skill: Skill.fishing),
          const SkillTile(skill: Skill.firemaking),
          const SkillTile(skill: Skill.cooking),
          const SkillTile(skill: Skill.mining),
          const SkillTile(skill: Skill.smithing),
          const SkillTile(skill: Skill.thieving),
          const SkillTile(skill: Skill.fletching),
          const SkillTile(skill: Skill.crafting),
          const SkillTile(skill: Skill.runecrafting),
          const SkillTile(skill: Skill.herblore),
          const SkillTile(skill: Skill.agility),
          const SkillTile(skill: Skill.summoning),
          const SkillTile(skill: Skill.astrology),
          const SkillTile(skill: Skill.altMagic),
          const _SectionHeader(title: 'Other'),
          const _NavTile(
            routeName: 'statistics',
            leading: Icon(Icons.bar_chart),
            title: Text('Statistics'),
          ),
          const _NavTile(
            routeName: 'save_slots',
            leading: Icon(Icons.save),
            title: Text('Save Slots'),
          ),
          const Divider(),
          const _NavTile(
            routeName: 'debug',
            leading: Icon(Icons.bug_report),
            title: Text('Debug'),
          ),
        ],
      ),
    );
  }
}

/// A navigation drawer that provides navigation to different screens.
class AppNavigationDrawer extends StatelessWidget {
  /// Constructs an [AppNavigationDrawer]
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Drawer(child: NavigationContent());
  }
}
