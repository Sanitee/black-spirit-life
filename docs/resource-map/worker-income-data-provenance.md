# Worker income data

The separate `worker_economics.json` stores inputs for rough income estimates. It does not replace map locations or node relationships.

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


## November 2, 2026 name correction

An exact-ID review corrected reversed Goblin/Human labels and added the proper Papu, Fadus, Dwarf, Dokkebi, Dolswe and Shellfolk names. It changed 66 labels across 30 towns, not numeric inputs or production records.

The 14 Inner Edania sites 2115–2128 remain unmodelled. Other missing mapped sites stop generation. The [official Workers guide](https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=40) supports species roles and the free worker slot, but does not verify the full yield table.

## Calculation

Inputs cover workload, standard/giant/luck yields, allowed worker types, town distance and level-40 median speed/luck. They exclude worker skill bonuses.

1. `active workload = base workload × (2 - resource availability / 100)`
2. `work minutes = 10 × ceil(active workload / work speed)`
3. `travel minutes = 2 × distance / movement speed / 60`
4. `cycle minutes = work minutes + travel minutes`

Output and current prices after tax give estimated silver. Listed stock is not demand. A sales-rate estimate needs two successful cumulative-trade readings and their elapsed time. Any market-volume ceiling is optimistic because other sellers share those sales.

## Licence

The calculation code uses the Unlicense. That does not license its Workerman data inputs. No separate Workerman data licence was found; the project owner accepted credited use and the remaining risk. Keep attribution and the public correction/removal route.
