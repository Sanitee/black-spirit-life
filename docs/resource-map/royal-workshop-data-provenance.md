# Seoul Royal Workshop data provenance

Snapshot: 2026-07-30

## Mechanics and interface

The Royal Workshop is modeled as a distinct Seoul system rather than ordinary
worker production nodes. The implementation follows the official interface
structure:

- 5 CP to open the Royal Workshop from Seoul.
- eight palace areas split into production (green) and processing (gold);
- area details with manager, the area's unlocked workshop records, one assigned
  Yukjo worker, one selected workshop/current in-game roll or recipe, task
  time and start/stop state;
- workers and storage come only from Yukjo Street;
- production goods are random daily selections, while processing goods are
  chosen by the player;
- one free refresh can be recorded, and the selected production goods refresh
  daily;
- movement speed does not affect Royal Workshop tasks.

The planner deliberately caps the palace at eight simultaneous assignments:
one worker and one current workshop in each of the eight areas. Earlier private
candidate data that stored workers and running state per sub-workshop is
migrated conservatively to the area's first recorded running workshop so old
notes are retained without double-counting impossible parallel work.

## Workshop unlock records and manager markers

The four production areas start with one workshop and can record four further
unlocks: the first costs 500 Morning's Gratitude Tokens and each of the next
three costs 1,000. The four processing areas start with one workshop and can
record two further unlocks at 1,000 tokens each. The current English client
names are stored for every unlock.

The eight manager NPC IDs and exact client world coordinates are recorded in
`royal_workshop_models.dart`. Selecting a manager places a temporary marker on
that exact point; it does not move the camera automatically. These Pearl
Abyss-origin game facts were normalized from a private 2026-07-30 client
research extract and are not inferred from the basemap. The raw extract is not
part of the public repository.

Primary references:

- Pearl Abyss English Royal Workshop update:
  https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=6551
- Pearl Abyss Royal Workshop update history:
  https://www.kr.playblackdesert.com/ko-KR/Adventure/History?_groupMasterNo=13110
- Pearl Abyss Royal Workshop guide:
  https://www.tw.playblackdesert.com/zh-TW/Wiki?wikiNo=851

The English area labels and recognizable screen layout were cross-checked
against:

- https://www.blackdesertfoundry.com/royal-workshop-guide/
- https://www.blackdesertfoundry.com/land-of-the-morning-light-seoul-patch-guide/

## Goods catalog

`royal_workshop_goods.json` contains 124 current English client item records:

- 40 production goods;
- 84 processing goods;
- client reference prices;
- the client-provided 29-hour reference at 150 worker speed where present;
- an explicit rare-roll flag for rare meals, buffs and artisan materials.

The 124 normalized records were selected from a private 2026-07-30 client
research extract. The raw extract and its original structure are excluded from
the public repository; only Black Spirit Life's application-specific catalog
and the eight normalized manager records ship.

Client reference prices are informational. They are not treated as guaranteed
sale value or as a Royal Workshop drop rate.

The catalog is used only to recognize an exact item name entered by the
player. It is not presented as a per-workshop eligibility list. No sufficiently
trustworthy source for the complete current slot-by-slot eligibility matrix was
available at this snapshot, so the UI asks the player to copy the roll or
recipe currently shown by the game.

## Income policy

The application only estimates a current ordinary task after the player enters:

- the exact current in-game roll or recipe for that individual workshop;
- the task time shown for their Yukjo worker;
- the number of cycles in that task;
- the net silver value of one completed cycle.

Rare meals, buffs and artisan rolls are always excluded from the guaranteed
income total. No selection probability, expected jackpot value, processing
material cost, trade distance bonus or Trading level is invented.

When Royal access is enabled, its 5 CP is reserved before the ordinary
worker-node and lodging route is optimized. Configured ordinary Royal tasks
are then added to the same hourly/day/week headline as the worker-node
portfolio. The Royal Workshop card shows the included subtotal separately,
and the management surface links directly to Yukjo worker and lodging setup.

## Practical income envelope

A community report recorded approximately 52 million clean silver per 24
online hours for a permanent low-cost setup and approximately 58 million for a
more actively managed setup:

- https://www.reddit.com/r/blackdesertonline/comments/1n3jkpn/worker_empire/

That is a useful reality check, not a guaranteed rate. It is roughly 2.2-2.4
million silver per online hour, or approximately 17-19 million during eight
online hours. Results still depend on the live rolls, worker speed, processing
inputs, Trading level, sale location and distance bonus.

The April 2, 2026 update raised Royal Workshop buff-item market caps to
500 million, 900 million or 1 billion silver:

- https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=13044

Those changes make lucky rolls valuable, but do not turn them into dependable
hourly income because the update did not publish higher selection rates.
Recent player reports suggest that rare goods and accumulated token rewards
can dominate long-run realized Royal income, but the reports do not expose a
stable enough probability model to annualize safely. Rare rolls therefore
remain visible and trackable while excluded from the ordinary income total.
