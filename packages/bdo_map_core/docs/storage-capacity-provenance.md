# Storage capacity provenance

The Storage investment planner uses the level-to-capacity table shown on the
BDO Codex Storage house page:

- Source: <https://bdocodex.com/us/npc/3107/>
- Reviewed: 2026-08-20
- Storage level 1: 3 slots
- Storage level 2: 5 slots
- Storage level 3: 8 slots
- Storage level 4: 12 slots
- Storage level 5: 16 slots

The production house graph records the maximum Storage level available for
each house, not the player's active upgrade level. Until an active-level field
is added, an owned house explicitly saved as Storage is counted at that mapped
maximum level. Owned houses saved to another use, and owned houses with an
unknown use, remain protected and are never silently converted by the solver.

The optimizer is town-local and minimizes incremental contribution points for
a requested number of extra slots. It includes prerequisite houses, reuses
owned prerequisites at zero additional CP, and reports any unavoidable slot
oversupply. It does not currently optimize the inverse “maximum slots for a CP
budget” question.
