# Gathering energy-helper audit — 3 September 2026

## Result

The catalog now has 18 ordinary Energy entries and 17 optional event entries.
The latter remain inside the collapsed **Event items you may own** section.

| Item | ID | Catalog section | Audited gathering-relevant behavior |
| --- | ---: | --- | --- |
| Energy Tonic (XL) | 17325 | Energy buffs | Restores 100 Energy instantly; 10-minute cooldown |
| Gatherer's Special Herbal Tea | 860435 | Event items you may own | Gathering EXP +100%; Gathering Mastery +150; Energy Recovery +15; Weight Limit +150 LT; Gathering Item Drop Rate +10%; 60 minutes |
| [Event] Energy Gourd Bottle | 752459 | Event items you may own | Restores 100 Energy instantly; 10-minute cooldown |
| [Event] Marni's Endurance Potion | 752460 | Event items you may own | Restores 100 Energy instantly; 10-minute cooldown |
| [Event] FESTA Beer | 790575 | Event items you may own | Restores 100 Energy instantly; also grants immediate Skill and Contribution EXP |
| [Event] Scary Halloween Candy | 752740 | Event items you may own | Life EXP +30%; Life Mastery +25; Gathering Item Drop Rate +5%; Energy Recovery +1; 60 minutes |
| [Event] Western Bourbon Whiskey | 767137 | Event items you may own | Life Mastery +100; Life EXP +50%; Energy Recovery +5; Gathering Item Drop Rate +10%; Movement Speed +5; Luck +5; Weight Limit +100 LT; 180 minutes |
| [Event] Dragon King's Hyangon Wine | 760681 | Event items you may own | Life EXP +30%; Life Mastery +50; Energy Recovery +1; Weight Limit +100 LT; 10 hours |
| [Event] Bubble-bobblin' Budae Jjigae | 46952 | Event items you may own | Recovers 20 Energy instantly; Energy Recovery +1; 3 hours |
| [Event] Coming-of-Age Perfume | 47110 | Event items you may own | Energy Recovery +2; Life EXP +20%; 60 minutes |
| [Event] Scroll - Life Skill I | 767989 | Event items you may own | Life Mastery +100; Life EXP +20%; Energy Recovery +1; 2 hours |
| [Event] Scroll - Life Skill II | 767990 | Event items you may own | Life EXP +100%; Life Mastery +100; Mount EXP +50%; Energy Recovery +1; 3 hours |
| [Event] Divine Blessing of Life | 1000408 | Event items you may own | Life Mastery +150; Life EXP +50%; Weight Limit +200 LT; Energy Recovery +5; Movement Speed +5; Luck +5; 3 hours |

Instant restorations are reference-only. They do not inflate the ongoing Energy
Recovery total. Dragon King's Hyangon Wine also has normal Item Drop Rate +20%;
that is monster-loot rate and is deliberately not counted as Gathering Item Drop
Rate.

The Bairog projection currently has no owned-quantity or cooldown schedule for
untradeable event refills. Treating one Gourd Bottle, Marni potion, or FESTA Beer
as permanent recovery would overstate the session. Those three therefore open
their full information instead of becoming calculation toggles. A future
consumable scheduler would need the user's quantity and intended use cadence
before these can safely alter projected session length.

## Evidence checked

- Current installed-client export:
  `Patch Research/client-2026-09-03-audit/items.json`.
- Exact installed-client artwork from the matching 3 September icon export.
- The 28 August and 3 September exports were compared for Energy Recovery and
  Maximum Energy changes. Gatherer's Special Herbal Tea was the only new
  qualifying item in that delta.
- Official Pearl Abyss notices were checked for current sale/pass availability,
  past event distribution, and continued Fairy Continuous Care support.

The inclusion boundary is a user-facing consumable with a verified Energy effect
and a credible reason it may still be usable or owned. The audit favors unique,
useful effects over every historical low-tier duplicate.

## Deliberate exclusions

- Snowfall Ginger Cookie, Hot Apple Cider, Adventure Together Scroll (Life),
  Breath of the Black Wings (Life), Global Banquet Platter (Life), and Fatebound
  Resolve are marked for removal when their events end, so they are not presented
  as items a player may still own.
- Shai's Cheer and Rabbit's Blessing are direct-apply event rewards in the current
  client, rather than inventory consumables a user can choose from this setup.
- Divine Blessing of Life is retained: it is an inventory consumable without an
  event-end removal notice and has a recent official distribution notice.
- Bubble-bobblin' Budae Jjigae and Coming-of-Age Perfume are retained because the
  current client still defines their effects and the May 2025 update explicitly
  added them to Fairy Continuous Care.
- Life Skill Scrolls I and II are retained because they are portable inventory
  versions of furniture buffs. They share the existing `furniture` exclusion
  group, so the calculator cannot add them to each other or to Blessing of Mystic
  Beasts.
- Individual residence furniture is not duplicated in this picker. The current,
  tradable Blessing of Mystic Beasts already represents that non-stacking buff
  family, while the two portable event scrolls cover the owned-event case.
- Blessing of Fragrant Wind was explicitly deleted after its event.
- Weaker Energy Potion and Energy Tonic sizes remain omitted to keep the setup
  useful instead of listing redundant tiers.
- Old low-value event foods and sweets that merely repeat small instant or +1
  recovery effects remain omitted. They add no distinct setup calculation and
  would bury the meaningful choices.
- Internal, GM/test, quest-direct, and unnamed `Recover Energy` records are not
  user-facing inventory items and remain excluded.

## Primary notices

- [3 September 2026 Gathering Special Pass](https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=19776)
- [3 September 2026 Pearl Shop update](https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=19771)
- [Energy Gourd Bottle and Dragon King's Hyangon Wine distribution](https://www.naeu.playblackdesert.com/en-US/News/Detail?countryType=en-US&groupContentNo=8797)
- [Fairy Continuous Care item support](https://www.naeu.playblackdesert.com/en-us/News/Detail?groupContentNo=8591)
- [Marni's Endurance Potion](https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=3762)
- [FESTA Beer](https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=3888)
