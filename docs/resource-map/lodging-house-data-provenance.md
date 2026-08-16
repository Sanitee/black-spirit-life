# Lodging and house graph provenance

Status: **retained with attribution under the project-owner Workerman
community-use decision**.

The bundled `lodging_houses.json` is a reproducible extraction of the complete
house graph in the locally pinned `shrddr/workermanjs` repository. It supports
worker-lodging CP planning and town house diagrams.

## Pinned source

- Repository: `https://github.com/shrddr/workermanjs`
- Commit: `cb4965a5be4e68f231c4bbad7b7a87003e27038b`
- License expression: `NOASSERTION`
- Upstream files:

| File | SHA-256 |
|---|---|
| `data/houseinfo.json` | `85ab96e968266f6e3a590cca18ea7df592959adfa8f512b781f7fa9021556ff4` |
| `data/lodging_per_town.json` | `c8a24856e1a3aa3acea8b8df5a59439b1bdc58970eca1e31dc23de018ba897ad` |
| `data/loc.json` | `284338684c006d3f78d7da1c148a952ef09d519af5b39a9cf5c6eb3933487a81` |
| `data/exploration.json` | `605a498d228b43478215766dbbccc17f833d1ab2c28f6399beb619db18349f7e` |

The upstream repository contains no separate licence file for these data. The
records contain Black Desert game facts owned by Pearl Abyss. WorkermanJS is
publicly shared and hosted for community use, and the project owner has
approved this fully attributed use in the free, noncommercial Black Spirit Life
fan project while accepting the residual risk. Corrections and substantiated
removal requests from Shrddr will be handled promptly through the public issue
route.

## Generated asset

- Generator: `packages/bdo_map_core/tool/generate_lodging_houses.dart`
- Asset: `packages/bdo_map_core/assets/data/lodging_houses.json`
- Asset SHA-256:
  `096d1205bbb12fd0ed0ad0f9ae1a613c680ae0e037cdaa4af91c7f4ad4efa6f6`
- Bytes: `789050`
- Housing towns: `31`
- Worker towns: `30`
- Lodging houses: `225`
- Other houses: `587`
- Total included houses: `812`

The generator reads the four blobs directly from the pinned Git object, checks
every source hash, and refuses newer working-copy data. It then verifies that:

- every prerequisite exists;
- every prerequisite stays inside its housing town;
- the prerequisite graph is acyclic;
- house CP, coordinates, parent node, town, and prerequisite values agree
  between the two housing tables;
- only houses explicitly listed by `lodging_per_town.json` add capacity.

House coordinates are retained unchanged as game-world `x`, `y`, and `z`.
Town node IDs come from each worker region's `waypoint` and must exist in the
pinned exploration table. Muiquun's two housing records are also preserved;
because it is not a worker town in `lodging_per_town.json`, its map node is
derived from the houses' shared parent node and its base worker capacity is
zero. The English house, town, and available usage labels come from the pinned
localization table.

Every house retains all `CraftList` usage entries as a usage type ID, readable
English label, and maximum level. This lets an owned residence, storage,
stable, workshop, ranch, or other house satisfy a lodging path without
misrepresenting that house as active lodging.

## Solver interpretation

The optimizer treats the caller's existing worker capacity as authoritative.
That value must already include the town's free base slot and all active
lodging. Owned-house IDs from the complete 812-house graph reduce incremental
CP and satisfy a prerequisite, but their lodging slots are not counted again.
A blocked house may still be required as a connection in a house chain, but
cannot be selected to provide lodging capacity.

This avoids claiming that owning a house proves its current in-game use.
