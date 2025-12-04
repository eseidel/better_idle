# better_idle

A better idle game. Modeled after Melvor Idle, except actually designed for
mobile.

Melvor Idle is nice, but has a bunch of UI flaws which detract from using it:

1. Uses tons of power by running in background.
2. Uses HTML/CSS for display, so sometimes has issues like clicks need to be
   outside of buttons to actually hit the buttons.
3. Has some strange UI choices like having "quests" buried several menus deep.
   Doesn't allow clicking on items to quickly navigate to their place in the
   menus, etc.

If this ever actually works well, the Melvor folks are welcome to take it and
use it.

### TODO

- Actions missing inputs should not be clickable.
- Actions should automatically stop when they run out of inputs.
- Clicking an action that is already running should stop it, not restart it.
- Track per-item mastery and levels.
- Add a shop.
- Enforce fixed size inventory, stop actions that exceed such.
- Add a store to purchase inventory slots.
- Allow buying of skill upgrades (e.g. faster axe)
- Welcome back should show levels gained.
- Welcome back should show items lost to full inventory.