# Map sources and packaging

This is the **0.1.7 source review**. Its counts and hashes are historical. Use the current release plan for versions, tags and artifact checks; do not reuse the old 0.1.7 publishing steps.

## Credits and use

Pearl Abyss owns the game facts and artwork. BDO Codex and BDOLytics are credited research references. The app retains selected facts in its own format, not website design, HTML or guide prose.

The owner approved credited Workerman/Shrddr use for tiles/cache, 64 node icons, the 812-house/31-town graph and economics inputs for 352 sites/30 towns. No separate written licence was found. This is the owner's risk decision, not permission from Shrddr. Keep attribution and respond to substantiated corrections/removal requests.

- [Workerman source](https://github.com/shrddr/workermanjs)
- [Workerman issues](https://github.com/shrddr/workermanjs/issues)
- [Map tiles](https://github.com/shrddr/shrddr.github.io/tree/main/maptiles)

## Reviewed data

The reviewed `packages/bdo_map_core/assets/data/resource_map.json` is 7,544,577
bytes with SHA-256
`BE62E56A6B18F14C7A6439521A9CA9CA240974219DBD1E44D85CDEC136C94C15`.
That snapshot contains Black Spirit Life's normalized application schema, including:

- 1,052 Pearl Abyss-origin worker-node records and 1,622 output relationships;
- 13,315 exact gathering points: 12,582 historical SomethingLovely points,
  501 Stone Cobra/Rock Scorpion points, 34 Rusalka points, and 198 Stillcoral
  coastal points;
- 51 planner-relevant vendor items, 266 physical NPC pins, and 1,243
  item-to-vendor listings; and
- the retained Edania, Royal Workshop, hunting and resource-map relationships.

That snapshot contains no raw response, HTML, page design or site-authored prose. The
worker-node, recipe, price, NPC and coordinate records are selected and
normalized game facts used by Black Spirit Life's original interface,
calculations, search, filtering and routing.

The reviewed `lodging_houses.json` is 789,050 bytes with SHA-256
`096D1205BBB12FD0ED0AD0F9AE1A613C680AE0E037CDAA4AF91C7F4AD4EFA6F6`.
The reviewed `worker_economics.json` is 354,383 bytes with SHA-256
`64ABEDA209B82EA1CAF6FC8C5EB29DDC8F1007837FA4D13652ABE534697C29D7`.


## Public files

Follow the [source rules](../public-release-source-matrix.md). Exclude the six private research inputs and all personal saves, accounts, credentials, caches, browser state, machine paths and internal release files. Keep generated reference data and the approved features. Check public refs/history as well as current source.

## Tile cache

Limit disk tiles to 64 MiB per provider and decoded images to 48 MiB. Keep cache-only viewing, distinct missing-area status, cancellation and late-response rejection. Clearing tiles must not touch saves.

A revisioned cache name prevents mixing reviewed versions; it does not make the live upstream URL immutable. No tiles are bundled.

## Release checks

Use the exact approved source, current release plan and artifact hashes. Keep source/privacy, build, install/update, save-preservation and public-download checks separate. Record any unrun checks honestly. The installer is unsigned, so the download page must disclose the possible Windows warning.

Source corrections or removal requests go through this repository's Issues tab. Replace only the affected material; preserve unrelated app behaviour and personal data.
