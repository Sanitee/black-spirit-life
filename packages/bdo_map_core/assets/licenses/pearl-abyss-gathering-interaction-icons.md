# Black Desert gathering interaction icons

The interaction artwork is Pearl Abyss game material, retained under this app's
recorded free, noncommercial, unofficial fan-content basis. No independent
license from a database website or extractor author is claimed for the artwork.

Retrieved read-only from the owner's installed Black Desert client on
2026-08-31 (patcher_version 89). Archive path:
`ui_texture/new_ui_common_forlua/widget/interaction/interaction_00.dds`.

- Original DDS SHA-256: `97b3e0f8710230fe1cd7dcb1736a637f4af426cb9363886be8285f6d1f6b4812`
- Bundled decoded PNG SHA-256: `7bd9c32b3db4ef0d325db3901c563e8bb41cbbed62beb246941350afcc47171f`
- Output: `assets/images/gathering_tools/interaction_00.png`
- Format decoding: iDevelopThings/bdo-data-extractor v0.1.9, source commit
  `5bf11bd7bc60dcbb6126be34bf3d76633abdd8b2`, `textures` command.
  https://github.com/iDevelopThings/bdo-data-extractor

The complete 512 × 256 atlas is retained without graphic editing. Flutter
selects the original bare-hands frame at runtime: left 211, top 71, width 34,
height 34 (game UV bounds 211, 71 to 245, 105). The frame's original colors and
circular background are part of the game artwork, not app-generated styling.

Verified native mappings:

- `ui_data/widget/interaction/ui_character_interaction_gathering.xml` defines
  `Button_Hand` using those UV bounds and the label key
  `PANEL_INVENTORY_TOOLBOX_HANDS` (Korean source text: `맨손 채집`).
- `luacscript/x64/widget/interaction/ui_character_interactiongathering_all_1.luac`
  connects that control to the bare-hands interaction. The readable original
  Lua mirror's `PaGlobal_InteractionGathering_All:initializeButton` binds
  `_ui._btn_barehand` to `Button_Hand` and assigns it to
  `_collectTypeUIInfo[__eCollectToolType_BareHands]._icon`:
  https://github.com/bberka/bdo-decompiled-lua/blob/main/widget/interaction/ui_character_interactiongathering_all_1.lua

The app also reuses this manual-gathering hand for milking while retaining
“Milking minigame” interaction wording in tooltips and accessibility. It does
not claim that milking requires an inventory hand tool, or that this frame is
the game's dedicated milking icon. The native milking layout,
`ui_data/widget/minigame/panel_minigame_powercontrol_all.xml`, instead references
milk-bottle/cow graphics and left/right mouse animations.

The open-palm frame at 36, 1 to 70, 35 is deliberately not used: the native
`ui_data/widget/interaction/ui_character_interaction.xml` identifies that
different frame as `Button_Greet`.

Only the artwork is shipped. No extractor executable, game script, game
database, client installation path, or downloaded research repository is
included in a build.
