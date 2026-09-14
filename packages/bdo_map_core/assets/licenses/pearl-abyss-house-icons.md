# Black Desert house-use icons

The house-use artwork is Pearl Abyss game material, retained under this app's
recorded free, noncommercial, unofficial fan-content basis. No independent
license from a database website or extractor author is claimed for the artwork.

Retrieved read-only from the owner's installed Black Desert client on
2026-08-31 (patcher_version 89). Archive path:
`ui_texture/new_ui_common_forlua/window/houseinfo/houseicon.dds`.

- Original DDS SHA-256: `10dc35bf38f551938d21a1a67b987e810d91638b36c8eac524037200444d0de2`
- Bundled decoded PNG SHA-256: `c7345dee93f887da1964da1d8f75e9d97a6a1522b11ef1e508c2f3cf4adfac87`
- Output: `assets/images/house_icons/houseicon.png`
- Format decoding: iDevelopThings/bdo-data-extractor v0.1.9, source commit
  `5bf11bd7bc60dcbb6126be34bf3d76633abdd8b2`, `textures` command.
  https://github.com/iDevelopThings/bdo-data-extractor

The complete texture is retained without graphic editing. Flutter selects the
18 × 18 icon cells and applies the current readable foreground color at render
time. Rectangles follow `HouseControlManager:UseTypeIconTexture`; house recipe
IDs are translated to UI use groups rather than treated as texture coordinates.
The game deliberately shares its local-specialties gear icon across fish,
mushroom, crop, timber and mineral workshops.

Reference for the game's UI group names and icon coordinates:
https://github.com/bberka/bdo-decompiled-lua/blob/main/window/houseinfo/panel_new_housecontrol.lua
https://github.com/bberka/bdo-decompiled-lua/blob/main/include/global_define_cpp_enum.lua

Only the artwork is shipped. No extractor executable, game script, game
database, client path, or downloaded research repository is included in a build.
