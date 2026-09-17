# Opportunities: EXP sorting and unknown effort order

User-approved Beta change, 17 September 2026. This changes the current Beta;
it is not a separate public application, release, installer or updater.

## Presentation

- Compact Demand / Profit / EXP controls, with the active direction shown.
- EXP label selects EXP and opens a beside menu. Its separate arrow reverses
  direction without opening the menu.
- Include unknown (default), Hide unknown and Only unknown are separate rows.
  They affect EXP sorting only; the choice and each sort direction are saved
  in the user's existing Opportunities preferences file.
- Numeric base EXP appears only while sorting by EXP, blue, above Investment.
  Profit remains above Stock. Comparable estimates use a simple `~` prefix.
- Unknown EXP has no label, value, symbol or additional tooltip.
- Approved C typography: recipe names20, primary values18, labels14,
  secondary values15; controls/body16, counts/timestamps13, heading28.

## Numeric reference policy

BDO Codex is primary; exact-formula BDOLytics references fill identified gaps.
The initial audited set has Cooking150 sourced, Alchemy79 sourced +6 comparison
estimates, and Processing145 sourced +5 comparison estimates. These are
reference-product counts, not a promise that every alternate batch has EXP.
Source-reported zeroes without confirmed meaning remain unknown.

`recipe_experience.dart` accepts only positive values tied to an exact formula
signature. Type, method, ingredients, substitutions, item identity and output
bounds are checked. A user-edited formula, different route or unaudited batch
does not inherit a number merely because its product has the same name.
References include both source and clean assembled substitution definitions.
EXP means one successful execution, not EXP per result item, per hour, or after
personal boosts. No recursive sum of ingredient EXP is displayed.

Internal provenance and reproducible generation live with the registry and
`tool/generate_recipe_experience.dart`. The release evidence retains the
external research audit without publishing machine-specific paths.

## Unknown order

Numeric rows always precede unknown rows in either direction. Within unknowns,
the sort key is production-chain depth, then distinct crafted intermediate
branches, then recipe name for stable ties. Descending shows more involved
production first; ascending shows simpler processing first. This is an effort
ordering only, not an assertion that effort determines actual EXP.

`recipe_effort.dart` indexes live definitions across Cooking, Alchemy and
Processing, including user edits. It handles alternatives and normalizes batch
routes; large-batch catalysts alone do not inflate the effort ranking.
Archived/unavailable recipes and manual/salvage conversions cannot create
ordinary production routes. Cycles terminate conservatively. Missing catalog
links do not establish that an ingredient is truly raw.

Profit, market stock, inventory, mastery and saved user choices are not inputs
to the effort score. Existing profitability/availability/search filters still
apply before sorting. Numeric estimates and unknowns remain distinct.

## Preservation and verification

Before editing, the prior accepted typography build and complete source were
SHA-verified and promoted under the existing rollback rulebook. The earlier
Planner baseline remains archived. No personal state was read or reset.
Tests use temporary synthetic profiles and prohibit market network requests.

Implementation evidence, test logs, native UI captures and the local candidate
manifest are retained in the private release evidence. The final validation
manifest records the completed checks and any limitations.
