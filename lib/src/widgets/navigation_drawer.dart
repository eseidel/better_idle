import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/xp.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/router.dart';
import 'package:better_idle/src/widgets/skills.dart';
import 'package:better_idle/src/widgets/strings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SkillTile extends StatelessWidget {
  const SkillTile({required this.skill, super.key, this.selected = false});

  final Skill skill;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;
    final routeName = skill.routeName;
    final activeSkill = context.state.activeSkill;
    final isActiveSkill = activeSkill == skill;
    final isSelected = selected || currentLocation == '/$routeName';
    final skillState = context.state.skillState(skill);
    final level = levelForXp(skillState.xp);

    return ListTile(
      leading: Icon(skill.icon, color: isActiveSkill ? Colors.orange : null),
      title: Text(skill.name),
      trailing: Text('$level / $maxLevel'),
      selected: isSelected,
      tileColor: isActiveSkill && !isSelected
          ? Colors.orange.withValues(alpha: 0.1)
          : null,
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
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Better Idle',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart),
            title: const Text('Shop'),
            trailing: Text(approximateCreditString(gp)),
            selected: currentLocation == '/shop',
            onTap: () {
              Navigator.pop(context);
              router.goNamed('shop');
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Bank'),
            trailing: Text('$inventoryUsed / $inventoryCapacity'),
            selected: currentLocation == '/bank',
            onTap: () {
              Navigator.pop(context);
              router.goNamed('bank');
            },
          ),
          const Divider(),
          const SkillTile(skill: Skill.woodcutting),
          const SkillTile(skill: Skill.firemaking),
          const SkillTile(skill: Skill.fishing),
          const SkillTile(skill: Skill.mining),
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
