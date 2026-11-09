# Item window height

Item windows fit their content up to the available screen height. Short content leaves no large empty area; long content scrolls. Text and artwork keep their normal size.

The body uses flexible constraints rather than guessed row counts or hidden measurement copies. Tabs resize and reposition the window while keeping their own scroll positions. Headers stay visible and quantities stay beside names.

This replaced the earlier [fixed-height design](item-window-fit.md). Later width and recipe-layout changes build on the same content-sized approach.
