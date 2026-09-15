# Map command-menu symbols

## Current treatment — 2026-09-09

The task-first Home now uses original Iron Ore, Silver and Nampo worker-house
artwork for its three main choices. The original bytes are bundled under
`assets/images/menu_artwork/`; provenance is in the adjacent licenses folder.
Saved, the checklist and other app-only commands keep recognizable functional
symbols. Material categories and item details continue using the actual items.
The map keeps 17 px labels, 36 px artwork and 52 px minimum rows, with a deeper
glass finish and restrained hover/focus feedback. Nothing is AI-generated.

The dated sections below are historical records, not the current Home design.

## Previous correction — 2026-08-31

The user rejected the generated parchment/journal illustrations: the intended
reference was the simple game UI symbols used for nodes and house uses. The
user explicitly approved Gathering's current font and icon size.

- Keep Gathering's 17 px labels, 36 px icon slots, 52 px minimum rows and 310 px
  width. Workers now shares these exact metrics; height follows content and the
  available viewport in both styles. Do not restore a smaller Worker font.
- Plan is a route-to-flag symbol, Checklist is checked lines, and Saved is a
  star. Plan has the same symbol in both menus; distinct actions are not aliases.
- Specific items uses the original Storage chest (house usage type 2). Find
  nodes retains original node type 0, enlarged within its menu slot to account
  for the texture's transparent margins. Invest adds a small plus to that node.
- Other command symbols use one restrained silver, native-drawn UI family.
  No illustrated desk objects, new button backgrounds or nested panels.
- Existing material icons, Gathering counts being hidden, transparent glass,
  navigation, map-marker sizes and housing behavior are unchanged.
- Rejected illustrated assets are no longer bundled. They and the full preceding
  source/runnable were preserved in the private rollback archive. The accepted
  baseline was verified, not replaced by this rejected version.

Verification: both styles inspected with native fonts and real material artwork;
161 map/menu/symbol tests and nine app integration checks pass, including matching
sizes and unclipped navigation at 200% text. The revised Worker screenshot was
deliberately updated for the requested icon/size change, with asset decoding
completed before capture. Analysis, production verification and Windows Release
build pass; rejected illustrated PNGs are absent from the rebuilt runnable.

The section below records the superseded generation attempt, not current UI.

Updated 2026-08-31 in response to the requested larger, cohesive icons and text,
clearer Plants & wood / Ores & minerals artwork, and removal of menu counts.

## Superseded treatment

- Gathering menu: 36 px artwork, 17 px labels, 52 px minimum rows, 310 px width.
  Height follows content, capped by available map height. Large text wraps and
  scrolls; neither interface style gains an opaque panel or a scrollbar.
- Category artwork comes from the existing game-item catalog, selected by stable
  identity instead of whichever item sorts first: Log, Iron Ore, Lamb Meat,
  Wolf Blood, Dwarf Mushroom, Blue Coral and Purified Water.
- Checklist and Saved materials use newly generated, transparent companion-app
  artwork. These are **not original Pearl Abyss assets**. Ordinary action glyphs
  and all map behavior are unchanged.

## Custom asset provenance

Mode: built-in image generation. Both outputs were inspected as RGBA images
with true transparency (alpha range 0–255), then copied unchanged into
`packages/bdo_map_core/assets/images/menu_icons/`:

- `checklist.png`: parchment checklist with brass clip.
- `saved.png`: leather journal with a star bookmark.

The originals remain in the generating task's image output directory. Flutter
decodes these at 144 × 144 for a 36 px menu slot; the transparent originals are
retained without repainting or flattening them.

## Verification of superseded treatment

- Both production menu styles inspected with native Segoe UI and the actual
  bundled item images against a basemap, not just test-font layout captures.
- 137 map/menu regression tests, four artwork tests and nine app/map integration
  checks pass. New coverage checks 36 px artwork, 17 px labels, no counts even
  with saved/checklist/planner entries, and 200% text in a short window.
- Analysis and the production-source verifier pass. The Windows Release was
  rebuilt, and both shipped PNGs match their source hashes.

## Prompts

### Checklist

Use case: stylized-concept. Asset type: finished production game-menu icon for a Black Desert companion application. A single isolated inventory-style object with genuinely transparent RGBA background, no scene, no square tile, no outer frame. Restrained painterly realism like classic Black Desert Online item artwork, natural worn material texture, subtle dimensional shading and pale upper-left highlights, dark fine edge definition, warm ivory, brown leather and aged brass. Not flat vector, not emoji, not cartoon, not shiny mobile-game candy. Strong readable silhouette at 36 pixels; use broad simple details, no tiny decoration, no writing, no lettering, no watermark. Square image, centered object occupying approximately 84% of canvas, all edges entirely inside the image. Subject: an unfurled ivory parchment quest list with modest rolled upper and lower edges, viewed almost front-on at a very slight three-quarter angle. Three dark green checkmarks in a vertical line, each with one short dark ink stroke next to it; no actual text. A small weathered brass clip holds the top. Compact broad sheet silhouette, professional PC fantasy RPG item icon.

### Saved materials

Use case: stylized-concept. Asset type: finished production game-menu icon for a Black Desert companion application. A single isolated inventory-style object with genuinely transparent RGBA background, no scene, no square tile, no outer frame. Restrained painterly realism like classic Black Desert Online item artwork, natural worn material texture, subtle dimensional shading and pale upper-left highlights, dark fine edge definition, warm ivory, brown leather and aged brass. Not flat vector, not emoji, not cartoon, not shiny mobile-game candy. Strong readable silhouette at 36 pixels; use broad simple details, no tiny decoration, no writing, no lettering, no watermark. Square image, centered object occupying approximately 84% of canvas, all edges entirely inside the image. Subject: a compact closed field journal of worn muted burgundy-brown leather, its ivory page edges visible, small aged brass corner guards and clasp, and a single brass five-pointed star attached to a short ivory bookmark ribbon protruding over the front cover. Viewed at a slight three-quarter angle. The book and star read immediately as saved/favorite materials. No other objects.
