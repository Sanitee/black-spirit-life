# Housing data sources

`lodging_houses.json` contains the reviewed Workerman house graph for lodging planning and town diagrams.

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


No separate data licence was found. The project owner accepted credited use in this free fan project; that is not written permission from Workerman. Keep credits and respond to substantiated removal requests.

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


The generator reads the pinned Git files and checks their hashes. It validates same-town prerequisites, no cycles and matching CP, coordinates and town relationships. Only listed lodging houses add capacity.

World coordinates stay unchanged. Town IDs must match the exploration table. Muiquun's houses remain, with zero base worker capacity because it is not listed as a worker town. All house-use IDs, English names and maximum levels are retained.

## Planning rules

Entered worker capacity must already include the free base slot and active lodging. Owned houses reduce added CP and satisfy connections; their capacity is not counted twice. A blocked house can be a required connection but cannot supply new lodging. Ownership alone does not prove a house's active use.
