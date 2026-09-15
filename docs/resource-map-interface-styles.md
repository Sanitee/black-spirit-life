# Resource Map interface styles

Status: approved for the Live Beta map workspace on 2026-08-29.

The Resource Map supports two complete interface systems. The choice is
independent of the planner's Sakura, Illuminated Ledger, and Standard
appearances. It is stored in `PlannerState.extensions.resourceMap.interfaceStyle`
and survives restart and portable profile transfer. The former style switch is
not shown on the working map canvas; an existing stored choice is still
honoured without spending permanent map space on a design control.

## Shared contract

- Original game artwork is the first choice for every item, tool, house use,
  and node/activity wherever an appropriate asset exists. Generic action
  glyphs remain only where there is no matching game artwork. Activity menus,
  search results, and node details use the same bundled map marker textures.
- Housing workshop counters align with the capacity counters. Reducing a
  workshop from one to zero removes its row and makes that type available in
  the add menu again; there is no separate remove button. Larger text may wrap.
- Worker activity browsing uses one content-sized glass panel below search:
  one header/back action, original node icons and the shared submenu sizing.
  No duplicate back link, tutorial paragraphs, nested instruction card, or
  filler height/long row dividers.
- Keep the geographic canvas visually dominant.
- Keep all current behavior and the familiar in-game item, gathering-tool,
  worker-output, node, and NPC artwork.
- Put a selected resource/location summary beside the search instrument, never
  on top of the selected map marker.
- Show only the name, actionable acquisition details, required tool, materials,
  and direct navigation needed for the current task.
- Use one protected reading field per surface. Do not nest decorative cards.
- Complex tools may grow to their content limit but never become a permanent
  full-height drawer.
- Search, Gather, Workers, favorites, resources, checklists, nodes, income,
  housing, NPC/vendor details, layers, dialogs, errors, loading, and image
  lightboxes all consume the active map interface tokens.
- Motion is spatially consistent and is removed when the operating system asks
  for reduced motion.

### August 31 readability and Saved revision

- The toolbar contains Gathering, Workers and Saved, with labels beside their
  in-game icons in both designs. Buttons size to their labels and search is 52
  pixels tall, a little wider than the previous compact field. Search is always available
  directly below; duplicate Map/Search actions are removed. Active tool buttons,
  Close, Escape and Ctrl+F retain the existing navigation/reset shortcuts.
- Saved opens directly beneath search, sizes to its rows, and scrolls after its
  bounded height. It never opens a separate right-side workspace, even when
  opened from Workers. A click goes straight to that entry; Back returns to Saved.
- Every indexed search result has a star. Materials keep their existing saved
  IDs; other entries use `map:<search-kind>:<id>` in the existing
  `favoriteResourceIds` preference. This preserves profiles and distinguishes an
  animal from its products. The source header saves the animal/plant; each loot
  row can independently save that material. Stored choices ignore browse filters.
- Commands, search, Saved and details use the shared see-through glass surface,
  not a solid dark panel. Tint stays at or below 60% opacity; blur removes sharp
  basemap annotations behind the lettering and text/icon shadows preserve clear
  edges. Navigation labels remain bright when inactive. Search explicitly disables
  the planner theme's filled text-field rectangle. This supersedes the rejected
  stronger dark backing from the first August 31 revision.

### August 31 workspace proportion correction

- All focused map tools continue beneath the upper-left search, including worker
  materials, route review, income and houses. Minimized tools stay there too;
  neither design sends the next step to the opposite side of the map.
- The workspace is at most 480 pixels wide and stays within the space below
  search. The material picker also shrinks with its visible results; it does not
  reserve catalogue-sized empty space for a single match.
- Material filters are content-sized, labeled text tabs, not expanding outlined
  boxes. Materials and workspace titles follow the shared sizing standard below.
- One footer holds the selected count, editable CP budget and Build route.
  The duplicate CP display and separate oversized Update row are removed.
  Budget submission and explicit Apply remain available. Large-text and short
  layouts scroll the controls with the list rather than clipping them.
- This changes geometry, not the accepted glass treatment: the same translucent
  backing, blur, text shadows, familiar icons and navigation labels remain.

### Permanent map sizing standard — August 31

Content refinement: gathering browser rows show the original artwork and name
once, with only the useful worker-node count beside the favourite star. Repeated
product subtitles, category tags and gathering-dot totals are not displayed.
Material/source details omit generic category eyebrows and the locations-count
footer. Loot and acquisition rows use the real in-game gathering-tool artwork;
names and special requirements remain available on hover and to assistive
technology. The checklist action is labelled “Add to to-do list”. Existing map
points, source data, favourite IDs and checklist state are unchanged.

