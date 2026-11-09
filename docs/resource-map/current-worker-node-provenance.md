# Worker-node sources

Snapshot reviewed August 15, 2026. These counts describe that review, not a live feed.

The app stores selected Pearl Abyss node facts in its own format. BDO Codex is credited as the research source. Raw responses, website content and the two complete research snapshots stay outside the public repository.

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


The importer keeps IDs, names, coordinates, CP, links and output identities. It discards HTML and unrelated response data. Normal builds read the reviewed seed offline and verify its checksum.

Coordinates convert as follows:

```text
gameX = (pixelX - 68600) * 25
gameZ = (72200 - pixelY) * 25
```

## Reviewed counts

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


Numeric IDs include Edania through 2128; old `client:*` duplicates are not added. Search includes node names and output items.

## Links

The source has 426 production pairs but only 425 unique valid children. One production self-link for 1638 and one exploration self-link are duplicates. Of 17 originally unlinked rows, 12 were resolved from named node records, not nearby coordinates:

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


IDs 1826–1829 and empty connection 2056 stay unlinked, visible and searchable. Tests preserve this distinction rather than assuming every layer flag proves a parent link.

## Official checks

The [June 4 production update](https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=13267) was used to check changed outputs. The [August 13 Inner Edania update](https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19693) checked new names and resource chains. IDs, coordinates and full links come from the separately pinned research snapshot.

## Refresh

Run the internal importer only after reviewing new source data:

```powershell
dart run tool/seeds/import_bdocodex_worldmap.dart `
  --source <reviewed-raw-response.json> `
  --output tool/seeds/bdocodex_worldmap_2026_08_15_private_seed.json `
  --retrieved-at <UTC-ISO-8601>
```
Review changed IDs, counts, links, outputs, official updates and source rights before updating the hash or tests. The same reviewed inputs must generate identical output.
