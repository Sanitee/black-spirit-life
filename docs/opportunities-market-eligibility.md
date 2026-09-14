# Opportunities market identity scope

The Opportunities workspace uses two fixed numeric item-ID tables derived from
read-only audits of Black Desert PC client metadata. They are request-selection
and grouping aids only: they do not contain prices, account state, inventory,
planner state, session data, local client paths or extractor payloads.

## Request eligibility

The 3 September 2026 client audit source was 97,581,268 bytes with SHA-256
`108E8302014FDFBDAF324FFF08C833CF879AF39F9600BBD3DFD0C5808779FE2B`.
The audited Opportunities scope contained 1,748 item IDs. Of those, 298 had a
false Central Market flag and are listed in
`lib/data/opportunities/market_eligibility.dart`; the remaining 1,450 had a
true flag. Unknown or custom IDs stay eligible, and network failures never add
an ID to the exclusion table.

Eight separately reviewed identities are temporarily archived while their
current acquisition sources remain unconfirmed: Monkey Blood (6211), Monkey
Hide (6011), Dinosaur Hide (6007), and Black Magic Crystal - Power (15202),
Patience (15208), Healing (15209), Resonance (15210), and Endurance (15215).
That policy lives in `lib/domain/catalog/temporarily_archived_items.dart` and
does not delete saved values or classify a failed request as unlisted.

## Enhancement grouping

The 10 September 2026 client audit source has SHA-256
`8998F94AA44A5DD86DC5F67F4CFA73EF1523E3B051B58D8F0F9DC42E592912E5`.
Its 2,842 marketable identities with a positive maximum enhancement level are
listed in `lib/domain/catalog/enhanceable_market_items.dart`. The table only
allows search summaries to combine enhancement levels; it does not infer
price, availability or eligibility from an item name or ID range.

## Reproduction boundary

The source client exports and extraction utilities remain outside the public
repository. Rebuilding either table requires a fresh read-only client audit,
the same field definitions, and a review of the resulting exact numeric IDs.
The public repository retains the source hashes above so a future audit can be
compared without publishing local installation details or unrelated client
data.
