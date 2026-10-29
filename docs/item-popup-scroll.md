# Item popup scrolling

The Planner's item-reference popup now keeps its scrolling separate from the
Craft Queue. No visual, recipe, calculation, storage or profile changes.

## Cause and correction

`OverlayPortal` paints the popup in the overlay but retains its anchor's widget
ancestry. Scroll notifications from the popup reached the Craft Queue's
`ScrollStartNotification` listener, which dismissed the active popup. Subsequent
wheel input then reached the underlying page.

`AnchoredPopover` now contains scroll notifications at its panel boundary. Child
scrollables still receive normal wheel/drag input, and listeners inside the panel
continue working. Actual parent-page scrolling and the existing dismissal rules
remain unchanged. The existing viewport constraints, artwork and scrollbar-free
appearance are retained. AFK Weight already had a local guard for this issue;
the shared boundary also protects item-reference and other anchored panels.

## Verification

- Reproduced the first-scroll dismissal with the production app, real catalog and
  a disposable synthetic profile before the change.
- Nine full-app tests open Pure Powder Reagent from Tyrant's Blood in all three
  themes, at ordinary size, requested 125% Planner zoom and 200% text.
- Repeated wheel input, both scroll limits, panel padding and body dragging keep
  the popup open and every background scroll position unchanged.
- The final entry is reachable, bounds remain inside the window, Escape closes
  the popup and the underlying Planner scrolls normally afterward.
- 103 existing overlay, smooth-scrolling, Recipe Book and Planner tests pass.
- Synthetic full-app screenshots cover the top and bottom of the long reference.

This is an isolated local correction based on the released 0.1.14 source. The
installed application, earlier runnables, protected backups and personal settings
are not replaced. Publication remains a separate Live Release operation.
