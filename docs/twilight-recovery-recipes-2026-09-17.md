# Twilight recovery recipes — 17 September 2026

Source: [SEA update details, 17 September 2026](https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19820).

Heating one Causality Shardstone yields five Twilight of the End materials of
the matching accessory slot: Necklace, Earring, Ring or Belt. The Shardstone
must be in the character's inventory to process it.

The existing Twilight records retain their names, icons, market IDs and weights.
Each now has two distinct Recipe Book routes: From Apeiron (one unenhanced
accessory, ten Twilight) and From Causality Shardstone (one Shardstone, five
Twilight). Both have exact output bounds. The previous Apeiron route remains
the default; no existing variant ID was replaced.

These are recovery routes, not ordinary production: crafting a Shardstone
already spends five Twilight plus additional materials. Keep the entire
Twilight record reference-only, so neither valuable accessories nor Shardstones
become automatic inputs to Planner or Opportunities. Both routes remain
browsable in the Recipe Book. No EXP was published for the new route; no numeric
value is assigned. The existing audited EXP records are unchanged.

The same patch removes crafting base Apeiron accessories from Twilight.
Preserve all four accessory item identities and their valid reform recipes,
but remove the obsolete formulas and Heating acquisition claim. Their bundled
nonproduction role also prevents an older saved recipe edit from restoring
automatic crafting. Do not rewrite or delete users' saved edits, inventory,
plans, sessions or settings.

The narrow catalog updater and its regeneration hooks retain all unrelated
catalog data. Regression tests cover the four slots, exact output, readable
reference variants, recovery-cycle exclusion, owned-input safety and older
saved recipe edits. This approved Beta change is included in Stable 0.1.10.
