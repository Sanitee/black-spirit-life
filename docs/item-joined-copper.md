# Joined copper item windows

Approved on 2026-10-29: option 4, Joined copper, from the Satin rim / Copper spine
mix. This isolated source is based on popup-scroll fix 4339ca3 (released 0.1.14
plus the contained-scroll correction). It is not a public release.

## Scope

Opened/pinned ItemReferenceCard windows now use the approved attached Recipe /
Used for tabs, layers symbol, joined artwork rows and dark copper finish. Sakura
uses the selected static bevel, spine, artwork corners and joined active-tab
edge. Other themes retain their own palettes. No flowers, new animation,
ordinary hover labels or persistent preference were added.

Recipe and Used for remember separate scroll offsets while open. The header and
single applicable Use recipe action stay fixed; multiple methods retain their
own actions. The existing overlay scroll containment, dismissal, dragging,
copying, workstation/variant/batch identity and host navigation are retained.
Long titles and large text reflow at narrow widths. Supplied artwork is honored.

Noninteractive artwork hover references and inline ItemReferenceSections retain
the original full reference, so facts are not hidden behind unclickable tabs.
No catalog, formula, calculation, profile, storage, updater or port changes.
No preview compile flags are required by this implementation.

## Verification and artifacts

Synthetic-only full-app captures cover all three themes at ordinary size,
requested 125% Planner zoom and 200% text. They exercise both tabs, independent
scroll positions, wheel limits, padding, dragging, final-content reachability,
Escape and background scrolling, and assert unchanged synthetic planner state.
Focused tests cover copy callbacks, custom artwork, alternate ingredients,
multiple routes, host formula delegation, item changes and narrow enlarged text.
Existing Recipe Book and anchored overlay regression tests are also run.

Evidence is in the chat workspace at audit/item-joined-copper-20261029 and
work/visuals/joined-copper-actual. See the audit result for exact test/build results
and any pre-existing failures. The separate Windows payload is
build/windows/x64/runner/Release; BlackSpiritLife.exe requires that full folder.

The original popup-scroll source/full runnable were hash-verified before edits.
The preceding preview source remains unchanged; its complete patch was saved
as work/visuals/joined-copper-approved-preview.patch in the chat workspace.
No installed app, personal profile, GUI launch, shortcut, handoff or publication
is part of this change. Live Release remains the publication owner.
