# Material map actions

Planner and Recipe Book material menus share open rows with game artwork, short labels and thin separators. Menus grow with their content and stay within the screen.

- Artwork: 34 px in a 42 px slot; checklist: 28 px.
- Rows: at least 60 px. Labels: 14 px bold; details: 11 px.
- Width starts at 310 px and grows as needed.
- Keep keyboard, focus, scrolling, right-click and long-press behaviour. Add no explanatory hover popups.

Each host still decides which gathering, vendor, checklist or worker action applies. This design does not change calculations or source resolution.

## Artwork credits

Gathering uses the existing hand frame `(211,71,34,34)`; NPC uses person frame `(141,1,34,34)`. These are Pearl Abyss game textures. The person is a vendor symbol here, not a claim about BDO's current Find NPC button.

Network uses credited Workerman node type 0, scaled 1.7× to account for transparent margins. Checklist uses Lucide scroll-text, adapted to Flutter Canvas; see `assets/app/lucide-LICENSE.txt`. Original image files are unchanged.
