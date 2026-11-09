# Resource Map layout

The map has two saved styles: **Glass Dock** and **Ghost Ledger**. They are separate from the main app theme. Both keep search and tools together at the upper left so controls do not jump around.

## Shared rules

- Use game artwork for items, tools, houses and nodes where available.
- Keep the map visible. Use one glass panel rather than nested cards or a permanent full-height drawer.
- Size panels to their content and available space. Long text wraps; long lists scroll. Do not shrink text to fit.
- Use the same layout for search, Gathering, Workers, Saved and details.
- Keep ordinary hover text off. Preserve accessibility and specifically approved rich previews.
- Respect reduced motion.

## Sizes

`ResourceMapPanelMetrics` defines 17 px main labels, 14 px secondary text, 20 px headings, 36 px artwork, 28 px tool symbols and rows at least 52 px tall. Search is 52 px tall. Tools fit below search, up to 480 px wide.

Housing is slightly smaller: 16 px labels, 28 px artwork, 44 px simple rows and a measured width of 320–420 px before screen limits. Enlarged text still wraps. Check both styles, short windows and 200% text.

## Saved and housing

Saved opens beneath search, grows with its rows and returns to the same list after viewing an entry. Material favourites keep their IDs; other entries use `map:<search-kind>:<id>` in `favoriteResourceIds`.

Housing requests keep separate workshop types and minimum levels. Reducing a workshop to zero removes that row. Capacity controls request extra beds or slots. Results show the selected houses, their required connections and CP; details open beneath each house. Choosing a house does not move the map.

## Style and storage

Glass Dock uses blurred dark panels with a cyan focus colour. Ghost Ledger uses lighter framing and a cyan rule. Both share short fades and movement from the search area.

The saved field is `PlannerState.extensions.resourceMap.interfaceStyle`. Values are `glassDock` and `ghostLedger`; missing or unknown values use Glass Dock. The working map does not show a permanent style switch.
