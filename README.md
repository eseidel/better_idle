# better_idle

An idle game, modeled after Melvor Idle 1, but designed for mobile.

If you like it, go buy Melvor Idle, they did all the hard work of designing
the actual game and images, etc.
https://melvoridle.com/

## Why?

Melvor Idle is nice, but is desktop/web-first and has numerous issues on mobile
which detract from using it:

1. Uses excessive power by running in background.
2. Uses HTML/CSS for display, so:
  - sometimes clicks need to be outside of/below buttons to actually hit
  - sometimes width of the content is wider than the screen and thus starts
    horizontal scrolling
  - if the "navigation drawer" is open sometimes scroll events still go through
    to the background
  - sometimes "tooltips" get stuck on
3. Has some non-mobile-friendly UI choices like having "quests" buried several
   menus deep. Doesn't allow clicking on items to quickly navigate to their
   place in the menus, etc.
4. Defaults to online-first (need to click at least 3 times to get to the game
   if playing offline), both in the cloud-sync and local-only paths.

Re-writing the entire game in a new language, probably isn't the correct
approach, but building this has been fun for me (and an excuse to play with
Claude). If this ever actually works well, the Melvor folks are welcome to take
it and use it as their own.

I currently am only targeting the base "full" game with no current plans to
implement expansions.  Mods have no (easy) path to working since this implementation
is written in a different language than the mods.

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