# Resource Map Release and Packaging Gate

## Controlling source decision

The source review is complete for Black Spirit Life `0.1.3+22`.

- Pearl Abyss-origin icons, portraits, descriptions, recipes, NPC information,
  prices, coordinates and node facts are treated as game content and factual
  information under the project's noncommercial fan-content basis.
- BDO Codex and BDOLytics are credited research, cross-checking and retrieval
  references. Black Spirit Life retains no site HTML, design, guide prose,
  commentary or annotation.
- Six source-only private research inputs are excluded from the public tree.
  The normalized runtime datasets remain.
- The four Workerman/Shrddr groups below are approved for this release under
  the project-owner community-use decision. They are not publication blockers.

## Workerman/Shrddr community-use decision

The approved attributed use covers:

1. the Workerman/Shrddr map tiles and bounded runtime cache;
2. the 64 node icons;
3. the Workerman-derived 812-house/31-town lodging graph; and
4. the Workerman-derived inputs in the 352-site/30-town worker-economics table.

WorkermanJS and its related map repository are intentionally public, Workerman
is publicly hosted for community use, and its documentation directs users to
the public GitHub issue tracker when they encounter problems. Black Spirit
Life is completely free and noncommercial, with no advertisements, donations,
subscriptions or paid features.

- Source project: <https://github.com/shrddr/workermanjs>
- Public issue route: <https://github.com/shrddr/workermanjs/issues>
- Tile repository: <https://github.com/shrddr/shrddr.github.io/tree/main/maptiles>

No separate written licence file was found. The project owner explicitly
accepts that residual risk and does not represent this decision as separate
written permission from Shrddr. Complete attribution, the public correction
and removal route, and prompt compliance with any future substantiated request
from Shrddr are required.

This decision is not to be reopened merely because there is no separate
licence file or personal reply. Reopen it only if new concrete evidence appears
that Shrddr prohibits this use.

## Runtime data boundary

The shipped `packages/bdo_map_core/assets/data/resource_map.json` is 7,801,681
bytes with SHA-256
`50CFE1C7A6FAD8AA731578A67C305C9C703A619AF7EDCE5C5142EA9E826AC462`.
It contains Black Spirit Life's normalized application schema, including:

- 1,052 Pearl Abyss-origin worker-node records and 1,622 output relationships;
- 13,315 exact gathering points: 12,582 historical SomethingLovely points,
  501 Stone Cobra/Rock Scorpion points, 34 Rusalka points, and 198 Stillcoral
  coastal points;
- 51 planner-relevant vendor items, 266 physical NPC pins, and 1,241
  item-to-vendor listings; and
- the retained Edania, Royal Workshop, hunting and resource-map relationships.

It contains no raw response, HTML, page design or site-authored prose. The
worker-node, recipe, price, NPC and coordinate records are selected and
normalized game facts used by Black Spirit Life's original interface,
calculations, search, filtering and routing.

The shipped `lodging_houses.json` is 789,050 bytes with SHA-256
`096D1205BBB12FD0ED0AD0F9AE1A613C680AE0E037CDAA4AF91C7F4AD4EFA6F6`.
The shipped `worker_economics.json` is 354,383 bytes with SHA-256
`64ABEDA209B82EA1CAF6FC8C5EB29DDC8F1007837FA4D13652ABE534697C29D7`.

## Public source boundary

The sanitized public repository is created from an explicit reviewed
allow/exclude list rather than a plain copy of the development repository. It
must omit all six private research inputs listed in
`docs/public-release-source-matrix.md`, retain the generated runtime data and
full application functionality, and keep the internal copies untouched.

The public tree must also exclude personal planner data, local machine paths,
private update feeds, credentials, caches, diagnostics, backups, screenshots,
private release artifacts and internal-only release history. A fresh clone and
all public refs/tags must pass the same scan.

## Cache and network safeguards

The map implementation:

- limits encoded disk tiles to 64 MiB per provider namespace;
- limits decoded images to 48 MiB;
- uses a revisioned provider cache namespace;
- allows cache-only viewing and reports uncached offline areas distinctly;
- cancels the app-owned HTTP client when downloads are disabled;
- rejects late network results by request epoch; and
- exposes cache size and a clear action without touching planner data.

The revisioned namespace is an invalidation label. The live upstream URL is not
content-addressed and is not described as cryptographically pinned.

## Remaining technical release gate

Before publication:

1. create and scan the neutral-author, one-commit public source snapshot;
2. tag that exact commit `v0.1.3`;
3. build the Stable app and installer from that clean tagged commit with
   package `BlackSpiritLife.App`, channel `win-x64-stable`, and GitHub update
   source `https://github.com/Sanitee/black-spirit-life`;
4. run analysis, automated tests, clean-install and installer lifecycle checks;
5. verify the previous-version in-app delta update, automatic apply/restart,
   profile preservation, offline map/planner behavior, repair and both
   uninstall choices;
6. enumerate the exact release files with byte lengths and SHA-256 hashes; and
7. obtain immediate project-owner approval for the exact commit, tag, release
   notes, files, hashes and GitHub actions before any public publication.

The unsigned installer may trigger Windows SmartScreen or an
unfamiliar-publisher warning; this must be disclosed on the release page.

## Corrections and removal requests

Use the repository's public issue route for source corrections or removal
requests. If new concrete evidence or a substantiated request from Shrddr
requires a change, address the exact affected provider, assets or dataset
promptly without silently changing unrelated planner or map functionality.
