# Resource Map

Find gathering spots, vendors, worker nodes and houses. Search by an item, source or place name. Select a result to see its available sources.

## Controls

Drag to pan; use the wheel, pinch or double-click to zoom. Arrow keys pan, `+`/`-` zoom, and `Home`/`0` show the world. Tools stay below search and keep their state when you switch tabs.

**Gather** and **Worker** filters appear when both apply. **Saved** keeps favourites. **Layers** controls towns, nodes, connections and worker-output artwork. Exact gathering points remain separate dots at every zoom.

In Planner, right-click or long-press a material for its map actions. **Plan worker nodes** adds that material to the map's targets without lowering an existing requested count.

## Worker routes

Choose starting towns, a CP budget and the number of production nodes wanted for each material. Build the route, review the complete connections and apply it in game. Saving records the setup for comparison; it does not control BDO.

Recipe material requests are solved together so shared connections cost CP once. Changing targets recalculates the whole route. The saved network is used for change reporting and equal-cost ties, not as free connections.

Small requests use an exact minimum-CP search. Large requests for one node per material may use an approximate connected route, labelled accordingly. Oversized requests for several nodes of one material stop rather than invent an exact result. Over-budget plans can be viewed but not saved as the current network.

## Record an existing setup

**Copy my in-game setup** fills a compatible path to each selected production node. Adjust it if your actual route differs.

**Your nodes → Scan screenshots** accepts files or pasted images. Choose a region or **Anywhere / sea**; for houses, choose the town. Align the known markers, review the results and save checked rows. More screenshots can be added before saving.

Imports add confirmed records; they never remove unseen ones. House imports include required connections but do not guess each house's use. Choose lodging, storage or workshop use afterward.

## Worker income

Estimates use recorded workload, yields, travel, representative level-40 workers, current prices after tax and your online hours. Offline production is not counted. Enter available workers and vacant lodging slots by town.

Income routes use a shared-connection estimate, not proof of the most profitable possible network. The model omits worker skills, feeding/stamina breaks and unverified lodging costs. Nodes with conflicting output data are excluded.

Stock is not demand. The optional sales limit needs two comparable trade-count readings and shares the observed volume across the portfolio. It remains optimistic because other sellers compete for those sales. A saved stock reading describes that check, not how often an item sells out.

## Map downloads

The cloud button switches between downloads and cached-only viewing. Offline viewing covers only previously loaded tiles, not the whole world.

| Status | Meaning |
|---|---|
| Ready | No request has finished yet |
| Loading map | Tiles are loading |
| Online | A tile loaded from the network |
| Cached / offline | Using saved tiles |
| Offline — area not cached | A needed tile is missing |
| Some tiles unavailable | A request failed; retry is available |

The information button shows cache size and **Clear downloaded tiles**. Clearing pauses downloads and removes map tiles only. Turn downloads on again with the cloud button. If files remain in use, close the app before clearing only `%LOCALAPPDATA%\Black Spirit Life\Map Cache`.

The cache is limited to 64 MiB on disk and 48 MiB decoded in memory. Do not bulk-download, share or package cached tiles.

## Data and limits

The map combines dated sources; it is not a live survey of every game location. Historical SomethingLovely points are labelled through 2021. Community-reported points are distinct from independently verified ones. Named-area markers are navigation aids, not exact spawn locations or routes.

Milk uses Dairy Cow sources; other cow/ox resources are separate. Coral Stoneback Crabs and coastal gatherable objects are separate too. Missing node links or spawn coordinates are never filled by guessing from nearby markers.

See the [package snapshot notes](../../packages/bdo_map_core/README.md#bundled-data), [node sources](current-worker-node-provenance.md), [Truffle sources](truffle-location-photo-provenance.md), [housing data](lodging-house-data-provenance.md) and [income data](worker-income-data-provenance.md).

## Development and credits

Run `flutter pub get`, then `flutter run -d windows` from the app root. The map is native Flutter, using `packages/bdo_map_core`.

If data will not load, check `packages/bdo_map_core/assets/data/resource_map.json` and run the package tests. Use the reviewed generator for changes; do not patch generated JSON by hand.

Workerman/Shrddr provides the credited basemap and some inputs. No separate written licence was found; the project owner's use decision is not permission from that project. See [source and packaging rules](release-and-packaging.md) and [third-party notices](../../THIRD_PARTY_NOTICES.md). Report missing or changed records through the repository's Issues tab.
