# Worker excavation unlock and manager provenance

## Purpose and safety boundary

This file documents the small factual manager guide used by the compact
production-node popup. It is intentionally separate from the worker-node
snapshot because:

- an exploration-node marker is not necessarily the manager's actual
  position;
- excavation unlock requirements and Energy costs are not universal;
- a manager name can be reliable even when their exact current spawn
  coordinate is not.

No third-party artwork, UI, map tile, or copied descriptive text is included.
The implementation retains only factual NPC IDs, names, parent-node
relationships, and a limited set of exact game-world X/Z coordinates for this
free, noncommercial fan application.

These are Pearl Abyss-origin NPC and node facts selected for Black Spirit
Life's application-specific guidance. Community sources are credited as
research references; no copied guide prose or site presentation is retained.

## User-facing rule

The popup uses conditional guidance:

> If this excavation is hidden, connect and invest in its parent node first.
> Then speak to the named manager and check Chat. The Energy cost can vary by
> node.

It does **not** claim that every excavation is currently hidden, or that every
unlock costs 35 Energy.

Pearl Abyss's official
[Node Adventurer's Guide](https://blackdesert.pearlabyss.com/ASIA/en-us/Game/Wiki?_masterWikiNo=18)
confirms that the point shown for a node is not necessarily the node manager's
location, and that node investment is performed through node management. The
community-maintained
[Black Desert Foundry node guide](https://www.blackdesertfoundry.com/nodes-guide/)
documents the common excavation-specific flow: speak to the parent node
manager and spend an amount of Energy to unlock the production node. The
[Glish Ruins excavation record](https://bdocodex.com/seaen/node/480/)
provides a concrete, player-verified example involving Karu after investing in
the parent.

These sources justify the conditional workflow, not a universal numeric
Energy cost.

## Manager and marker records

The bundled worker-node graph currently has 40 excavation production records
under 36 unique parent nodes. Every parent has a reviewed manager identity.
Only 18 managers have an exact current X/Z spawn coordinate in the referenced
[Caphras Archives](https://caphrasarchives.com/llms.txt) NPC record. Those 18
receive a **Mark on map** action; the other 18 deliberately do not.

| Parent ID | Parent node | Manager record | Exact X/Z marker |
|---:|---|---|---:|
| 24 | Ancient Stone Chamber | [Stone Chamber Excavation Lead (50009)](https://caphrasarchives.com/npc/50009.md) | -46008.6, 3455.0 |
| 345 | Glish Ruins | [Karu (41086)](https://caphrasarchives.com/npc/41086.md) | 37478.7, -107868.0 |
| 347 | Lynch Farm Ruins | [Zara Lynch (41093)](https://caphrasarchives.com/npc/41093.md) | -17993.4, -38133.4 |
| 638 | Bernianto Farm | [Griffian Bernianto (43449)](https://caphrasarchives.com/npc/43449.md) | -229908.0, 11573.8 |
| 710 | Rhua Tree Stub | [Kamasylve Priestess Lunia (50454)](https://caphrasarchives.com/npc/50454.md) | -251690.0, -208681.0 |
| 715 | Mansha Forest | [Mansha (50459)](https://caphrasarchives.com/npc/50459.md) | -376017.0, -123338.0 |
| 1156 | Ancient Ruins Excavation Site | [Jamo Hasa (50546)](https://caphrasarchives.com/npc/50546.md) | 168070.0, 2585.2 |
| 1324 | Pila Fe | [Hazer (50600)](https://caphrasarchives.com/npc/50600.md) | 462208.0, 78112.0 |
| 1332 | Pilgrim's Sanctum: Obedience | [Siriya Min (50620)](https://caphrasarchives.com/npc/50620.md) | 815342.0, 278063.0 |
| 1333 | Pilgrim's Sanctum: Abstinence | [Semica (50618)](https://caphrasarchives.com/npc/50618.md) | 743483.0, 144494.0 |
| 1334 | Pilgrim's Sanctum: Sharing | [Samaya (50619)](https://caphrasarchives.com/npc/50619.md) | 892139.0, 60953.5 |
| 1335 | Pilgrim's Sanctum: Sincerity | [Saimar (50617)](https://caphrasarchives.com/npc/50617.md) | 822785.0, -10472.3 |
| 1336 | Pilgrim's Sanctum: Humility | [Tarik (50621)](https://caphrasarchives.com/npc/50621.md) | 893017.0, -61507.7 |
| 1390 | Roud Sulfur Works | [Salta (50665)](https://caphrasarchives.com/npc/50665.md) | 1083310.0, 405019.0 |
| 1613 | Mirumok Ruins | [Voraro (50707)](https://caphrasarchives.com/npc/50707.md) | -424965.0, -322887.0 |
| 1619 | Tooth Fairy Forest | [Hunnie (50713)](https://caphrasarchives.com/npc/50713.md) | -551359.0, -319416.0 |
| 1628 | Looney Cabin | [Looney (45580)](https://caphrasarchives.com/npc/45580.md) | -576555.0, -438540.0 |
| 1629 | Weenie Cabin | [Weenie (45579)](https://caphrasarchives.com/npc/45579.md) | -584288.0, -375340.0 |
| 1655 | Sherekhan Necropolis | [Camira (50727)](https://caphrasarchives.com/npc/50727.md) | Not verified |
| 1656 | Garmoth's Nest | [Ominous Altar (50729)](https://caphrasarchives.com/npc/50729.md) | Not verified |
| 1663 | Fountain of Origin | [Jyarro (50747)](https://caphrasarchives.com/npc/50747.md) | Not verified |
| 1694 | Crypt of Resting Thoughts | [Thornwood Goddess Statue (50763)](https://caphrasarchives.com/npc/50763.md) | Not verified |
| 1704 | Star's End | [Runaway Monster (50777)](https://caphrasarchives.com/npc/50777.md) | Not verified |
| 1743 | Mountain of Division | [Tunn Verdun (50778)](https://caphrasarchives.com/npc/50778.md) | Not verified |
| 1759 | Sherekhan Iron Mine | [Alvaro (50791)](https://caphrasarchives.com/npc/50791.md) | Not verified |
| 1762 | Zvier Highlands | [Ganzorig (50797)](https://caphrasarchives.com/npc/50797.md) | Not verified |
| 1763 | Camp Balacs | [Reina Balacs (50795)](https://caphrasarchives.com/npc/50795.md) | Not verified |
| 1788 | Dokkebi Forest | [Tombkebi (47311)](https://caphrasarchives.com/npc/47311.md) | Not verified |
| 1789 | Golden Pig Cave | [Doaji (47318)](https://caphrasarchives.com/npc/47318.md) | Not verified |
| 1797 | Beombawi Valley | [Tiger Victim's Grave (47364)](https://caphrasarchives.com/npc/47364.md) | Not verified |
| 1799 | Haemo Island | [Hwisa's Grave (47365)](https://caphrasarchives.com/npc/47365.md) | Not verified |
| 1838 | Tungrad Ruins | [Ezrin (47442)](https://caphrasarchives.com/npc/47442.md) | Not verified |
| 1860 | Myeonggyun Hall | [Hosu (47625)](https://caphrasarchives.com/npc/47625.md) | Not verified |
| 1870 | Mount Ahshi | [Bonghwang Statue (47636)](https://caphrasarchives.com/npc/47636.md) | Not verified |
| 2016 | Urnas Mountains | [Dener (47685)](https://caphrasarchives.com/npc/47685.md) | Not verified |
| 2022 | Great Dark Spot | [Nadir (47700)](https://caphrasarchives.com/npc/47700.md) | Not verified |

## Cross-check notes

- Retrieved and reviewed: 2026-07-30.
- Exact marker coordinates come only from a Caphras NPC page's World Presence
  spawn table. A parent node's coordinate is never substituted.
- Current BDO Codex node-detail manager relations are inconsistent for several
  Pilgrim nodes. The five Pilgrim assignments above use the NPC title, named
  region, and exact spawn coordinate together. For example, Siriya Min is the
  Obedience manager and Saimar is the Sincerity manager.
- The older `20600` Voraro identity is not used. Current manager record 50707
  explicitly identifies Voraro as the Mirumok Ruins node manager and includes
  an exact spawn point.
- A missing marker is deliberate evidence handling, not missing UI. Add a
  coordinate only when an exact current spawn source is available.

## Maintenance checks

`worker_node_unlock_guide_test.dart` requires:

1. every bundled parent-linked excavation node to resolve a guide;
2. all parent IDs to be unique;
3. only exact-location records to enable a marker;
4. conditional, non-numeric Energy wording;
5. current Pilgrim manager assignments to remain explicit.

Any worker-node refresh that adds or reparents an excavation must update this
review before the focused test is changed.
