# Resource Map Handoff Guide

Status: **full-feature Stable map with attributed community sources**

This guide covers the native **Resource Map** workspace in Black Spirit Life.
It uses `packages/bdo_map_core` and no WebView, embedded browser, HTML, CSS, or
JavaScript UI.

## Distribution status

The default community basemap is streamed from the public Workerman / Shrddr
endpoint. The map tiles, 64 node icons, complete lodging graph and
Workerman-derived economics inputs are retained with full attribution under
the project-owner community-use decision recorded in `release-and-packaging.md`.
No separate licence file was found; the owner accepts that residual risk and
will respond promptly to a substantiated correction or removal request.

The worker nodes, Stone Cobra/Rock Scorpion points, Rusalka points and
Stillcoral points are Pearl Abyss-origin Black Desert facts researched through
credited references and normalized into Black Spirit Life's application
schema. BDO Codex is a retrieval/reference source, not the owner of those game
facts. No site HTML, page design, guide prose, annotation or route geometry is
retained. Six source-only research inputs do not enter the public repository,
but the normalized runtime records remain.

## Open the map

Application:

```powershell
flutter pub get
flutter run -d windows
```

Select **Resource Map** in the title strip. The active destination expands to
its icon and name while the inactive destination remains a full-size icon
button. The map is created only after its first visit. Switching back to
**Craft Planner** keeps both workspaces mounted, so planner and map state
remain available during that process.

## Use the map

- The desktop map uses a narrow persistent command rail and a compact floating
  sheet instead of a full-height sidebar. Collapse the sheet to leave only the
  rail; expanding it restores the same search or detail state.
- Search for a source, item, node, place, or production activity. Item and
  product names resolve to their source when one exists: for example,
  `Thuja Sap` opens Thuja Tree and shows Thuja Timber, the appropriate tools
  and methods, and worker alternatives.
- Browse field sources in grouped sections such as animals, trees, plants, and
  mushrooms. **Favorites** stays available as a compact personal shortlist.
- In Black Spirit Life, **Needed for your current plan** follows the
  active Alchemy, Cooking, or Processing plan. It shows up to eight
  highest-priority missing materials that resolve to a map resource, with the
  planner's item icon, missing quantity, and exact-location/worker-node counts.
  Select a row to open that material directly.
- When a material has both source types, use **All**, **Gather**, or **Worker**
  to compare everything, show only manual gathering, or show only worker
  nodes. The selector is omitted when it would have no useful choice.
- Open **Layers** to toggle cities and towns, gateway hubs, all current map
  nodes, and worker output artwork independently. The complete all-node layer
  includes orientation and service nodes without treating them as
  resource-producing worker nodes.
- Worker nodes retain their activity icons. At closer zoom levels, progressive
  item artwork above a worker marker makes its outputs visible without filling
  the fully zoomed-out map with large labels.
- Click a worker node or exact gathering dot to replace the sheet contents with
  its details. Returning to the source or material restores the overview and
  all sibling markers.
- Every exact gathering record remains a small individual dot at every zoom.
  Low-zoom spatial buckets enlarge only the invisible click target and zoom
  behavior; they do not replace positions with visible numbered circles.
- Drag to pan. Use the mouse wheel or pinch gesture to zoom around the pointer
  or focal point. Double-click to zoom in.
- Use the arrow keys to pan, `+` or `-` to zoom, and `Home` or `0` to show the
  full world.
- Use the `+`, `-`, and globe controls at the right when pointer or keyboard
  input is not convenient.
- In the integrated planner, right-click a material row—or long-press it on a
  touch device—to open the applicable gathering, checklist, and worker actions.
  **Plan worker nodes** switches to the map, opens the Targets page, and adds
  the selected material with one requested production node, or preserves its
  existing count.

The interface deliberately starts with a clean map and encourages
material-first search. Search remains complete even when no overlay is
currently visible; choosing a result shows only its relevant source set.

### Plan a worker-node network

1. Open the node-network tool from the map command rail.
2. Enter the maximum CP available for the network and choose either all mapped
   towns or at least one specific starting town.
3. Find outputs by item name, grouped under wood and sap, crops and plants,
   ores and traces, fish and marine, mushrooms, animal products, or other
   materials. Set how many distinct production nodes are wanted for each.
4. Build the route. The review shows the total CP plus the nodes and complete
   connection paths to add, keep, or disconnect.
5. After applying an affordable result in game, save it as the current network
   to compare the next calculation against it.

To record an existing network, open **Copy my in-game setup** and add each
staffed production destination. The app fills the lowest-cost complete path
compatible with the selected worker towns and the draft already marked on the
map. Review and adjust the nodes manually if the inferred route differs from
the route used in game. Saving stores planner comparison context only; it does
not change anything in BDO.

