# Open map-action emblems — 2026-10-30

The user selected Open emblems and explicitly approved applying it to the
shown material menus. Implemented in the isolated Open Emblems 20261030 source,
branch `codex/open-emblems`, on the complete content-sized item-window candidate
(v0.1.15 base plus all six staged item-window files, not HEAD alone).

## Scope

Planner's material map actions and the same Recipe Book material menu share one
presentation: bare emblems in 42px slots, 34px game artwork, 28px scroll, open
60px-minimum rows and thin separators. Text is 14/700 with 11px details; width
starts at 310px, grows with text and clamps to the viewport. Native menu hover,
focus, scrolling, keyboard, secondary-click and long-press behavior remain.
No extra icon mounts, inset row boxes, tooltips, idle animation or new settings.

Only presentation is shared. Each caller retains its original availability,
source-name handling, demand forwarding and callbacks. NPC/gathering/checklist/
network actions appear only when the existing resolver permits them. Recipe
Book and Planner retain their existing differences in optional-source labels.
Opportunities and standalone Resource Map menus are outside this visual pass.
No calculations, catalog, identifiers, storage, native ports or updater changes.

## Artwork

- Gathering: existing original interaction atlas, verified bare-hands frame
  `(211,71,34,34)`. The pixels are selected at runtime without altering the atlas.
- NPC: original person frame `(141,1,34,34)` from that same atlas, approved as a
  familiar vendor symbol. Not claimed to be the current game's Find NPC button.
- Network: existing credited node type 0, with the existing 1.7x transparent-
  margin normalization. No new asset or external runtime request.
- Checklist: Lucide scroll-text adapted to Flutter Canvas, **not game artwork**.
  The ISC notice ships in `assets/app/lucide-LICENSE.txt`.

Existing Pearl Abyss interaction and Workerman node notices continue to apply.
Original image files remain byte-identical. Text supplies accessibility labels;
decorative images are excluded to avoid duplicate or misleading tool labels.

## Verification and boundaries

Actual Flutter captures use the full app, real bundled catalog/source lookup,
native fonts and disposable synthetic profiles: Milk Tea/Cooking Honey and
Beer/Sugar, all three themes at 1200x752, 960x600 and 200% text. Images decode,
labels wrap, escape closes, hover adds no explanatory popup, and merely opening
these menus leaves the synthetic plan state unchanged.

Additional 320x480 tests exercise all four actions, original callback identity,
accessibility, scrolling to each action and long-press/Escape in all themes at
100% and 200%. Existing Planner lookup, Recipe Book modal, map resolver, item
popup scroll and content-sized window tests are included in the regression run.

An unrelated existing Recipe Book map-state-retention test fails before opening
the changed menu, while searching for Insectivore Plant Powder (line 56). The
same failure was reproduced in the unchanged preceding source. It is recorded,
not hidden or repaired by this visual change.

Workspace evidence: `audit/open-emblems-20261030`; actual captures:
`work/visuals/open-emblems-actual`. Consult the final result for test/build counts
and hashes. The separate runnable is `build/windows/x64/runner/Release/BlackSpiritLife.exe`
under this source; it includes the prior content-sized item-window adjustment.

The preceding complete source and runnable were freshly hash-verified before
and after and remain unchanged. No installed app or personal profile was opened
or changed, no desktop app was launched, and nothing was handed off or published.
This implementation still awaits user review and a separate release request.