Worker-node icons/counts open the worker planner for the displayed material,
retaining existing requested amounts and other selected items. A source with
multiple products uses its displayed item's worker nodes; if that item has no
worker source, the shortcut names the first eligible material on hover. The
number always belongs to the material the shortcut opens, not the combined
node count of unrelated products.

The approved Gathering submenu is the reference, not a special larger variant.
Use `ResourceMapPanelMetrics` throughout map menus, search, saved entries,
material pickers, activity lists and selected details:

- Primary labels: 17 logical pixels; original game artwork: 36 pixels.
- Secondary gathering-tool/interaction indicators: 28 pixels, subordinate to
  the 36-pixel item artwork. Bare-handed interactions use the original game hand
  icon without implying a required inventory item.
- Secondary information: 14 pixels; detail headings: 20 pixels. This is a
  deliberate hierarchy, not permission to shrink ordinary menu labels.
- Single-line artwork rows: at least 52 pixels; multiline labels grow naturally.
- Panels measure their content, keep a compact useful width and wrap long names.
  Empty or short lists must not reserve the space of a full catalogue.
- Height is content-driven, capped by the actual map space below search.
  Dense lists use that space before scrolling; no 320-pixel detail cap.
- Every surface stays under the upper-left search in both styles. Shared glass,
  game artwork, navigation behavior and reduced-motion support are preserved.
- Check sparse and dense real content, both styles, narrow/short windows and
  200% text. Search must keep focus while its results resize.

This is a standing user preference for future map changes. The sizing hierarchy
above supersedes older per-panel font and artwork numbers in design notes.

Housing refinement: the user requested a slightly smaller house-planning panel,
not smaller Gathering menus. Housing uses 16 px primary text, 28 px original
game artwork and 44 px simple rows, with tighter workshop-level and result
spacing. Its width remains measured from the content (320–420 px before viewport
constraints), and long house addresses and enlarged text still wrap naturally.

## Glass Dock

Glass Dock is the default. Its compact tool dock sits at the upper-left, with
structured search directly beneath it in the order `scope | query | search`.
Results and selected details continue down that same edge. Reading surfaces use
blurred graphite glass, a restrained cyan focus signal, square-to-soft corners,
hairline separation, and no cards inside cards. Task workspaces continue beneath
search and remain bounded to the content-sized working area.

Motion uses a short fade and vertical settle. Selection details arrive from the
search edge, workspaces settle a few pixels down from search, and focus/hover
signals use the same 130–280 ms ease-out family.

## Ghost Ledger

Ghost Ledger is an editorial, near-frameless system. Its navigation and search
share the same upper-left flow as Glass Dock so map controls never jump between
edges. Uppercase micro-labels, a luminous cyan rule, and a feathered dark
reading field replace conventional panel frames. Selected details open beneath
the search. Task workspaces are bounded annotations at the same left edge, with their
backing fading into the map rather than ending as a hard drawer edge.

Motion follows the writing direction: command rows reveal along the accent
spine, details and task workspaces settle down from search.
It uses the same timing family as Glass Dock so switching styles does
not make the application feel slower or less predictable.

## Persistence and fallback

Stable values are `glassDock` and `ghostLedger`. Missing or unrecognized values
resolve to `glassDock`. Selecting Glass Dock removes the stored override so old
profiles retain the default without unnecessary state. The canvas deliberately
does not expose either value as a permanent navigation item.
# Compact town housing — 2026-08-31

The user approved the real-data housing preview with game house-use icons,
multiple independent workshop requests and full street/floor/room addresses.
The native panel lives under search in both map styles. One shared glass layer
wraps content; it grows with the actual controls and rows, up to available height.
Width is measured from current content and capped; long names wrap, never truncate.
Lodging/storage/stable steppers mean extra beds/slots. A selected workshop adds
one editable row and leaves one empty selector for another type. Exact usage IDs
remain separate even when two workshops share a name. Minimum levels remain
available beside each chosen workshop.

The result is a short capacity/CP line followed by only the selected houses and
their prerequisite chain. No duplicate town summary, house-count heading or
permanent max-level/owned footnote. Details expand directly under the house.
Browse-all, shop lodging and screenshot import remain available in House options.
Combined recommendations highlight their own map closure; selecting a house
does not move the camera. Calculations run outside the rendering isolate.
