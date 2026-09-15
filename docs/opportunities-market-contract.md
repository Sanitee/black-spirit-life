# Opportunities market contract

Verified against the EU official endpoints on 2026-09-08. This adapter is separate
from the existing planner refresh and does not mutate planner caches or choices.

## Data sources

Read-only POST requests go directly from Dart HTTP to:

- `https://eu-trade.naeu.playblackdesert.com/Trademarket/GetWorldMarketSubList`
- `https://eu-trade.naeu.playblackdesert.com/Trademarket/GetBiddingInfoList`

NA uses the corresponding `na-trade` hostname. No account, cookies, credentials,
browser process, scraper service, or trading action is involved.

The quote request is `{"keyType":0,"mainKey":4998}`. For ordinary non-enhanced
materials the successful compact row fields are ID, minimum enhancement, maximum
enhancement, base price, stock, lifetime trades, minimum price, maximum price,
last sale price, and last sale Unix seconds. The decoder selects only the
requested ID at enhancement zero. Missing, malformed, or unsuccessful responses
remain unavailable; they do not become zero stock or permanent NPC-only status.

The book adds `"subKey":0`. Its binary format contains a little-endian header,
symbol frequencies, and a Huffman stream. Heap ties must follow the server's
frequency-only ordering. Decoded rows are `price-sellers-buyers|`. The decoder
checks header sizes, result code, symbol uniqueness, numeric alphabet, decoded
length, actual symbol frequencies, and unique valid price levels. Input/output
are bounded to 1 MiB. The existing captured book fixture is tested alongside
truncated and malicious header cases.

## Financial interpretation

- Snapshot keys are numeric item-ID strings, not display names.
- Quote and book timestamps are independent and per item.
- Null depth means unknown; an empty list means that side was checked and empty.
- Stock and preorders can coexist at different prices. Zero stock never implies
  preorders; lifetime trades never imply current demand.
- Buy fills consume lowest asks first. Immediate sale estimates consume highest
  bids first. Each fill is capped by its returned quantity.
- Summary stock is not a substitute for the returned ask depth.
- Fills do not apply tax, NPC rules, or profit policy. Domain calculators own those
  choices. A fill is an estimate against the checked book, not a promised sale.
- Callers must check freshness using an explicit time and maximum age before
  interpreting depth as presently executable. Future timestamps are not fresh.
- Merging a quote never refreshes an older book. A failed lookup contains no
  replacement item and cannot falsely refresh cached values.

### Current-price estimates (user-approved, 2026-09-09)

A confirmed input shortage may be valued at the fresh base market price. Any
available quantity keeps its actual ask-level cost; only the missing quantity
uses the base price. The ingredient and full-run estimate are explicitly marked.
Actual purchased/available quantities, input capacity, and `marketReady` do not
change. Unknown/stale books or quotes never qualify. Fully buyable formulas and
substitutes take priority over cheaper unavailable estimates.

For exchanges, checked insufficient buyers may attach a separate after-tax
listing estimate. The original immediate-sale quote keeps its actual covered
quantity, proceeds, and availability. Account limits and requirements still apply
to the listing estimate. Unknown market data and unpriced utility rewards do not
become valued income.

These are **base-price estimates**, not maximum-price estimates. A live check on
2026-09-09 showed that quote minimum/maximum fields are the overall item limits,
while the anonymous book contains occupied levels and a base-price row rather
than the complete allowed tier ladder. Neither is a verified current band cap.

## Scan and persistence

The service scans individual verified endpoints with at most four concurrent
requests and 140 ms spacing per worker. Calls on one service are serialized,
support cancellation/HTTP abort, and provide progress plus per-item callbacks.
Timeouts and failures are returned per item. A batch endpoint was not assumed
without a verified contract.

Quote/book snapshots are session-only. The caller explicitly records successful
quote counters through `OpportunityMarketObservationStore` and enriches the
merged snapshot with `withActivity`. The store uses the caller's resolved profile
directory and `AtomicFileStore`; it never assumes a fixed AppData path.

The separate `opportunity-market-observations.json` is versioned and keyed by
region, item ID, and sub-ID, with `pearl-abyss` provenance. It retains at most
10,000 items and 128 samples per item, coalesces frequent refreshes, and prunes
history older than seven days. A successful write publishes the in-memory update;
a failed write preserves the prior file and history.

Visible activity is the difference between two observed cumulative counters over
their actual interval. The first sample and intervals under one hour are unknown.
The default lookback is 24 hours. A decreasing counter starts a new baseline;
out-of-order/future samples are ignored. Zero change over a valid interval is a
known zero. There is no fabricated daily-sales rate.

## Verification

Deterministic suite: `test/opportunities/opportunity_market_test.dart`.
Optional live contract check: set `OPPORTUNITY_MARKET_LIVE_TEST=1` and run
`test/opportunities/opportunity_market_live_test.dart`. It is skipped by default
and does not persist observations.

New-service live check, 2026-09-08 16:03:28 UTC:

| ID | Base price | Stock | Buyers | Ask / bid levels | Lifetime trades |
|---|---:|---:|---:|---:|---:|
| 4998 | 5,450,000 | 21,821 | 5,760 | 9 / 3 | 278,512,887 |
| 50804 | 1,640,000 | 7,027 | 300 | 11 / 1 | 62,459,271 |

These are dated verification captures, not production defaults or example profit
inputs. The implementation always requests current values.
