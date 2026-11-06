# Taller item windows and inline quantities

Historical fixed-height candidate. The subsequent content-sized implementation
is documented in [item-window-auto-height.md](item-window-auto-height.md).

Requested on 2026-10-29 after the Joined copper v0.1.15 release.

Pinned Joined copper windows now allow 760 logical pixels of height instead of
548, scaled with the existing text-scale allowance and still limited by the
available viewport. This gives ordinary complete recipes room without reducing
type or artwork sizes. The Recipe / Used for header and single-recipe action
remain fixed; smaller windows and enlarged text retain safe independent scrolling.

Primary ingredient quantities now sit 8 logical pixels after the ingredient
name, on its text baseline. Long names can wrap without pushing quantities out
of the row. Alternatives, exact-name copying, semantic labels, formula quantities
and recipe actions are unchanged. No ordinary tooltips, persistence, data or
calculator changes; noninteractive hovers and inline references are unchanged.

## Verification

- 24 full-app synthetic-profile cases: Clear Liquid Reagent / Clown's Blood
  (the reported recipe) and Pure Powder Reagent / Tyrant's Blood, across all
  three themes, 1200x752, a constrained 1200x600, requested 125% Planner zoom
  at 1500x940, and 200% text.
- The complete Clown's Blood recipe, including alternatives, has zero scroll
  extent at ordinary and zoomed application sizes in all three themes.
- Overflowing smaller/enlarged layouts still scroll, retain tab positions,
  reach their final contents and never move the underlying Planner.
- Inline-quantity placement and copying are checked at 100% and 200% text.
- 278 further Recipe Book, popup and overlay regression checks passed.
- Focused analysis passed. See the chat audit for the final Windows build result.

Actual app captures: chat workspace work/visuals/item-window-fit-actual.
Evidence: audit/item-window-fit-20261029.

This isolated source starts at released v0.1.15 commit
a45165ddfa27c67cc19d617f0b182fb6b4e34e5d. The original release source remains
clean and the 727,482,106-byte published full package was freshly hash-verified
(F5F1FABC868C95E456C1E1E05D6858B2ED40CF51CCD0F69AF3CBF875A40F2B31).
Existing protected source/runnable snapshots and release artifacts are untouched.
The full separate runnable is build/windows/x64/runner/Release; do not detach
BlackSpiritLife.exe from its supporting files. No app launch, profile access,
installed-app replacement, handoff or publication is part of this adjustment.