To capture a larger existing setup from images, open **Your nodes** and choose
**Scan screenshots**:

1. Choose **Worker nodes**. Leave **Anywhere / sea** checked when the region is
   unknown or offshore; otherwise uncheck it and type a broad region into the
   bounded suggestion field. For houses, choose **Town houses** and type the
   exact town instead of searching a full-screen list.
2. Choose a cropped screenshot file or use **Paste screenshot** immediately
   after copying a Lightshot or Windows screenshot. Regional node images should
   keep several icons or route lines visible; house images should use a zoomed
   town view.
3. Drag and resize the outlined known records until they sit over the same
   in-game icons. Normal BDO icon colors are recognized automatically; the
   optional refinement can label one invested and one uninvested icon when a
   custom display changes those colors.
4. Review the recognized and uncertain rows. Only checked rows are saved. Use
   **Scan another part** before saving to add as many overlapping screenshots
   as needed for a sparse sea route or a dense town. Repeated sightings
   reinforce confidence, duplicates are combined, and manual checkbox choices
   stay authoritative.

Screenshot capture is additive. It never interprets an unseen record as a
removal, never replaces the saved setup, and never infers a house's active use.
Confirmed houses include their connected prerequisite chain; select lodging,
storage, stable, or workshop use afterward in the normal house details.

**Recipe materials** opens a separate, collapsible Cooking and Alchemy
selection. Individual shortages or a whole mode can be checked. The selected
rows are sent through one calculation, so a shared material or connection
trunk is paid for once. The current 28-material Alchemy portfolio now returns
a complete connected route instead of the former "request too large" failure.
Every recipe or income plan exposes its full town-to-production-node
connection lines on the map.

Every calculation solves the complete selected request again. The saved
network does not lock an old route or make it artificially cheaper; it is used
only for change reporting and as the tie-break when two plans have equal total
CP. If removing one material eliminates a shared-path saving, the remaining
materials are rerouted through the newly cheapest alternative. Calculations
run outside the map UI, and an older result is ignored if a newer request has
superseded it.

Dense plans keep their complete visible route. While panning, the native map
repaints directly instead of rebuilding the dense marker tree; equal route
styles and node rings are submitted in batches, and interactive hit targets
continue to track the live camera.

The optimizer keeps globally exact minimum-CP solving within its guarded search
bounds. Large one-node-per-material portfolios use a deterministic greedy route
with terminal-by-terminal local improvement, return a complete connected path,
and explicitly report that the global minimum is not guaranteed. Requests for
multiple nodes of one material remain fail-closed if exact enumeration is too
large. Plans over the entered CP budget remain visible for comparison but
cannot be saved as the current network.

### Compare worker income

**Worker income** uses current output prices after the configured market
deduction plus pinned production workload, expected yield, worker-town
distance, and representative level-40 worker profiles. Enter the total CP and
online hours per day; the result shows rough net silver per online hour, per
configured online day, and per week. Workers are not credited with production
while the account is offline.

The complete raw-sale network recalculates added CP after every selected node
so later nodes can reuse an earlier route. This is a deterministic
income-per-added-CP heuristic, not proof of the globally highest possible
portfolio. Individual recipe-network requests remain governed by the exact
and scalable solver rules above.

Worker capacity can be entered per town as already-hired workers currently
free for assignment plus vacant slots in lodging already owned. One selected
production node consumes one worker. The capacity matcher maximizes covered
nodes and reuses already-hired workers before vacant slots; it does not claim
that the resulting worker-town allocation maximizes income. The bundled
lodging graph can show reviewed house prerequisites, but the income model does
not guess an unrecorded ownership choice or worker assignment.

Listed stock is competition context, not demand. When enabled, the measured
sales option needs two comparable market snapshots and derives completed sales
from the cumulative trade-count change over the real observation interval.
The portfolio shares each item's measured volume across all selected nodes
rather than granting every node the entire market. Even then, the ceiling is
optimistic because other sellers compete for those sales.

These estimates omit worker skills, feeding and stamina interruptions, and
unverified lodging-house CP. Nodes whose current map outputs disagree with the
pinned yield data are excluded instead of receiving a fabricated estimate.

Planner-need rows sort zero stock first, then stock below the required
quantity, using the active mode's saved market snapshot. The badge and detail
line distinguish not marketable, unknown, zero, low, and sufficient stock,
and include the market region and last-check date when available. This is a
single saved observation, not stock history: **0 stock at last EU check** must
not be interpreted as "often out of stock."

## Tile status and cache controls

The lower status bar distinguishes:

| Status | Meaning |
|---|---|
| Ready | No request has completed yet |
| Loading map | Disk reads or network requests are active or queued |
| Online | At least one tile loaded from the network |
| Cached / offline | Downloads are disabled, or the current view was satisfied from cache |
| Offline — area not cached | Downloads are disabled and at least one visible tile is absent |
| Some tiles unavailable | A visible tile request failed and can be retried |

