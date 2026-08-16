# Current worker-node snapshot provenance

## Public/runtime and private-research boundary

The 1,052 runtime node records contain Pearl Abyss-origin Black Desert
world-map facts retrieved with BDO Codex as a credited research/extraction
reference. Black Spirit Life independently selects, normalizes, connects and
presents those facts through its own map interface, rendering, search,
filtering, routing and calculations. BDO Codex is not described as the owner
of the Black Desert map, nodes or game information.

The runtime dataset contains no raw response, HTML, page design, annotations
or site-authored prose. It may be published under the project's PA fan-content
basis after the narrow schema cleanup in the controlling source matrix.

The two complete normalized research snapshots are a different boundary.
They are source-only private inputs and must not enter the clean public
repository. Keep them in the internal provenance archive; do not delete them
from that private archive.

## Pinned source

- Retrieval/reference provider: BDO Codex
- World map: `https://bdocodex.com/us/worldmap/`
- Endpoint: `POST https://bdocodex.com/ajax.php?l=us`
- Request fields: `a=get_markers&atype=worldmap&l=us`
- Locale: English (`us`)
- Retrieved: `2026-08-15T16:55:00.000Z`
- Normalized seed:
  `packages/bdo_map_core/tool/seeds/bdocodex_worldmap_2026_08_15_private_seed.json`
- Seed SHA-256:
  `752dc2af7c7350d1e8154984d12dd200559460d51c6ffde521099a6a52ef375c`

The raw response is not committed. The private import helper strips it to the
factual fields needed to build Black Spirit Life's map:

- numeric node ID;
- English node and activity names;
- temporary source icon and layer flags used only during normalization;
- pixel coordinates and contribution-point cost;
- normalized links and parent ID;
- factual output item IDs, English names, and primary-order flag;
- structured product item IDs, names, and icon paths.

Raw output HTML, knowledge records, messages, page structure and unrelated
response metadata are not retained. The production generator does not contact
BDO Codex. It loads the private pinned research seed, verifies its checksum
and invariants, and converts coordinates with:

```text
gameX = (pixelX - 68600) * 25
gameZ = (72200 - pixelY) * 25
```

## Locked record boundary

The seed validates:

| Record | Count |
|---|---:|
| All current map-node records | 1,052 |
| Raw exploration-layer records | 610 |
| Raw production-layer records | 442 |
| Production children with factual parent links | 437: 425 from the normalized world-map `plinks` plus 12 reviewed node-detail corrections |
| Production rows still lacking a factual parent | 5 |
| Exploration endpoint pairs | 667 |
| Production endpoint pairs | 426 |
| Structured output products | 285 |
| Safely classified resource-producing rows | 366 |

All 1,052 numeric node IDs are retained, including current high IDs through
2128. The older `client:*` Edania rows are not appended; their numeric current
records already exist in this snapshot. This prevents duplicate Edania
markers while retaining its managers, production nodes, links, coordinates,
and outputs.

Every node is indexed by name, including connections, cities, towns,
dangerous nodes, banks, specialties, and workshops. Resource production rows
also index every parsed output item name, allowing searches such as `Thuja
Sap` or `Wolf Hills Ash Sap` to resolve to useful named locations rather than
anonymous `Lumbering` or `Mining` rows.

## Upstream layer/link discrepancy

The BDO Codex payload contains a real discrepancy between its raw layer flags
and its production-link rows:

- raw layer flags contain 610 layer-one and 442 layer-zero rows;
- `plinks` contains 426 endpoint pairs but only 425 unique valid production
  children;
- one `plinks` row is a duplicate self-link for node 1638, which also has a
  valid parent link;
- one regular exploration link is also a duplicate self-link;
- 17 layer-zero rows do not have a unique valid `plinks` parent association.

The importer keeps every row and preserves the raw discrepancy honestly. A
separate node-detail review then resolves only relationships supported by
named BDO Codex records:

1. It resolves 425 unique valid production children from `plinks`.
2. All 442 raw layer-zero rows remain marked as production-layer records.
3. Twelve upstream orphans were matched to named parent records by reviewing
   the corresponding BDO Codex node details; no coordinate proximity was used.
4. Five records remain honestly unlinked: Korean-region production IDs
   `1826`, `1827`, `1828`, and `1829`, plus empty connection record `2056`.
   They remain visible, searchable, and render-safe.
5. The two malformed self-links are ignored after their endpoints and exact
   counts are validated.

Tests lock this discrepancy explicitly. It must not be silently “cleaned up”
or represented as a perfect upstream parent/production equivalence.

### Reviewed parent corrections

| Production child | Factual parent |
|---:|---|
| 206 | 66 — Wolf Hills |
| 207, 208 | 72 — Mask Owl's Forest |
| 209 | 63 — Elder's Bridge |
| 1677, 1678 | 1668 — Tshira Ruins |
| 1717, 1720 | 1704 — Star's End |
| 1734 | 1007 — Al-Naha Island |
| 1735 | 1008 — Racid Island |
| 1736 | 1099 — Tinberra Island |
| 1737 | 1100 — Lerao Island |

These are Black Spirit Life relationship corrections among PA-origin node
facts researched through the same credited reference family. They belong to
the application's normalized runtime dataset; the complete private research
snapshots remain outside the public repository.

## Official June 2026 cross-check

The pinned current snapshot was cross-checked against Pearl Abyss's
[June 4, 2026 production-node update](https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=13267).
Focused loader tests lock examples from the update:

- Wolf Hills: Ash Timber and Ash Sap;
- Gervish Mountains: Thuja Timber, Thuja Plank, and Thuja Sap;
- Blood Wolf Settlement: Cedar Timber and Cedar Sap;
- La O'delle: Thornwood Timber and Thornwood Sap;
- Garmoth's Nest and Pila Fe: new excavation outputs;
- current Valencia and Kamasylvia mine/lumber additions through node ID 2084.

The August 15 refresh was also cross-checked against Pearl Abyss's
[August 13, 2026 Inner Edania update](https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19693).
That official source confirms the new Inner Edania production-node names and
the Rough Marble, Magnetite Ore, and Olivine Ore resource chains. Numeric IDs,
coordinates, topology, and complete output rows remain traceable to the
separately identified private complete research snapshot retrieved through
BDO Codex.

The official page is used only as a factual cross-check. Node IDs,
coordinates, complete output rows, and links come from the separately
identified private snapshot.

## Re-import and determinism

Refreshing the seed is an explicit review operation, not part of a normal map
build:

```powershell
dart run tool/seeds/import_bdocodex_worldmap.dart `
  --source <reviewed-raw-response.json> `
  --output tool/seeds/bdocodex_worldmap_2026_08_15_private_seed.json `
  --retrieved-at <UTC-ISO-8601>
```

Any refresh must review changed counts, fields, IDs, link anomalies, output
names, legal boundary, and official update facts, then update the pinned
checksum and tests deliberately. Normal resource-map generation verifies the
seed SHA-256 and produces byte-identical JSON on repeated runs with the same
inputs.
