import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/page_image.dart';
import 'package:better_idle/src/widgets/router.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skills.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logic/logic.dart';

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
    final level = levelForXp(skillState.xp);

    return ListTile(
      leading: SkillImage(skill: skill, size: 24),
      title: Text(skill.name),
      trailing: Text('$level / $maxLevel'),
      selected: isSelected,
      tileColor: isActiveSkill && !isSelected ? Style.activeColorLight : null,
      onTap: () {
        Navigator.pop(context);
        router.goNamed(routeName);
      },
    );
  }
}

/// A navigation drawer that provides navigation to different screens.
class AppNavigationDrawer extends StatelessWidget {
  /// Constructs an [AppNavigationDrawer]
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;
    final gp = context.state.gp;
    final state = context.state;
    final inventoryUsed = state.inventoryUsed;
    final inventoryCapacity = state.inventoryCapacity;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            color: Style.drawerHeaderColor,
            child: const Text(
              'Better Idle',
              style: TextStyle(color: Style.textColorPrimary, fontSize: 24),
            ),
          ),
          ListTile(
            leading: const PageImage(
              pageId: 'shop',
              fallbackIcon: Icons.shopping_cart,
            ),
            title: const Text('Shop'),
            trailing: Text(approximateCreditString(gp)),
            selected: currentLocation == '/shop',
            onTap: () {
              Navigator.pop(context);
              router.goNamed('shop');
            },
          ),
          ListTile(
            leading: const PageImage(
              pageId: 'bank',
              fallbackIcon: Icons.inventory_2,
            ),
            title: const Text('Bank'),
            trailing: Text('$inventoryUsed / $inventoryCapacity'),
            selected: currentLocation == '/bank',
            onTap: () {
              Navigator.pop(context);
              router.goNamed('bank');
            },
          ),
          const Divider(),
          const SkillTile(skill: Skill.hitpoints),
          const SkillTile(skill: Skill.attack),
          const Divider(),
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
          const Divider(),
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
