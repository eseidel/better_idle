# better_idle

A better idle game. Modeled after Melvor Idle, except actually designed for mobile.

Melvor Idle is nice, but has several big flaws:

1. Uses tons of power by running in background.
2. Uses HTML/CSS for display, so sometimes has issues like clicks need to be outside of buttons to actually hit the buttons.
3. Has some strange UI choices like having "quests" buried several menus deep. Doesn't allow clicking on items to quickly navigate to their place in the menus, etc.

If this ever actually works well, the Melvor folks are welcome to take it and use it.


### MVP

- Saves progress (somewhere) and reloads on open.
- Keeps track of time since start and updates automatically on load.
- Show a toast on activity completion.
- Support more than one activity subtype (e.g. maple, oak) and keep separate progress.