# EXP sorting — September 17, 2026

Choose **EXP** to sort by experience per successful craft. Its menu includes or hides recipes with unknown EXP; the arrow reverses the order. These choices are saved. EXP is shown only in this sort, with `~` for estimates. Unknown values stay blank.

## Numbers

Values apply to an exact recipe, including its method, inputs, substitutes and output range. Editing a recipe or choosing an unreviewed route does not inherit a value from the item name. EXP is not per output item, per hour, or adjusted for personal buffs. Ingredient EXP is not added to it.

The initial review covered Cooking: 150 sourced values; Alchemy: 79 sourced and 6 estimates; Processing: 145 sourced and 5 estimates. BDO Codex was the main reference, with exact-formula BDOLytics checks for gaps. Unexplained zeroes stayed unknown.

See `recipe_experience.dart` and `tool/generate_recipe_experience.dart` for the records and generation rules.

## Unknown values

Known numbers always come first. Unknown recipes sort by production depth, number of crafted ingredient branches, then name. This compares preparation effort; it does not guess EXP.

`recipe_effort.dart` follows Cooking, Alchemy and Processing definitions, including edits and alternatives. It handles cycles, batches and missing links without treating salvage, archived recipes or batch catalysts as ordinary production. Prices, inventory and mastery do not affect this order. Other active filters still apply.

The approved text sizes were names 20 px, main values 18, labels 14, supporting values 15, controls 16, counts 13 and headings 28.
