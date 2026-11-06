# Content-sized item windows

Requested on 2026-10-29 as a refinement of the taller Joined copper window.

The window now shrink-wraps the active tab's actual content, with the existing
available viewport height as an upper bound. Short descriptions and recipes no
longer reserve a blank reading area. Complete ordinary recipes fit naturally;
longer recipes and multiple-recipe lists can use the available height before
their body scrolls. A recipe taller than the available screen must still scroll,
especially with enlarged text. No text or artwork is reduced to force a fit.

This uses a minimum-size column and loose flexible scroll body, rather than
estimated row counts, duplicate hidden measurement widgets or asynchronous
resizing. Wrapped names, alternatives, effects and theme/text metrics therefore
participate in the actual layout. The existing overlay placement may move the
panel when its tab changes size; scrolling never moves its header or background.
The header and single-recipe action remain fixed, separate tab offsets remain,
and primary quantities remain directly beside the names.

## Verification

- 24 actual-application synthetic-profile cases cover Clown's Blood and Tyrant's
  Blood, all three themes, 1200x752, 1200x600, zoomed 1500x940 and 200% text.
- Full Clown's Blood including all alternatives fits without scrolling at the
  ordinary and zoomed sizes; smaller/enlarged cases remain scrollable.
- 281 Recipe Book, Planner popup and anchored-overlay regression checks passed.
  New checks cover short content, a full recipe, ten distinct synthetic recipes,
  complete first/final recipe visibility, screen resize and shrinking after
  scrolling, independently in all three themes.
- Focused analysis passed. The build outcome and full payload identities are
  recorded in the workspace audit result, not inferred from test success.

No calculations, catalogue identities, saved state, profile/schema contracts,
release version, updater, port policy, artwork hovers or inline references change.

## Isolation

Source: `[private-source]/Item Window Auto Height 20261029`, branch
`codex/item-window-auto-height`. Base is released v0.1.15 commit
`a45165ddfa27c67cc19d617f0b182fb6b4e34e5d`, plus the complete preceding staged
height/inline-quantity implementation, then this refinement. HEAD alone does not
contain the changes.

Separate runnable: `build/windows/x64/runner/Release/BlackSpiritLife.exe`.
Evidence: workspace `audit/item-window-auto-height-20261029`; actual screenshots:
`work/visuals/item-window-auto-height-actual`.

The preceding Item Window Fit source (10,730 files) and full runnable (9,582
files) were freshly hash-verified against manifest
`2E2146C0A3ADA07E1E19DCA4D36859A9963423BFA09BF6AB859FF3A8E7C66C22`
before work and remain untouched in their original isolated location. Released
v0.1.15 source and all earlier accepted backups remain unchanged. No personal
profile was accessed, application window launched, installed app replaced, or
Live Release handoff/publication performed. User review remains separate.
