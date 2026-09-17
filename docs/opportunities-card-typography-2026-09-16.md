# Opportunities card typography

Approved on 2026-09-16: use preview A's balanced supporting text, with the
user's correction that profit must not be larger than the recipe name.

- Item/recipe names: 18 px, bold (700).
- Primary profit/value: 18 px, semibold (600), never larger than the name.
- Metric and context labels: 13 px.
- Stock, investment, and other supporting values: 14 px.
- Preserve the current card width, icons, spacing, colours, responsive layout,
  user text scaling, actions, calculations, and saved data.
- Apply the same hierarchy to Crafting, Best Use, and Exchanges overview cards.
- Remove the passive “Main item only” label. Keep the existing Crafting profit
  information button and full explanation unchanged.

Card sizes are centralized in `OpportunitiesVisualSpec`; shared dialog and
toolbar typography remains unchanged. Planner suggestions and installer-path
changes are separate requests and are not included in this visual-only change.