The cloud button changes between network-enabled and cached-only mode. Cached-
only mode reads existing disk tiles but does not fetch missing ones. Turning
downloads off cancels the app-owned HTTP client, advances the request epoch,
and discards a response that arrives late. Turning downloads on queues needed
visible tiles again.

The disk cache is provider-namespaced and capped at 64 MiB. Encoded tiles are
pruned by recent use. Decoded images use a separate 48 MiB in-memory LRU.

| Host | Disk-cache root |
|---|---|
| Black Spirit Life | `%LOCALAPPDATA%\Black Spirit Life\Map Cache` |

Open the information button to see the measured cache size and choose
**Clear downloaded tiles**. Clearing:

1. pauses downloads;
2. cancels app-owned network work and invalidates late results;
3. disposes decoded images;
4. removes downloaded tile files; and
5. leaves planner state, inventory, recipes, themes, settings, and overlay data
   untouched.

Downloads remain paused afterward. Re-enable them explicitly with the cloud
button. If Windows reports files still in use, close the app and remove only
the appropriate `Map Cache` directory above.

“Cached / offline” means best-effort viewing of tiles already requested during
normal use. It is not a complete offline world-map pack, and the cache must not
be bulk-filled, shared, or packaged.

## Current data and honest limitations

Dataset `2026.08.16-stable-v1` contains:

| Record type | Count and status |
|---|---|
| Current numeric map nodes | 1,052: 610 map records, 76 non-resource town/service records, and 366 resource-producing production records |
| Parent-linked production children | 437: 425 unique upstream links plus 12 reviewed named-node corrections |
| Unlinked production rows | 5 with `parentId: null`; no relationship is inferred from proximity |
| Safely classified resource rows | 366 |
| Resources | 356 |
| Field sources | 38 |
| Fish drying yards | 42 total; 41 with reviewed outputs and one honestly output-unknown |
| Historical exact dots | 12,582 globally deduplicated SomethingLovely MIT points, historical through 2021 |
| PA Stone Cobra/Rock Scorpion facts researched through BDO Codex | 501 positions normalized into Black Spirit Life map records |
| PA Rusalka facts researched through BDO Codex | 34 Coral Stoneback Crab positions for Rusalka's Coral (`821255`) |
| PA Stillcoral coastal facts researched through BDO Codex | 198 positions: 105 Rainbow Coral, 66 Oyster, 6 Giant Pearl Clam, and 21 Sea Fan |
| Exact gathering dots | 13,315 total |
| Radius-free focuses | 3: Tshira over exact points, Beombawi Valley as a Marni Sniper Hunting region anchor, and Maslan's Yulas Citron Orchard as a named Citron Tree destination |
| Broad gathering areas | 0 |
| Gathering routes | 0 |

The current node layer contains 1,052 Pearl Abyss-origin world-map records
retrieved with BDO Codex as a credited research reference and normalized into
Black Spirit Life's schema. Its numeric IDs include Inner Edania through node 2128;
the former `client:*` Edania records are not appended. The Stable dataset presents those
records as 610 map entries, 76 non-resource town/service entries, and 366
resource-producing production entries. Upstream supplies 426 production-link
rows, but one is a duplicate self-link, so 425 unique valid production
children originate in that layer. A separate named-node review resolved 12 of
the 17 upstream orphans. The five still-unresolved rows are visible and
searchable, but the generator does not guess a connection. See
`release-and-packaging.md` for the reviewed public runtime boundary.

The previous Tshira orientation circle was centered from a node coordinate,
not verified spawn geometry, so it was removed. No BDOLytics data or
third-party route geometry is included. The replacement focus selects a
compact set of exact Stone Cobra and Rock Scorpion dots around Tshira Ruins
without drawing a radius, coverage circle, or traced video path.

The second focus adds Marni Sniper Hunting at the Wild Game Preserve in
Beombawi Valley, northwest of Dalbeol Village. Pearl Abyss's
[official sniper-hunting guide](https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=74)
verifies the activity and its boar, bear, and hawk population, plus the rare
tigers that may appear. The marker uses the existing reviewed Beombawi Valley
node coordinate as a navigation anchor; it is not an asserted spawn. Animals
roam through the preserve, so no exact spawn dots, broad circle, or radius were
fabricated. Pork, Pig Blood, Pig Hide, Bear Meat, Bear Blood, Bear Hide,
Crystal of Decimation, Crystal of Bitterness, Crystal of Darkness, Forest
Crystal, and Live Meat resolve to the source. Pearl Abyss's
[Land of the Morning Light update](https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=5387)
documents those rare crystal rewards. A sniper rifle is used for the hunt and a
Butcher Knife collects the materials after a kill; the crystal rewards are
explicitly presented as rare rather than guaranteed.

