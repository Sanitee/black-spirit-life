# Scrolling inside item windows

Scrolling an item popup used to reach the Planner behind it and could close the popup.

`AnchoredPopover` now contains those scroll notifications. The popup still scrolls normally, including at its ends and over padding. Scrolling the underlying page keeps its existing behaviour.

Regression checks cover the mouse wheel, dragging, the final entry, Escape and the page's unchanged scroll position.
