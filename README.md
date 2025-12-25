# better_idle

A better idle game. Modeled after Melvor Idle, except actually designed for
mobile.

Melvor Idle is nice, but has a bunch of UI flaws which detract from using it:

1. Uses tons of power by running in background.
2. Uses HTML/CSS for display, so:
  - sometimes clicks need to be outside of buttons to actually hit the buttons
  - width of the content is wider than the screen and thus has horizontal
    scrolling
  - if the "navigation drawer" is open sometimes scroll events still go through
    to the background
  - sometimes "tooltips" get stuck
3. Has some non-mobile-friendly UI choices like having "quests" buried several
   menus deep. Doesn't allow clicking on items to quickly navigate to their
   place in the menus, etc.
4. Defaults to online-first (need to click at least 3 times to get to the game
   if playing offline), both in the cloud-sync and local-only paths.

If this ever actually works well, the Melvor folks are welcome to take it and
use it.

### TODO

- Handle global and per-action modifiers (e.g. mastery levels).
- Complete support for mastery benefits.
- Fix Firemaking to put log selection behind a pop-up.
- Add Farming
- Add Township
- Fix fishing regions to drop junk/specials.
- Add more Thieving drops.
- Add global drops.
- Implement mastery rewards (and UI) for all actions.
- Implement mastery pool checkpoints.
- Implement mastery tokens.
- Gems should not drop for rune essence.
- Handle recipes which have multiple possible inputs.