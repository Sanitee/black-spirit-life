# Royal Workshop data

Snapshot: July 30, 2026. Component review: November 2, 2026.

**Royal Workshop management is hidden** (`_royalWorkshopEnabled == false`). Its saved data and planner remain for later work. Hidden settings do not reserve CP or add worker income.

## Preserved model

- Seoul access costs 5 CP. The palace has eight areas: production and processing.
- Each area has one current workshop and one assigned Yukjo Street worker. Storage also comes from Yukjo Street.
- Production goods are daily random choices; processing recipes are selected. One free refresh can be recorded. Movement speed does not affect task time.
- Production areas start with one workshop and allow four unlocks costing 500, then 1,000 tokens each. Processing areas allow two extra unlocks at 1,000 each.

Older per-workshop running state is reduced to the first recorded running workshop in each area, preventing impossible parallel work while retaining notes.

Eight manager IDs and exact coordinates are in `royal_workshop_models.dart`. Their markers do not move the camera. The private client extract is not published.

## Goods and estimates

`royal_workshop_goods.json` has 124 goods: 40 production and 84 processing. It keeps client reference prices, the 29-hour reference at 150 worker speed where present, and rare-roll flags. All names/IDs were checked through October 31; that did not verify prices or drop probabilities.

The catalogue recognizes names, not a complete workshop eligibility list. Users must enter their actual roll or recipe, task time, cycles and net value per cycle. Reference prices are not guaranteed sale values.

Ordinary estimates preserve losses and leave missing inputs unknown. Rare rolls are excluded from dependable income; no drop rates, processing costs, trade bonuses or jackpot averages are invented. If this component is enabled later, its access CP and ordinary subtotal must be kept separate and counted once. See `docs/worker-royal-correctness-20261102.json`.

Community income reports are checks for plausibility, not promised rates. Higher market caps do not prove higher rare-roll chances.

## Sources

- <https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=424>
- <https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=6551>
- <https://www.kr.playblackdesert.com/ko-KR/Adventure/History?_groupMasterNo=13110>
- <https://www.tw.playblackdesert.com/zh-TW/Wiki?wikiNo=851>
- <https://www.blackdesertfoundry.com/royal-workshop-guide/>
- <https://www.blackdesertfoundry.com/land-of-the-morning-light-seoul-patch-guide/>
- <https://www.reddit.com/r/blackdesertonline/comments/1n3jkpn/worker_empire/>
- <https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=13044>