Marni Sniper Hunting remains one factual field source in the dataset, but the
Gather interface presents it through the relevant **Meat** and **Blood & hides**
material categories rather than adding a separate hunting destination.

The 12,582 SomethingLovely dots are transformed from immutable,
MIT-licensed commit `289c833d34851dc84f3a647a2d9cf604eda9c93a` and remain
explicitly labeled historical through 2021 and `stale`. They comprise the
prior 6,952 positions plus 2,776 exact common-animal and Everlasting Herb
positions and 2,854 genuine tree coordinates. Coverage includes:

- Snake (391 globally unique locations; Snake Meat at all 391, with 133 also
  serving Snake Skin and Cobra Blood);
- Scorpion (240), Sheep (1,068), Wolf (397), Deer (549), Fox (468), Pig (719),
  Cow/Ox (531), Bear (62), Wasteland Cheetah Dragon (61), Fan Flamingo (103),
  Lizard (1,109), Raccoon (176), Weasel (1,042), and Stone Rhino (103), with
  supported meat/blood/hide resources sharing each animal family's
  coordinates; and
- Truffle Mushroom (96), Everlasting Herb (112), Insectivore Plant (142),
  Thuja (591), Delotia (752), Violet Flower (966), and Volcanic Umbrella
  Mushroom (50); and
- Ash (299), Birch (300), Cedar (300), Fir (300), Maple (300), Pine (300),
  Acacia (300), Elder (300), White Cedar (300), and Thornwood (155) tree
  positions.

The large new tree inputs are reduced with a deterministic 20-by-15 spatial
selection, capped at 300 genuine source coordinates per family; the cap never
creates or interpolates a location. Log is attached to all 11 existing tree
sources and reuses their 3,445 coordinates; it does not add a separate point
payload. Shared animal products reuse one coordinate instead of drawing
stacked dots. None of the historical points is claimed as complete current
spawn coverage.

Source cards intentionally omit the **Historical exact locations** heading and
the historical-dot explanatory paragraph. Exact dots remain interactive, while
their verification and provenance remain preserved in the records and audit
documentation.

The two source research inputs produced 501 retained PA in-game points after
global duplicate suppression: 266 Stone Cobra and 235 Rock Scorpion. The
radius-free Tshira focus groups the exact points relevant to the current
combined Snake/Scorpion rotation, but it does not assert that all 501 points
form one route. Current-client spawn persistence remains open to corrections.

Rusalka's Coral is item `821255`, gathered by defeating a Coral Stoneback Crab
and mining it with a pickaxe; it is not the separate item named Rusalka
Crystal. The Stable dataset retains 34 individual Coral Stoneback Crab positions
transformed from a BDO Codex NPC page review instead of restoring the broad
circle. They are labeled `communityReported`, have not been independently
verified in game, and retain the credited research link. They are PA location
facts in Black Spirit Life's own record format.

The Stillcoral coastal source separately retains 198 PA in-game object
positions researched through BDO Codex: 105 [Rainbow Coral](https://bdocodex.com/us/gatherable/10924/),
66 [Oyster](https://bdocodex.com/us/gatherable/10967/), six
[Giant Pearl Clam](https://bdocodex.com/us/gatherable/10913/), and 21
[Sea Fan](https://bdocodex.com/us/gatherable/10951/). These points are not an
asserted route or independently verified current-client survey. No path order,
broad circle, or interpolated location is added.

The former v7 layer appended 12 manager and 16 production records from a
minimal NA-client Edania factual extract. The Stable dataset does not append those
client-prefixed rows because their numeric current records are already present
in the complete node snapshot. The separately pinned Edania input remains an
internal resource-metadata cross-check and is not part of the public tree.

Add current animal dots or a route only after documented source review or
independent in-game verification; never copy another site's route or
annotation.

## Troubleshooting

**The map background is dark or incomplete**

Check the status. If it says **Offline — area not cached**, enable downloads.
If it says **Some tiles unavailable**, use retry. The overlay remains useful
even when the third-party basemap is unavailable.

**Clearing the cache did not remove every byte**

Close both map hosts and delete only the matching cache directory listed
above. Never delete the planner profile to clear map tiles.

**The dataset fails to load**

Run the package tests and confirm
`packages/bdo_map_core/assets/data/resource_map.json` is present. Regenerate it
only through the reviewed internal data pipeline; do not repair the generated
JSON manually.

**A current node or animal location is missing**

The node layer is a pinned 2026-08-15 snapshot, not a live service. Confirm
whether the record changed after that review date and record it as a data
review item. Animal points remain intentionally selective. Do not fill either
kind of gap by copying another map.

## Related documents

- `release-and-packaging.md`
- `lodging-house-data-provenance.md`
- `worker-income-data-provenance.md`
