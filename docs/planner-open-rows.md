# Planner Open rows

The user selected Open rows from `planner-defined-stripes.html` and asked to see
the actual implementation. Craft Queue ingredients now use uninterrupted,
alternating full-width bands inside each existing craft card. Ingredient artwork
and both quantity labels sit directly on the bands, without separate frames or
quantity backings. There are no inset row cards, extra separators or animations.

The existing card header, buttons, rounding and Sakura corner decoration remain.
Rows use the current theme's surface and primary colors; light themes use a
restrained darker tint. Names and controls wrap, and the existing larger-text
quantity layout remains active. Per-craft and batch quantities retain accessible
labels without hover popups. No new preference is introduced.

This applies only to the main Planner's Craft Queue. Need First, Bonus Recipes,
Inventory, Opportunities and the maps retain their presentation. Real artwork,
copy/substitute/quality/acquisition/map actions, collapse, completion/Undo,
processing variants, calculations and persistence remain unchanged.

## Candidate and protection

Source: `D:/Codex/Black Spirit Life/Fish Startup Fix 20261029`, branch
`codex/planner-open-rows`, based on the user-tested Fish startup fix
`896c6f7e02bc7587b37e4ccd7793bbb88f201c98`.

Separate build output: `build/planner-open-rows/windows/x64/runner/Release/BlackSpiritLife.exe`.
The prior full runnable under `build/opportunities-crafted-sale` is not replaced.
No installed app, shortcut, personal profile, release metadata or public download
is changed. This is a local candidate awaiting the user's visual review, not a
public release or acceptance of the new design.

Before editing, the accepted Fish fix's complete tracked source (10,715 files)
and complete runnable (9,582 files) were copied and hash-verified at:
`D:/Codex/Black Spirit Life/Protected Rollback/accepted-fish-startup-20261029T085531981Z`.
Manifest SHA-256: `059523D1E0D9B64595374C913475A18A0A59029A91D3E32F3D094EA86218DFA9`.
The preceding accepted update-glow snapshot also passed full verification.

## Verification and real screenshots

The regression suite covers current quantities and math, modes/themes, Bonus
isolation, substitute/quality/copy/map actions, inventory editing, acquisition,
completion, reset and existing adaptive layouts. Only superseded quantity-badge
assertions and their padding expectations were updated.

`planner_open_rows_test.dart` renders the real application and catalog at
1500 × 940 and 1200 × 752, plus 1200 × 940 with 200% text, in Sakura, Ledger and
Standard. It checks uninterrupted card-width stripes, alternating colors, no
ingredient icon frames or quantity backings, unchanged inventory/quantities,
collapse/reopen, absence of layout exceptions and reachability of the final row.

Screenshots use only disposable synthetic state and no live market requests.
The example selects Chicken Breast Salad, amount 100, with 100 Vinegar owned.
These are actual Flutter renders, not HTML mockups or generated artwork.

Evidence and final build/verification results are in the chat workspace:
`audit/planner-open-rows-20261029`. Captures are in
`work/visuals/planner-open-rows-actual`. No personal settings were read or altered.

All 122 focused widget tests passed; scoped analysis and `git diff --check` are
clean. The separate Windows Release build succeeded. It reported the existing
OCR compiler search-path warnings for unavailable `atlmfc/lib/x64` and
`lib/um/x64`; these did not prevent building the payload. Flutter's original
build-directory configuration was restored after the isolated build.
