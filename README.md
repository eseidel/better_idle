# better_idle

A better idle game. Modeled after Melvor Idle, except actually designed for
mobile.

Melvor Idle is nice, but has a bunch of UI flaws which detract from using it:

1. Uses tons of power by running in background.
2. Uses HTML/CSS for display, so sometimes has issues like clicks need to be
   outside of buttons to actually hit the buttons, or the width of the content
   is wider than the screen and thus has horizontal scrolling.
3. Has some strange UI choices like having "quests" buried several menus deep.
   Doesn't allow clicking on items to quickly navigate to their place in the
   menus, etc.
4. Defaults to online-first (need to click at least 3 times to get to the
   game if playing offline).

If this ever actually works well, the Melvor folks are welcome to take it and
use it.

### TODO

- Handle global and per-action modifiers (e.g. mastery levels).
- Support Mastery skill modifiers (e.g. increasing double items chance)
- Fix Firemaking to put log selection behind a pop-up.
- Fix Smithing to separate action groups. 
- Add Equipment
- Add Farming
- Fix combat to show attack timers/progress bars.
- Fix fishing regions to drop junk/specials.
- Add Thieving drops.
- Implement mastery rewards (and UI) for all actions.
- Implement mastery pool checkpoints.
- Implement mastery tokens.