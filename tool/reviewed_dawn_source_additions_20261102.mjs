// NA/EU PC August 6, 2026, groupContentNo=10422. These are reference hints,
// not new Planner production routes: the starting essence must not be free.
export const additions = [
  [820980, "Essence of Dawn - Black Spirit's Rage"],
  [820981, 'Essence of Dawn - Accuracy'],
  [820982, 'Essence of Dawn - Damage Reduction'],
  [820983, 'Essence of Dawn - Evasion'],
].map(([id, name]) => ({
  id, name,
  lines: [
    "Heating · Eligible enhanced accessories + Dawn's Aura",
    "Simple Alchemy · 1 of this essence + 1 Dark Bonghwang's Tear → 30 (net +29)",
    '10× batch · 10 of each input + 1 Black Stone Powder → 300 (net +290)',
  ],
  evidence: ['dawnMultiplication20260806', 'novemberDawnDescriptions'],
}));
