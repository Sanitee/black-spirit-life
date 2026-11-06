# Worker income data provenance

`packages/bdo_map_core/assets/data/worker_economics.json` is a separate,
attributed dataset. It does not alter the accepted worker-node or exact
gathering-location data in `resource_map.json`.

## Pinned input

- package: `bdo-empire` 0.8.1
- repository: <https://github.com/Thell/bdo-empire>
- commit: `4a24b6f42926543e5f3eae5c8c559ebd689b698c`
- declared package license: `Unlicense`
- pinned upstream Workerman commit recorded by that package:
  `cb4965a5be4e68f231c4bbad7b7a87003e27038b`

The generator rejects any source file whose SHA-256 differs from the manifest
embedded in `generate_worker_economics.mjs`. The reviewed generated asset is
354,475 bytes and has SHA-256:

`5eb5905de243757a584e471c9874417db6b59f4467d5dfd7b0102dbb4780926b`

It covers all 352 resource-producing worker sites in the map and 30 worker
towns.

### Identity correction — 2026-11-02

All 88 town-worker profiles were compared by character ID to the English PC
client names through October 31. The old generator reversed Goblin (species 0)
and Human (species 1), and gave species 3–8 generic labels. The generator now
uses the worker species and names Papu, Fadus, Dwarf, Dokkebi, Dolswe and Shellfolk.
66 displayed labels changed across 30 towns; every numeric profile input, worker
type, character ID and all 352 production records remain exactly unchanged.

The 14 Inner Edania sites 2115–2128 remain explicitly unmodeled. Regeneration now
recognizes that existing exclusion rather than failing on the newer map; it does
not invent workload, yield or travel-distance records. Any other missing mapped
site still fails generation. This is an identity correction, not a claim that
the July economics snapshot is independently certified against all current
server mechanics. The current official NA/EU Workers guide supports the species
roles and one free worker slot, but does not provide full numeric yield tables:
<https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=40>.

## Transformation

The generator retains only:

- production workload;
- expected standard, giant-worker, and luck-bonus output quantities;
- worker-town distance;
- allowed worker types for each production site;
- arithmetic level-40 median work speed, movement speed, and luck; and
- the one base worker slot asserted by the pinned source.

Level-40 medians reproduce the source package's documented arithmetic and do
not include worker skill bonuses. The runtime uses the same transparent cycle
formula as the pinned source:

1. `active workload = base workload × (2 - resource availability / 100)`
2. `work minutes = 10 × ceil(active workload / work speed)`
3. `travel minutes = 2 × distance / movement speed / 60`
4. `cycle minutes = work minutes + travel minutes`

Expected output and current market price after the application's configured
tax determine the rough net-silver estimate.

## Market activity

Current listed stock is never called demand. The Arsha v2 response also
provides a cumulative `totalTrades` count. The application can calculate an
observed daily trade volume only after two successful snapshots. The elapsed
observation interval is retained and shown as confidence context.

An optional market-volume ceiling can cap expected sellable output when one
worker would produce more than the entire observed market volume. This remains
an optimistic ceiling because other sellers compete for the same sales.

## Distribution status

The package declares the Unlicense for its calculation code. Its bundled
game-data files also record an upstream Workerman snapshot whose repository has
no separate licence file. WorkermanJS is publicly shared and hosted for
community use, and the project owner has approved this fully attributed use in
the free, noncommercial Black Spirit Life fan project while accepting the
residual risk. The Unlicense is not represented as a licence for the Workerman
inputs. Corrections and substantiated removal requests from Shrddr will be
handled promptly through the public issue route.
