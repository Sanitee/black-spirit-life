# Market item IDs

Two numeric-ID tables decide which items to request and which enhancement levels can be grouped. They contain no prices or user data.

## Eligibility

The September 3, 2026 audit covered 1,748 IDs: 298 nonmarket items in `lib/data/opportunities/market_eligibility.dart` and 1,450 market items. Unknown/custom IDs remain eligible. Failed requests never mark an item nonmarket.

Source: 97,581,268 bytes; SHA-256 `108E8302014FDFBDAF324FFF08C833CF879AF39F9600BBD3DFD0C5808779FE2B`.

Eight items were separately archived while their acquisition sources were unconfirmed: Monkey Blood 6211, Monkey Hide 6011, Dinosaur Hide 6007, and Black Magic Crystal IDs 15202, 15208, 15209, 15210 and 15215. See `lib/domain/catalog/temporarily_archived_items.dart`. This does not delete saved values.

## Enhancement levels

The September 10 audit identified 2,842 market items with enhancement levels. `lib/domain/catalog/enhanceable_market_items.dart` lets summaries group those levels; it does not infer prices or availability from names or ID ranges.

Source SHA-256: `8998F94AA44A5DD86DC5F67F4CFA73EF1523E3B051B58D8F0F9DC42E592912E5`.

Refresh these tables through a read-only client review using the same fields and exact IDs. Client exports, extraction tools and local installation details stay private.
