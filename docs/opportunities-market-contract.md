# Market data rules

The Opportunities adapter reads public market data without an account or trading actions. Its endpoint format was checked on EU on September 8, 2026. The price rules below also reflect the current calculator.

## Requests

Use read-only POST requests to:

- `https://eu-trade.naeu.playblackdesert.com/Trademarket/GetWorldMarketSubList`
- `https://eu-trade.naeu.playblackdesert.com/Trademarket/GetBiddingInfoList`

NA uses the `na-trade` host. A quote request is `{"keyType":0,"mainKey":4998}`; the order book adds `"subKey":0`.

Quote fields are ID, minimum/maximum enhancement, base price, stock, lifetime trades, minimum/maximum price, last sale price and last sale Unix seconds. Select the requested ID at enhancement zero. Failed or malformed data stays unknown, not zero or NPC-only.

The book has a little-endian header, symbol frequencies and a Huffman stream. Frequency ties use the server's frequency-only heap order. Decoded rows are `price-sellers-buyers|`. Check headers, result codes, unique symbols, numeric alphabet, decoded length, actual frequencies and unique price levels. Limit input and output to 1 MiB.

## Prices and availability

- Key records by item ID. Quote and book timestamps are separate.
- Missing depth is unknown; an empty list means checked and empty.
- Stock and orders can coexist. Trade totals are not current demand.
- Buy from the lowest asks; estimate immediate sales from the highest bids. Never exceed each level's quantity.
- A summary stock count cannot replace ask depth. Domain calculators apply tax, NPC prices and profit rules.
- Check each value's age. Future timestamps, failed requests or a new quote must not make an old book fresh.

For ingredients that cannot be bought now, use the highest valid occupied preorder price from a fresh book. If none is available, use a fresh positive base price. Keep actual ask and NPC costs for quantities they cover. Unknown prices stay unknown, not free. A price estimate never creates stock or makes a recipe ready to buy.

Exchanges may show a separate after-tax listing estimate when checked buyers cannot cover the output. Keep immediate-sale quantities and proceeds separate, and retain account limits. Unpriced rewards are not invented income. Quote minimum/maximum fields are overall item limits, not verified current bid-band caps.

## Refresh and storage

Allow at most four concurrent requests with 140 ms spacing per worker. Serialize calls on one service; support cancellation, progress and per-item errors. Do not assume a batch endpoint.

Quotes and books are session-only. Successful trade counters can be saved through `OpportunityMarketObservationStore`, using the selected profile folder and `AtomicFileStore`. The versioned `opportunity-market-observations.json` keys by region/item/sub-ID with `pearl-abyss` provenance. Keep at most 10,000 items, 128 samples each and seven days. Failed writes preserve the old file and in-memory history.

Sales activity needs two comparable counters at least an hour apart; the default lookback is 24 hours. Use their real interval. A falling counter starts a new baseline; ignore future or out-of-order readings. No change over a valid interval means zero. A first reading means unknown.

## Checks

Run `test/opportunities/opportunity_market_test.dart`. The optional `test/opportunities/opportunity_market_live_test.dart` needs `OPPORTUNITY_MARKET_LIVE_TEST=1`; it is skipped by default and saves no observations. Historical live prices are not defaults.
