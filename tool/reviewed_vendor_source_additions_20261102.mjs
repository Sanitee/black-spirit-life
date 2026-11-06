// Exact PC identities, not a general import of historical native vendor links.
// Crow Coin costs: NA/EU live patch, 2026-05-21, groupContentNo=10081.
// Tea locations: current PC description extracted 2026-11-02, item 9306.
export const additions = [
  ...[
    [5827, 'Moon Scale Plywood', 15],
    [5809, 'Moon Vein Flax Fabric', 40],
    [5810, 'Tide-Dyed Standardized Timber Square', 80],
    [5812, 'Deep Tide-Dyed Standardized Timber Square', 80],
    [8021, 'Wave Residue Adhesive', 300],
    [5821, 'Tear of the Ocean', 400],
  ].map(([id, name, coins]) => ({
    id, name,
    lines: [`Crow Coin Shop · ${coins} coins each`],
    evidence: ['crowCoinShop20260521'],
  })),
  {
    id: 9306,
    name: 'Star Anise Tea',
    lines: ['NPC · General Goods Vendors in Sand Grain Bazaar, Muiquun or Arehaza'],
    evidence: ['novemberVendorDescriptions'],
  },
  ...[
    [757010, 'Mythical Feather', 'patrigioFeather20230719'],
    [820935, 'Primordial Crystal', 'morningLightGathering'],
  ].map(([id, name, evidence]) => ({
    id, name,
    lines: [
      'Patrigio · Random night-shop offer (22:00–07:00 game time)',
      'Secret Shop · 50 Energy per roll; Silver price varies',
    ],
    evidence: [evidence, 'patrigioShopRules', 'novemberNightShopIdentity'],
  })),
];
