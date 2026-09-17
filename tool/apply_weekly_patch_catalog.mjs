import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyTwilightPatch } from './apply_twilight_patch_20260917.mjs';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const catalogPath = path.join(projectRoot, 'assets', 'data', 'app-data.json');
const checkOnly = process.argv.includes('--check');
const clientDataArgument = process.argv.indexOf('--client-data-root');
const clientDataRoot =
  clientDataArgument >= 0 ? process.argv[clientDataArgument + 1] : null;

if (clientDataArgument >= 0 && !clientDataRoot) {
  throw new Error('--client-data-root requires a directory path.');
}

const reviewedAt = '2026-08-28';
const currentReviewDate = '2026-09-03';
const sources = {
  july23:
    'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10342',
  july30:
    'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10401',
  august6:
    'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10422',
  august13:
    'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10451',
  august20:
    'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10478',
  august27:
    'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19749',
  september3:
    'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10550&countryType=en-US',
};

// name, id, weight, mode, marketable, client icon path, SHA-256
const itemRecords = [
  ['Great Ocean Oil', 9727, 0.1, 'alchemy', true, 'icons/new_icon/03_etc/07_productmaterial/00009727.webp', 'f80aa662d7d7f6c31086d4943d7c7b2bdeaf26380e53009276456567fa3c6762'],
  ['Destruction Spirit Stone', 45298, 0.05, 'processing', true, 'icons/new_icon/03_etc/07_productmaterial/00045298.webp', '4d2b04ae0254baec421e0530ab816c71e1fd88bae886f09776eb8d17a6e3cafc'],
  ['Guardian Spirit Stone', 45300, 0.05, 'processing', true, 'icons/new_icon/03_etc/07_productmaterial/00045300.webp', '424342a5f6c48cc4a5f082c89ea0e1bda91ded40a52a21dd3f749f9802b0cc03'],
  ['Life Spirit Stone', 45302, 0.05, 'processing', true, 'icons/new_icon/03_etc/07_productmaterial/00045302.webp', 'd6f972d763f0d1f860e40c9ab521a07837580e6e1718b7a23cd6b3b2b602540e'],
  ['Oquilla Wave Meal', 9649, 0.1, 'processing', true, 'icons/new_icon/03_etc/07_productmaterial/00009649.webp', '41fe8671277f41724018ef0799461056563b8e259d3ae71f8b6e5698d547ac47'],
  ['Crystal Extraction Tool', 16000, 0.1, 'processing', false, 'icons/new_icon/03_etc/11_enchant_material/00016000.webp', 'ba02fba431a707106dbcbb9a594abf99256c6c30d8d1a31fffaaf1a279f67f78'],
  ['Cron Stone', 16080, 0.0001, 'processing', false, 'icons/new_icon/03_etc/00016080.webp', '03f99067a8489f2ada058e425c243fb528e7293682eb4e7bff3c1bb848a56767'],
  ['Pure Forest Breath', 50807, 0.1, 'processing', true, 'icons/new_icon/03_etc/09_petitem/00050807.webp', '1ce10e95802124d670adc194e580d74e68582d1916ce2a25e43be717538814ae'],
  ['Starlight Hardener', 8023, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/00008023.webp', '905fcaba389252cc660818c51e6a9765467c52a279e33c3e6a748d5804030ea5'],
  ['Starlight Emulsifier', 8024, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/00008024.webp', 'e160515289f81acfa4efc535d30cb64a7da12866acc75c7ee28d135de465b299'],
  ['Sunset Tidal Black Stone', 756007, 0.01, 'processing', true, 'icons/new_icon/03_etc/00756004.webp', '4cacb6ca011540e247f88e151529b256954a5a729143f18c02b4f8428fe9cbd0'],
  ['Primordial Hammer', 767130, 0.0001, 'processing', false, 'icons/new_icon/03_etc/00767130.webp', '899d0eb9155c12d212d186db99546a14069b51f03a1d7a1bd6b29f5811d69777'],
  ['Ancient Hammer', 767131, 0.0001, 'processing', false, 'icons/new_icon/03_etc/00767131.webp', '4cb743b8f2e06d991cc901383341670fe08db7fbeaa07d669721f068e72fabdc'],
  ['Obsidian Hammer', 767291, 0.0001, 'processing', false, 'icons/new_icon/03_etc/00767291.webp', '7a3ce2e5272543e6ab205661441d2d9e6a3c5c2628bb34b9228b3b1e1a5b446e'],
  ['Ancient Hammer - PEN (V)', 790871, 0.0001, 'processing', false, 'icons/new_icon/03_etc/00790871.webp', '96331ad89c32869a01077e1f7cf7cbe2d725776ef42b5d38bccc9a5e434fedfa'],
  ['Ancient Hammer - HEX (VI)', 790872, 0.0001, 'processing', false, 'icons/new_icon/03_etc/00790872.webp', '5d8106b1ca8f9533ba3bec24045700931109c6dd2610b3fd5eec3d744b8c80cf'],
  ['Ancient Black Stone - PEN (V)', 790873, 0.1, 'processing', false, 'icons/new_icon/03_etc/00790873.webp', '7fc9c27665a1f800ef48f932b5a0eb1d860db13819a003533895fe75cf801540'],
  ['Ancient Black Stone - HEX (VI)', 790874, 0.1, 'processing', false, 'icons/new_icon/03_etc/00790874.webp', '5df22f14e54184031b707a7517d46ed455c8f3afd75a7e8a028401deef4a133c'],
  ['Ancient Black Stone - SEP (VII)', 790875, 0.1, 'processing', false, 'icons/new_icon/03_etc/00790875.webp', 'f5cbdea73ee68b7e4ab67d4cfd60d9b4f5319938c07c682d0b24861ec5a3a5c1'],
  ["Lyngbakr's Bone", 821362, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821362.webp', 'a6636becc30c88bc295e071fa5e946eea0e41a3021a503b2e7da7fcfeadd5b7b'],
  ["Lyngbakr's Scale", 821363, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821363.webp', 'bab03b5c7f11a3c2a1ba3249fc1cb76943de3eb001b8345f25a659873debd25b'],
  ["Lyngbakr's Fluid", 821364, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821364.webp', '0a9e225b5ddfebdca900cda5c5cd54a4ba4375e2c83358324978eb7039aa35aa'],
  ['Sturdy Coral Support', 821365, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821365.webp', 'bc6a245fe2b611b986a95a8b4e0c24a043c50b6f2df5f43eb45e3fa3dbaf8088'],
  ['Raging Wave Plywood', 821366, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821366.webp', '874042cd1c1c3e39aed2c091c076ad7cb0b4000608f7aa0613795da0be4ecb82'],
  ['Dormant Crimson Coral Adhesive', 821367, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821367.webp', '767acdef8801ee0085f1cae65d52be5351d7f91cbb61e98b3aa6278ea16e908b'],
  ['Sunset Coral Essence', 821369, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821368.webp', '4cbdb121ae1512d1e8722e7212461574725a56f0d79af647e924a98c1edd1495'],
  ['Concentrated Spellbound Catalyst', 821372, 0.1, 'processing', false, 'icons/new_icon/03_etc/07_productmaterial/000821372.webp', '291cc8a9477762aaa5c81e01930c4aa9d3690447c6b44e693f360b89e6baf5fb'],
  ['Ocean Essence', 821467, 0.1, 'processing', false, 'icons/new_icon/03_etc/00890075.webp', '8ac44f53a5e0f4eefd9a4cee6dbbcca7f15586df4d4fe4d51e5dd951721f9271'],
  ['Red Sea Monster Meat', 821468, 0.1, 'processing', true, 'icons/new_icon/03_etc/07_productmaterial/00821468.webp', '111cafe0e0e4f98ed4d1f306e95199b4bf7ae7723bf3a8a3ad0f9f210e3889f0'],
  ["Dark Bonghwang's Tear", 890011, 0.3, 'processing', false, 'icons/new_icon/03_etc/00890011.webp', '5ed070e58cd46d20253be417a0f62352051a107c2691d9587c1f78c27728ebe7'],
  ['Ocean Draught', 890072, 0.2, 'alchemy', true, 'icons/new_icon/03_etc/08_potion/00890072.webp', '5234981163870245f9debb17e32b06661fae486b78f3df11082be6be07b2fc72'],
  ['Vast Ocean Draught', 890073, 0.2, 'alchemy', true, 'icons/new_icon/03_etc/08_potion/00890073.webp', '81ea62ce59d212ec241e327244b20323faaf307a65e172d493e2c9aa6ea8820c'],
  ['Endless Ocean Draught', 890074, 0.2, 'alchemy', true, 'icons/new_icon/03_etc/08_potion/00890074.webp', '343402a259ca4463f40d8fbd38673fd8685d5989aa40eb2a1c09ac2ce2ae889f'],
  ["Labreska's Helmet (Bound)", 930901, 17, 'processing', false, 'icons/new_icon/06_pc_equipitem/00_common/13_hel/00719897.webp', 'c9de659cc12acd75ba068d58520ce3c7559356f22dcf5a769e6f7fc173b3a01a'],
  ["Fallen God's Armor (Bound)", 930902, 23, 'processing', false, 'icons/new_icon/06_pc_equipitem/00_common/09_upperbody/00719898.webp', '659799fb9c1563cf66101db5d64241f952e171c093fb2b4e3fdff1ea288be3d3'],
  ["Dahn's Gloves (Bound)", 930903, 12, 'processing', false, 'icons/new_icon/06_pc_equipitem/00_common/11_hand/00719899.webp', 'fbcd2c96651aec7df6e7e31b0ce940f871725c097b2e716c26289b6069b1593e'],
  ["Ator's Shoes (Bound)", 930904, 13, 'processing', false, 'icons/new_icon/06_pc_equipitem/00_common/12_foot/00719900.webp', '634d829f107767218624871168a5427c9920bf328bb94d9be39e73d42493bed3'],
];

const ingredient = (name, qty, extra = {}) => ({ name, qty, ...extra });

const procVariant = ({
  id,
  label,
  routeId,
  batchMultiplier,
  ingredients,
  outputMin,
  outputMax = outputMin,
  method,
}) => ({
  id,
  label,
  routeId,
  batchMultiplier,
  ...(method == null ? {} : { method }),
  baseOutput: (outputMin + outputMax) / 5,
  outputMin,
  outputMax,
  ingredients,
});

const fixedProc = ({
  method,
  ingredients,
  outputMin = 1,
  outputMax = outputMin,
  marketId,
  variants,
  defaultVariantId,
  group,
  recipeRole,
  npcPrice,
}) => ({
  type: 'processing',
  baseOutput: (outputMin + outputMax) / 5,
  group: group ?? 'Processing - ' + method,
  method,
  ...(marketId == null ? {} : { marketId: String(marketId) }),
  outputMin,
  outputMax,
  ingredients,
  ...(defaultVariantId == null ? {} : { defaultVariantId }),
  ...(variants == null ? {} : { variants }),
  ...(recipeRole == null ? {} : { recipeRole }),
  ...(npcPrice == null ? {} : { npcPrice }),
});

const substitute = (normal, improved, qty, owner) =>
  ingredient(normal, qty, {
    options: [normal, improved],
    substituteGroup: owner + ':' + normal,
    substituteRatios: { [normal]: 1, [improved]: 1 / 3 },
  });

const draughtPairs = {
  'Fury Draught': [
    ['Elixir of Frenzy', 'Elixir of Endless Frenzy'],
    ['Elixir of Concentration', 'Elixir of Advanced Concentration'],
    ['Elixir of Fury', 'Elixir of Endless Fury'],
    ['Elixir of Destruction', 'Elixir of Lethal Destruction'],
  ],
  'Adaptation Draught': [
    ['Elixir of Life', 'Elixir of Strong Life'],
    ['Defense Elixir', 'Elixir of Steel Defense'],
    ['Elixir of Endurance', 'Elixir of Overwhelming Endurance'],
    ['Helix Elixir', 'Splendid Helix Elixir'],
  ],
  'Potential Draught': [
    ['Elixir of Wind', 'Elixir of Flowing Wind'],
    ['Elixir of Swiftness', 'Elixir of Intrepid Swiftness'],
    ['Elixir of Spells', 'Elixir of Agile Spells'],
    ['Elixir of Shock', 'Elixir of Strong Shock'],
  ],
  'Corruption Draught': [
    ['Elixir of Draining', 'Elixir of Strong Draining'],
    ['Elixir of Perforation', 'Elixir of Brutal Perforation'],
    ['Elixir of Death', 'Brutal Death Elixir'],
    ["Grim Reaper's Elixir", "Grim Soul Reaper's Elixir"],
  ],
  'Berserk Draught': [
    ['Elixir of Assassination', 'Elixir of Lethal Assassin'],
    ['Elixir of Detection', 'Elixir of Sharp Detection'],
    ['Elixir of Carnage', 'Elixir of Brutal Carnage'],
    ['Elixir of Sky', 'Merciless Sky Elixir'],
  ],
};

const draughtRecipe = (name, pairs) => {
  const standard = [
    ...pairs.map(([normal, improved]) =>
      substitute(normal, improved, 30, name),
    ),
    ingredient('Spellbound Catalyst', 10),
  ];
  const mass = [
    ...pairs.map(([normal, improved]) =>
      substitute(normal, improved, 300, name + ' mass'),
    ),
    ingredient('Concentrated Spellbound Catalyst', 10),
  ];
  return {
    type: 'simple_alchemy',
    baseOutput: 10,
    group: 'Draughts',
    method: 'Simple Alchemy',
    outputMin: 10,
    outputMax: 10,
    ingredients: standard,
    defaultVariantId: 'simple-alchemy-10x',
    variants: [
      {
        id: 'simple-alchemy-10x',
        label: 'Simple Alchemy',
        routeId: 'simple-alchemy',
        batchMultiplier: 10,
        baseOutput: 10,
        outputMin: 10,
        outputMax: 10,
        ingredients: standard,
      },
      {
        id: 'simple-alchemy-100x',
        label: 'Simple Alchemy',
        routeId: 'simple-alchemy',
        batchMultiplier: 100,
        baseOutput: 100,
        outputMin: 100,
        outputMax: 100,
        ingredients: mass,
      },
    ],
  };
};

const processingDraughtRecipe = (name, pairs) => {
  const recipe = draughtRecipe(name, pairs);
  const marketIds = {
    'Fury Draught': 1389,
    'Adaptation Draught': 1391,
    'Potential Draught': 1393,
    'Corruption Draught': 1395,
    'Berserk Draught': 1397,
  };
  return fixedProc({
    method: 'Simple Alchemy',
    marketId: marketIds[name],
    ingredients: recipe.ingredients,
    outputMin: 10,
    defaultVariantId: recipe.defaultVariantId,
    variants: recipe.variants.map((variant) => ({
      ...variant,
      baseOutput: variant.outputMin / 2.5,
    })),
  });
};

const harmonyRecipe = (name, huntName, improvedHuntName) => {
  const standard = [
    substitute(huntName, improvedHuntName, 30, name),
    substitute(
      'Elixir of Will',
      'Elixir of Remarkable Will',
      30,
      name,
    ),
    ingredient('Harmony Draught', 10),
    ingredient('Concentrated Spellbound Catalyst', 1),
  ];
  const mass = [
    substitute(huntName, improvedHuntName, 300, name + ' mass'),
    substitute(
      'Elixir of Will',
      'Elixir of Remarkable Will',
      300,
      name + ' mass',
    ),
    ingredient('Harmony Draught', 100),
    ingredient("Ibellab's Essence", 1),
    ingredient('Concentrated Spellbound Catalyst', 10),
  ];
  return {
    type: 'simple_alchemy',
    baseOutput: 10,
    group: 'Draughts',
    method: 'Simple Alchemy',
    outputMin: 10,
    outputMax: 10,
    ingredients: standard,
    defaultVariantId: 'simple-alchemy-10x',
    variants: [
      {
        id: 'simple-alchemy-10x',
        label: 'Simple Alchemy',
        routeId: 'simple-alchemy',
        batchMultiplier: 10,
        baseOutput: 10,
        outputMin: 10,
        outputMax: 10,
        ingredients: standard,
      },
      {
        id: 'simple-alchemy-100x',
        label: 'Simple Alchemy',
        routeId: 'simple-alchemy',
        batchMultiplier: 100,
        baseOutput: 100,
        outputMin: 100,
        outputMax: 100,
        ingredients: mass,
      },
    ],
  };
};

const oceanIngredients = (multiplier, owner) => [
  substitute(
    'Elixir of Mastery',
    'Elixir of Improved Mastery',
    36 * multiplier,
    owner,
  ),
  substitute(
    'Elixir of Time',
    'Elixir of Flowing Time',
    36 * multiplier,
    owner,
  ),
  substitute(
    'Elixir of Amity',
    'Improved Elixir of Amity',
    36 * multiplier,
    owner,
  ),
  ingredient('Tears of the Falling Moon', 10 * multiplier),
];

const alchemyRecipes = Object.fromEntries(
  Object.entries(draughtPairs).map(([name, pairs]) => [
    name,
    draughtRecipe(name, pairs),
  ]),
);

alchemyRecipes['Harmony Draught - Human'] = harmonyRecipe(
  'Harmony Draught - Human',
  'Elixir of Human Hunt',
  'Elixir of Perfect Human Hunt',
);
alchemyRecipes['Harmony Draught - Demihuman'] = harmonyRecipe(
  'Harmony Draught - Demihuman',
  'Elixir of Demihuman Hunt',
  'Elixir of Fierce Demihuman Hunt',
);
alchemyRecipes['Harmony Draught - Kamasylvia'] = harmonyRecipe(
  'Harmony Draught - Kamasylvia',
  "Griffon's Elixir",
  "Strong Griffon's Elixir",
);
alchemyRecipes['Harmony Draught - Edania'] = harmonyRecipe(
  'Harmony Draught - Edania',
  'Elixir of Edania',
  'Strong Elixir of Edania',
);

alchemyRecipes['Ocean Draught'] = {
  type: 'simple_alchemy',
  baseOutput: 1,
  group: 'Draughts',
  method: 'Simple Alchemy',
  marketId: '890072',
  outputMin: 1,
  outputMax: 1,
  ingredients: oceanIngredients(1, 'Ocean Draught'),
  defaultVariantId: 'simple-alchemy-1x',
  variants: [
    {
      id: 'simple-alchemy-1x',
      label: 'Simple Alchemy',
      routeId: 'simple-alchemy',
      batchMultiplier: 1,
      baseOutput: 1,
      outputMin: 1,
      outputMax: 1,
      ingredients: oceanIngredients(1, 'Ocean Draught'),
    },
    {
      id: 'simple-alchemy-10x',
      label: 'Simple Alchemy',
      routeId: 'simple-alchemy',
      batchMultiplier: 10,
      baseOutput: 10,
      outputMin: 10,
      outputMax: 10,
      ingredients: [
        ...oceanIngredients(10, 'Ocean Draught mass'),
        ingredient("Ibellab's Essence", 1),
      ],
    },
  ],
};
alchemyRecipes['Vast Ocean Draught'] = {
  type: 'simple_alchemy',
  baseOutput: 1,
  group: 'Draughts',
  method: 'Simple Alchemy',
  marketId: '890073',
  outputMin: 1,
  outputMax: 1,
  ingredients: [
    ...oceanIngredients(2, 'Vast Ocean Draught'),
    ingredient('Swaying Wind Shard', 1),
  ],
};
alchemyRecipes['Endless Ocean Draught'] = {
  type: 'simple_alchemy',
  baseOutput: 1,
  group: 'Draughts',
  method: 'Simple Alchemy',
  marketId: '890074',
  outputMin: 1,
  outputMax: 1,
  ingredients: [
    ingredient('Ocean Draught', 4),
    ingredient('Ocean Essence', 1),
  ],
  defaultVariantId: 'ocean-draught',
  variants: [
    {
      id: 'ocean-draught',
      label: 'Ocean Draught',
      routeId: 'ocean-draught',
      batchMultiplier: 1,
      baseOutput: 1,
      outputMin: 1,
      outputMax: 1,
      ingredients: [
        ingredient('Ocean Draught', 4),
        ingredient('Ocean Essence', 1),
      ],
    },
    {
      id: 'vast-ocean-draught',
      label: 'Vast Ocean Draught',
      routeId: 'vast-ocean-draught',
      batchMultiplier: 1,
      baseOutput: 1,
      outputMin: 1,
      outputMax: 1,
      ingredients: [
        ingredient('Vast Ocean Draught', 2),
        ingredient('Ocean Essence', 1),
      ],
    },
  ],
};

const forestPairs = [
  ['Wind Spirit Stone Fragment', 'Earth Spirit Stone Fragment'],
  ['Wind Spirit Stone Fragment', 'Water Spirit Stone Fragment'],
  ['Wind Spirit Stone Fragment', 'Tree Spirit Stone Fragment'],
  ['Earth Spirit Stone Fragment', 'Water Spirit Stone Fragment'],
  ['Earth Spirit Stone Fragment', 'Tree Spirit Stone Fragment'],
  ['Water Spirit Stone Fragment', 'Tree Spirit Stone Fragment'],
];
const forestVariants = forestPairs.flatMap(([left, right]) => {
  const routeId =
    left.split(' ')[0].toLowerCase() + '-' + right.split(' ')[0].toLowerCase();
  const label = left.split(' ')[0] + ' + ' + right.split(' ')[0];
  return [
    procVariant({
      id: routeId + '-1x',
      label,
      routeId,
      batchMultiplier: 1,
      ingredients: [ingredient(left, 10), ingredient(right, 10)],
      outputMin: 1,
      outputMax: 3,
    }),
    procVariant({
      id: routeId + '-10x',
      label,
      routeId,
      batchMultiplier: 10,
      ingredients: [
        ingredient(left, 100),
        ingredient(right, 100),
        ingredient('Black Stone Powder', 1),
      ],
      outputMin: 10,
      outputMax: 30,
    }),
  ];
});

const cronConversions = [
  ['Primordial Hammer', 1000],
  ['Ancient Hammer', 1000],
  ['Obsidian Hammer', 200],
  ['Ancient Hammer - PEN (V)', 200],
  ['Ancient Hammer - HEX (VI)', 300],
  ['Ancient Black Stone - PEN (V)', 1000],
  ['Ancient Black Stone - HEX (VI)', 1500],
  ['Ancient Black Stone - SEP (VII)', 2000],
  ["Labreska's Helmet (Bound)", 1500],
  ["Fallen God's Armor (Bound)", 1500],
  ["Dahn's Gloves (Bound)", 1500],
  ["Ator's Shoes (Bound)", 1500],
];

const essenceRoutes = [
  ["Essence of Dawn - Black Spirit's Rage", 820980, 16, 40, [ingredient("Dawn's Aura", 1)]],
  ['Essence of Dawn - Accuracy', 820981, 10, 25, [ingredient("Dawn's Aura", 1)]],
  [
    'Essence of Dawn - Damage Reduction',
    820982,
    100,
    250,
    [
      ingredient('JIN Dawn Crystal - Damage Reduction', 1, {
        options: ['JIN Dawn Crystal - Damage Reduction', "Dawn's Aura"],
        substituteGroup: 'Essence of Dawn - Damage Reduction:processing:1',
        substituteRatios: {
          'JIN Dawn Crystal - Damage Reduction': 1,
          "Dawn's Aura": 1,
        },
      }),
    ],
  ],
  ['Essence of Dawn - Evasion', 820983, 16.8, 42, [ingredient("Dawn's Aura", 1)]],
];

const essenceRecipe = (name, marketId, baseOutput, output, heatingIngredients) => ({
  type: 'processing',
  baseOutput,
  group: 'Processing - Multiple Methods',
  method: 'Heating',
  marketId: String(marketId),
  sourceNote:
    'Current Heating route plus Dark Bonghwang Simple Alchemy routes added Aug 6, 2026.',
  outputMin: output,
  outputMax: output,
  ingredients: heatingIngredients,
  recipeRole: 'manual_conversion',
  defaultVariantId: 'heating-current',
  variants: [
    {
      id: 'heating-current',
      label: 'Heating',
      routeId: 'heating',
      batchMultiplier: 1,
      baseOutput,
      outputMin: output,
      outputMax: output,
      ingredients: heatingIngredients,
    },
    procVariant({
      id: 'dark-bonghwang-1x',
      label: 'Dark Bonghwang',
      routeId: 'dark-bonghwang',
      batchMultiplier: 1,
      method: 'Simple Alchemy',
      ingredients: [
        ingredient(name, 1),
        ingredient("Dark Bonghwang's Tear", 1),
      ],
      outputMin: 30,
    }),
    procVariant({
      id: 'dark-bonghwang-10x',
      label: 'Dark Bonghwang',
      routeId: 'dark-bonghwang',
      batchMultiplier: 10,
      method: 'Simple Alchemy',
      ingredients: [
        ingredient(name, 10),
        ingredient("Dark Bonghwang's Tear", 10),
        ingredient('Black Stone Powder', 1),
      ],
      outputMin: 300,
    }),
  ],
});

const oquillaIngredients = [
  ingredient('Margoria Seafood Meal', 3),
  substitute('Teff Bread', 'Spongy Teff Bread', 3, 'Oquilla Wave Meal'),
  substitute(
    'Whale Meat Salad',
    'Fresh Whale Meat Salad',
    3,
    'Oquilla Wave Meal',
  ),
  ingredient('Red Sea Monster Meat', 1),
];

const massRecipe = (method, material, output) => {
  const standard = [
    ingredient(material, 1),
    ingredient('Starlight Hardener', 1),
    ingredient('Starlight Emulsifier', 1),
  ];
  const mass = [
    ingredient(material, 10),
    ingredient('Starlight Hardener', 10),
    ingredient('Starlight Emulsifier', 10),
    ingredient('Black Stone Powder', 1),
  ];
  return fixedProc({
    method,
    ingredients: standard,
    defaultVariantId: 'standard-1x',
    variants: [
      procVariant({
        id: 'standard-1x',
        label: method,
        routeId: method.toLowerCase().replaceAll(' ', '-'),
        batchMultiplier: 1,
        ingredients: standard,
        outputMin: 1,
      }),
      procVariant({
        id: 'standard-10x',
        label: method,
        routeId: method.toLowerCase().replaceAll(' ', '-'),
        batchMultiplier: 10,
        ingredients: mass,
        outputMin: 10,
      }),
    ],
  });
};

const processingRecipes = Object.fromEntries(
  Object.entries(draughtPairs).map(([name, pairs]) => [
    name,
    processingDraughtRecipe(name, pairs),
  ]),
);

processingRecipes['Crystal Extraction Tool'] = fixedProc({
  method: 'Simple Alchemy',
  ingredients: [
    ingredient('Magical Shard', 10),
    ingredient('Pure Iron Crystal', 100),
  ],
  defaultVariantId: 'simple-alchemy-1x',
  variants: [
    procVariant({
      id: 'simple-alchemy-1x',
      label: 'Simple Alchemy',
      routeId: 'simple-alchemy',
      batchMultiplier: 1,
      ingredients: [
        ingredient('Magical Shard', 10),
        ingredient('Pure Iron Crystal', 100),
      ],
      outputMin: 1,
    }),
    procVariant({
      id: 'simple-alchemy-10x',
      label: 'Simple Alchemy',
      routeId: 'simple-alchemy',
      batchMultiplier: 10,
      ingredients: [
        ingredient('Magical Shard', 100),
        ingredient('Pure Iron Crystal', 1000),
        ingredient('Black Stone Powder', 1),
      ],
      outputMin: 10,
    }),
  ],
});
processingRecipes['Pure Forest Breath'] = fixedProc({
  method: 'Simple Alchemy',
  marketId: 50807,
  ingredients: [
    ingredient('Wind Spirit Stone Fragment', 10),
    ingredient('Earth Spirit Stone Fragment', 10),
  ],
  outputMin: 1,
  outputMax: 3,
  defaultVariantId: 'wind-earth-1x',
  variants: forestVariants,
});
processingRecipes['Cron Stone'] = fixedProc({
  method: 'Heating',
  ingredients: [ingredient('Primordial Hammer', 1)],
  outputMin: 1000,
  npcPrice: 3000000,
  defaultVariantId: 'primordial-hammer',
  variants: cronConversions.map(([input, output]) =>
    procVariant({
      id: input.toLowerCase().replaceAll(/[^a-z0-9]+/g, '-'),
      label: input,
      routeId: input.toLowerCase().replaceAll(/[^a-z0-9]+/g, '-'),
      batchMultiplier: 1,
      ingredients: [ingredient(input, 1)],
      outputMin: output,
    }),
  ),
});
for (const entry of essenceRoutes) {
  processingRecipes[entry[0]] = essenceRecipe(...entry);
}
for (const [index, slot] of ['Necklace', 'Earring', 'Ring', 'Belt'].entries()) {
  processingRecipes['Twilight of the End - ' + slot] = fixedProc({
    method: 'Heating',
    marketId: 821421 + index,
    ingredients: [ingredient('Apeiron ' + slot, 1)],
    outputMin: 10,
    group: 'Reference - Destructive Conversion',
    recipeRole: 'manual_conversion',
  });
}
processingRecipes['Oquilla Wave Meal'] = fixedProc({
  method: 'Simple Cooking',
  marketId: 9649,
  ingredients: oquillaIngredients,
  defaultVariantId: 'simple-cooking-1x',
  variants: [
    procVariant({
      id: 'simple-cooking-1x',
      label: 'Simple Cooking',
      routeId: 'simple-cooking',
      batchMultiplier: 1,
      ingredients: oquillaIngredients,
      outputMin: 1,
    }),
    procVariant({
      id: 'simple-cooking-10x',
      label: 'Simple Cooking',
      routeId: 'simple-cooking',
      batchMultiplier: 10,
      ingredients: [
        ingredient('Margoria Seafood Meal', 30),
        substitute(
          'Teff Bread',
          'Spongy Teff Bread',
          30,
          'Oquilla Wave Meal mass',
        ),
        substitute(
          'Whale Meat Salad',
          'Fresh Whale Meat Salad',
          30,
          'Oquilla Wave Meal mass',
        ),
        ingredient('Red Sea Monster Meat', 10),
        ingredient("Nadia Rowen's Special Sauce", 1),
      ],
      outputMin: 10,
    }),
  ],
});
processingRecipes['Sturdy Coral Support'] = massRecipe(
  'Manufacture',
  "Lyngbakr's Bone",
  'supports',
);
processingRecipes['Raging Wave Plywood'] = massRecipe(
  'Manufacture',
  "Lyngbakr's Scale",
  'plywood',
);
processingRecipes['Dormant Crimson Coral Adhesive'] = massRecipe(
  'Simple Alchemy',
  "Lyngbakr's Fluid",
  'adhesive',
);
processingRecipes['Sunset Tidal Black Stone'] = fixedProc({
  method: 'Heating',
  marketId: 756007,
  ingredients: [
    ingredient('Tidal Black Stone', 100),
    ingredient('Sunset Coral Essence', 1),
  ],
  defaultVariantId: 'heating-1x',
  variants: [
    procVariant({
      id: 'heating-1x',
      label: 'Heating',
      routeId: 'heating',
      batchMultiplier: 1,
      ingredients: [
        ingredient('Tidal Black Stone', 100),
        ingredient('Sunset Coral Essence', 1),
      ],
      outputMin: 1,
    }),
    procVariant({
      id: 'heating-10x',
      label: 'Heating',
      routeId: 'heating',
      batchMultiplier: 10,
      ingredients: [
        ingredient('Tidal Black Stone', 1000),
        ingredient('Sunset Coral Essence', 10),
        ingredient('Black Stone Powder', 1),
      ],
      outputMin: 10,
    }),
  ],
});
processingRecipes['Concentrated Spellbound Catalyst'] = fixedProc({
  method: 'NPC Exchange',
  ingredients: [ingredient('Spellbound Catalyst', 10)],
  group: 'Reference - NPC Exchange',
  recipeRole: 'manual_conversion',
  npcPrice: 10000000,
});

const referenceNames = [
  'Primordial Hammer',
  'Ancient Hammer',
  'Obsidian Hammer',
  'Ancient Hammer - PEN (V)',
  'Ancient Hammer - HEX (VI)',
  'Ancient Black Stone - PEN (V)',
  'Ancient Black Stone - HEX (VI)',
  'Ancient Black Stone - SEP (VII)',
  "Labreska's Helmet (Bound)",
  "Fallen God's Armor (Bound)",
  "Dahn's Gloves (Bound)",
  "Ator's Shoes (Bound)",
  "Dark Bonghwang's Tear",
  'Starlight Hardener',
  'Starlight Emulsifier',
  "Lyngbakr's Bone",
  "Lyngbakr's Scale",
  "Lyngbakr's Fluid",
  'Sunset Coral Essence',
  'Ocean Essence',
  'Red Sea Monster Meat',
];

const sourceText = await readFile(catalogPath, 'utf8');
const catalog = JSON.parse(sourceText);

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const iconBytes = (dataUri) => {
  if (typeof dataUri !== 'string' || !dataUri.startsWith('data:image/')) {
    return null;
  }
  const comma = dataUri.indexOf(',');
  return comma < 0 ? null : Buffer.from(dataUri.slice(comma + 1), 'base64');
};

const renameMapEntry = (values, oldName, newName) => {
  if (values == null || typeof values !== 'object' || Array.isArray(values)) {
    return;
  }
  if (Object.hasOwn(values, oldName)) {
    if (Object.hasOwn(values, newName)) {
      throw new Error(
        `Cannot rename ${oldName}: the catalog already contains ${newName}.`,
      );
    }
    values[newName] = values[oldName];
    delete values[oldName];
  }
};

const renameIngredient = (entry, oldName, newName) => {
  if (entry == null || typeof entry !== 'object' || Array.isArray(entry)) {
    return;
  }
  if (entry.name === oldName) entry.name = newName;
  if (Array.isArray(entry.options)) {
    entry.options = entry.options.map((name) =>
      name === oldName ? newName : name,
    );
  }
  if (entry.substituteRatios != null) {
    renameMapEntry(entry.substituteRatios, oldName, newName);
  }
};

const renameRecipeIngredientReferences = (oldName, newName) => {
  for (const items of [
    catalog.items,
    catalog.cooking.items,
    catalog.processing.items,
  ]) {
    for (const recipe of Object.values(items)) {
      for (const entry of recipe.ingredients ?? []) {
        renameIngredient(entry, oldName, newName);
      }
      for (const variant of recipe.variants ?? []) {
        for (const entry of variant.ingredients ?? []) {
          renameIngredient(entry, oldName, newName);
        }
      }
    }
  }
};

const exactProcessingRecipe = ({ingredients, ...fields}) => ({
  type: 'processing',
  ...fields,
  ingredients,
});

const recipeIngredientNames = (recipe) => [
  ...(recipe.ingredients ?? []).map((entry) => entry.name),
  ...(recipe.variants ?? []).flatMap((variant) =>
    (variant.ingredients ?? []).map((entry) => entry.name),
  ),
];

for (const [name, id, weight, mode, marketable, iconPath, expectedHash] of itemRecords) {
  const iconMap =
    mode === 'alchemy' ? catalog.itemIcons : catalog.processing.itemIcons;
  const existingBytes = iconBytes(iconMap[name]);
  const existingMatches =
    existingBytes != null && sha256(existingBytes) === expectedHash;
  if (!existingMatches) {
    if (clientDataRoot == null) {
      throw new Error(
        'Missing or stale embedded icon for ' +
          name +
          '. Seed once with --client-data-root <current extracted client data>.',
      );
    }
    const bytes = await readFile(path.join(clientDataRoot, iconPath));
    const actualHash = sha256(bytes);
    if (actualHash !== expectedHash) {
      throw new Error(
        'Client icon hash mismatch for ' + name + ': ' + actualHash,
      );
    }
    iconMap[name] = 'data:image/webp;base64,' + bytes.toString('base64');
  }

  catalog.itemWeightIds[name] = String(id);
  catalog.itemWeightsLtById[String(id)] = weight;
  if (marketable) {
    catalog.marketIds[name] = String(id);
    catalog.marketNameIds[name.toLowerCase()] = String(id);
  }
}

for (const [name, recipe] of Object.entries(alchemyRecipes)) {
  catalog.items[name] = recipe;
}
for (const [name, recipe] of Object.entries(processingRecipes)) {
  catalog.processing.items[name] = recipe;
}

for (const name of referenceNames) {
  catalog.processing.items[name] = fixedProc({
    method: 'Base item',
    ingredients: [],
    group: 'Reference - Patch Items',
    recipeRole: 'manual_conversion',
  });
}

catalog.processing.items['Primordial Hammer'].sourceNote =
  'Limited-event reward from hammer selection boxes. If you already own one, Heating converts it into Cron Stone x1,000.';
catalog.cooking.items['Fresh Whale Meat Salad'].sourceNote =
  'Slight chance while cooking Whale Meat Salad at Cooking Professional 1 or higher.';
catalog.cooking.items['Spongy Teff Bread'].sourceNote =
  'Slight chance while cooking Teff Bread at Cooking Skilled 5 or higher.';

for (const [name, id, weight] of [
  ['Fresh Whale Meat Salad', 9458, 0.1],
  ['Spongy Teff Bread', 9299, 0.1],
]) {
  catalog.itemWeightIds[name] = String(id);
  catalog.itemWeightsLtById[String(id)] = weight;
}

const officialSource = (url, supports) => ({
  title: 'Official Black Desert patch notes',
  url,
  supports,
});
const bdoCodexSource = (name, id, supports) => ({
  title: 'BDO Codex item: ' + name,
  url: 'https://bdocodex.com/us/item/' + id + '/',
  supports,
});
const acquisitionRoute = (
  kind,
  summary,
  source,
  itemName,
  itemId,
  supports = ['acquisition'],
) => ({
  kind,
  summary,
  availability: 'permanent',
  confidence: 'high',
  sources: [
    officialSource(source, supports),
    bdoCodexSource(itemName, itemId, ['identity', 'acquisition']),
  ],
});
const acquisition = (name, id, routes) => ({
  canonicalName: name,
  itemId: id,
  status: 'reviewed',
  reviewedAt,
  routes,
});

catalog.acquisitionInfo["Dark Bonghwang's Tear"] = acquisition(
  "Dark Bonghwang's Tear",
  890011,
  [
    acquisitionRoute(
      'boss_drop',
      'Defeat the Dark Bonghwang World Boss.',
      sources.august6,
      "Dark Bonghwang's Tear",
      890011,
    ),
  ],
);
for (const [name, id] of [
  ["Lyngbakr's Bone", 821362],
  ["Lyngbakr's Scale", 821363],
  ["Lyngbakr's Fluid", 821364],
  ['Sunset Coral Essence', 821369],
]) {
  catalog.acquisitionInfo[name] = acquisition(name, id, [
    acquisitionRoute(
      'monster_drop',
      'Defeat Lyngbakr in the Great Ocean.',
      sources.august27,
      name,
      id,
    ),
  ]);
}
catalog.acquisitionInfo['Starlight Hardener'] = acquisition(
  'Starlight Hardener',
  8023,
  [
    acquisitionRoute(
      'npc_purchase',
      'Buy it for 200 Crow Coins from a Crow Coin Shop.',
      sources.august27,
      'Starlight Hardener',
      8023,
    ),
  ],
);
catalog.acquisitionInfo['Starlight Emulsifier'] = acquisition(
  'Starlight Emulsifier',
  8024,
  [
    acquisitionRoute(
      'npc_purchase',
      'Buy it for 200 Crow Coins from a Crow Coin Shop.',
      sources.august27,
      'Starlight Emulsifier',
      8024,
    ),
  ],
);
catalog.acquisitionInfo['Red Sea Monster Meat'] = acquisition(
  'Red Sea Monster Meat',
  821468,
  [
    acquisitionRoute(
      'monster_drop',
      'Defeat Lyngbakr, or complete [Weekly] Lyngbakr Ecology Survey on Cheongsa Island.',
      sources.august27,
      'Red Sea Monster Meat',
      821468,
    ),
  ],
);
catalog.acquisitionInfo['Ocean Essence'] = acquisition(
  'Ocean Essence',
  821467,
  [
    acquisitionRoute(
      'monster_drop',
      'Defeat Hollow Maretta, or complete [Weekly] Lyngbakr Ecology Survey on Cheongsa Island.',
      sources.august27,
      'Ocean Essence',
      821467,
    ),
  ],
);
catalog.acquisitionInfo['Concentrated Spellbound Catalyst'] = acquisition(
  'Concentrated Spellbound Catalyst',
  821372,
  [
    acquisitionRoute(
      'npc_purchase',
      'Buy it for 10,000,000 Silver from Old Moon Shops in towns and major cities.',
      sources.august27,
      'Concentrated Spellbound Catalyst',
      821372,
      ['npc', 'price', 'acquisition'],
    ),
    acquisitionRoute(
      'npc_exchange',
      'Exchange Spellbound Catalyst x10 for Concentrated Spellbound Catalyst x1 at an Old Moon merchant.',
      sources.august27,
      'Concentrated Spellbound Catalyst',
      821372,
      ['npc', 'exchange', 'acquisition'],
    ),
  ],
);

const spellbound = catalog.acquisitionInfo['Spellbound Catalyst'];
if (spellbound != null) {
  const exchangeSummary =
    'Exchange Concentrated Spellbound Catalyst x1 for Spellbound Catalyst x10 at an Old Moon merchant.';
  const exchangeRoute = acquisitionRoute(
    'npc_exchange',
    exchangeSummary,
    sources.august27,
    'Spellbound Catalyst',
    820936,
    ['npc', 'exchange', 'acquisition'],
  );
  const exchangeIndex = spellbound.routes.findIndex(
    (route) => route.summary === exchangeSummary,
  );
  if (exchangeIndex < 0) {
    spellbound.routes.push(exchangeRoute);
  } else {
    spellbound.routes[exchangeIndex] = exchangeRoute;
  }
  spellbound.reviewedAt = reviewedAt;
}

const previousOilName = 'Blue Whale Oil';
const currentOilName = 'Great Ocean Oil';
renameMapEntry(catalog.items, previousOilName, currentOilName);
renameRecipeIngredientReferences(previousOilName, currentOilName);
catalog.processing.itemIcons[currentOilName] = catalog.itemIcons[currentOilName];
for (const iconMap of [catalog.itemIcons, catalog.processing.itemIcons]) {
  delete iconMap[previousOilName];
}
delete catalog.marketIds[previousOilName];
delete catalog.itemWeightIds[previousOilName];
delete catalog.marketNameIds[previousOilName.toLowerCase()];
catalog.itemRenames[previousOilName] = currentOilName;
catalog.marketNameAliases[previousOilName] = currentOilName;
catalog.iconAliases[previousOilName] = currentOilName;
delete catalog.acquisitionInfo[previousOilName];
catalog.acquisitionInfo[currentOilName] = {
  canonicalName: currentOilName,
  itemId: 9727,
  status: 'reviewed',
  reviewedAt: currentReviewDate,
  routes: [
    {
      kind: 'hunting',
      summary: 'Hunt a Blue Whale, then butcher its corpse.',
      availability: 'permanent',
      confidence: 'high',
      sources: [
        officialSource(sources.september3, ['identity', 'acquisition']),
        bdoCodexSource(currentOilName, 9727, ['identity', 'acquisition']),
      ],
    },
    {
      kind: 'monster_drop',
      summary: 'Defeat sea monsters or Khan.',
      availability: 'permanent',
      confidence: 'high',
      sources: [
        officialSource(sources.september3, ['acquisition']),
        bdoCodexSource(currentOilName, 9727, ['identity', 'acquisition']),
      ],
    },
    {
      kind: 'boss_reward',
      summary: 'Open a World Boss Vell Reward Bundle.',
      availability: 'permanent',
      confidence: 'high',
      sources: [
        officialSource(sources.september3, ['acquisition']),
        bdoCodexSource(currentOilName, 9727, ['identity', 'acquisition']),
      ],
    },
  ],
};

for (const [name, currentId] of [
  ['Destruction Spirit Stone', 45298],
  ['Guardian Spirit Stone', 45300],
  ['Life Spirit Stone', 45302],
]) {
  const acquisitionInfo = catalog.acquisitionInfo[name];
  if (acquisitionInfo == null) {
    throw new Error(`Missing reviewed acquisition record for ${name}.`);
  }
  const previousId = String(acquisitionInfo.itemId);
  acquisitionInfo.itemId = currentId;
  acquisitionInfo.reviewedAt = currentReviewDate;
  for (const route of acquisitionInfo.routes ?? []) {
    for (const source of route.sources ?? []) {
      source.url = source.url
        .replace(`/item/${previousId}/`, `/item/${currentId}/`)
        .replace(`/item/${previousId}?`, `/item/${currentId}?`);
    }
  }
}
for (const obsoleteId of ['45297', '45299', '45301']) {
  delete catalog.itemWeightsLtById[obsoleteId];
}

catalog.processing.items['Breath of All Creations'] = exactProcessingRecipe({
  baseOutput: 0.4,
  group: 'Processing - Simple Alchemy',
  method: 'Simple Alchemy',
  marketId: '56185',
  sourceNote:
    'September 3, 2026 formula verified against the current game client.',
  outputMin: 1,
  outputMax: 1,
  ingredients: [
    ingredient('Oil of Fortitude', 20),
    ingredient('Energy of All Creations', 1),
    ingredient('Ancient Spirit Dust', 10),
  ],
});
catalog.processing.items["Elion's Tear"] = exactProcessingRecipe({
  baseOutput: 0.4,
  group: 'Processing - Simple Alchemy',
  method: 'Simple Alchemy',
  marketId: '17566',
  sourceNote:
    'September 3, 2026 formula verified against the current game client.',
  outputMin: 1,
  outputMax: 1,
  ingredients: [
    ingredient('Tears of War', 1),
    ingredient('Ancient Spirit Dust', 50),
  ],
});

const imperfectAlchemyStones = [
  'Imperfect Alchemy Stone of Destruction',
  'Imperfect Alchemy Stone of Protection',
  'Imperfect Alchemy Stone of Life',
];
const spiritStones = [
  'Destruction Spirit Stone',
  'Guardian Spirit Stone',
  'Life Spirit Stone',
];
const interchangeableIngredient = (options, group) => ({
  name: options[0],
  qty: 1,
  options,
  substituteGroup: group,
  substituteRatios: Object.fromEntries(options.map((name) => [name, 1])),
});
const alchemyStoneIngredient = interchangeableIngredient(
  imperfectAlchemyStones,
  'Alchemy Stone Shard:alchemy-stone',
);
const spiritStoneIngredient = interchangeableIngredient(
  spiritStones,
  'Alchemy Stone Shard:spirit-stone',
);
catalog.processing.items['Alchemy Stone Shard'] = exactProcessingRecipe({
  baseOutput: 0.4,
  group: 'Processing - Grinding',
  method: 'Grinding',
  marketId: '44336',
  sourceNote:
    'Spirit Stones yield 10–18 shards depending on Processing Mastery. Destructive stone conversions remain manual planner references.',
  outputMin: 1,
  outputMax: 1,
  ingredients: [alchemyStoneIngredient],
  recipeRole: 'manual_conversion',
  defaultVariantId: 'alchemy-stone',
  variants: [
    procVariant({
      id: 'alchemy-stone',
      label: 'Alchemy Stone',
      routeId: 'alchemy-stone',
      batchMultiplier: 1,
      ingredients: [alchemyStoneIngredient],
      outputMin: 1,
    }),
    procVariant({
      id: 'spirit-stone',
      label: 'Spirit Stone',
      routeId: 'spirit-stone',
      batchMultiplier: 1,
      ingredients: [spiritStoneIngredient],
      outputMin: 10,
      outputMax: 18,
    }),
  ],
});
catalog.acquisitionInfo['Alchemy Stone Shard'] = {
  canonicalName: 'Alchemy Stone Shard',
  itemId: 44336,
  status: 'reviewed',
  reviewedAt: currentReviewDate,
  routes: [
    {
      kind: 'processing',
      summary:
        'Buy through the Central Market, grind an Alchemy Stone, or grind a Spirit Stone for 10–18 shards depending on Processing Mastery.',
      availability: 'permanent',
      confidence: 'high',
      sources: [
        officialSource(sources.september3, ['recipe', 'conversion']),
        bdoCodexSource('Alchemy Stone Shard', 44336, [
          'identity',
          'acquisition',
        ]),
      ],
    },
  ],
};

const retiredItems = [
  'Mystical Spirit Powder',
  "Vell's Fine Powder",
  'Wild Spirit Stone',
];
delete catalog.processing.items['Mystical Spirit Powder'];
delete catalog.items["Vell's Fine Powder"];
for (const name of retiredItems) {
  delete catalog.itemIcons[name];
  delete catalog.processing.itemIcons[name];
  delete catalog.marketIds[name];
  delete catalog.marketNameIds[name.toLowerCase()];
  delete catalog.acquisitionInfo[name];
}
catalog.legacyUnavailableItems = [
  ...new Set([...catalog.legacyUnavailableItems, ...retiredItems]),
].sort((left, right) => left.localeCompare(right, 'en'));

for (const items of [
  catalog.items,
  catalog.cooking.items,
  catalog.processing.items,
]) {
  for (const [name, recipe] of Object.entries(items)) {
    const retiredReferences = recipeIngredientNames(recipe).filter((entry) =>
      retiredItems.includes(entry),
    );
    if (retiredReferences.length > 0) {
      throw new Error(
        `${name} still references retired ingredients: ${retiredReferences.join(', ')}.`,
      );
    }
  }
}

catalog.meta.version = '10.3';
if (!catalog.meta.notes.includes('v10.3: September 3 life-item update')) {
  catalog.meta.notes +=
    ' | v10.3: September 3 life-item update (Great Ocean Oil, spirit-stone shards, and revised Simple Alchemy formulas).';
}

catalog.weeklyPatchReview = {
  reviewedAt: currentReviewDate,
  range: '2026-07-23 through 2026-09-03',
  officialSources: Object.values(sources),
  thirdPartyStatus:
    'The September 3 client extraction is authoritative where third-party catalogs still expose dormant legacy rows.',
  clientEvidence: {
    clientDate: currentReviewDate,
    extractor:
      'https://github.com/iDevelopThings/bdo-data-extractor/tree/5bf11bd7bc60dcbb6126be34bf3d76633abdd8b2',
    itemsSha256:
      '108e8302014fdfbdaf324fff08c833cf879af39f9600bbd3dfd0c5808779fe2b',
    recipesSha256:
      'ef5f41af2b6ab904f6db3195f254e2e9f4dec866e7123474ae9036613aef5574',
    manufactureSha256:
      'c816450107a41e04706724bbcaf573f7a0fa798dbd2c00655ab6adb41cd10f09',
  },
  housePlannerStatus:
    'No production-node, worker, or house recipe change was identified in the September 3 patch.',
  knownSourceDiscrepancies: [
    {
      item: 'Oquilla Wave Meal',
      detail:
        "The current item-description text says 10 Nadia Rowen's Special Sauce for mass processing, while the current executable recipe data consumes 1. The executable recipe record is used.",
    },
    {
      item: 'Retired alchemy powders',
      detail:
        'The extracted recipe table retains dormant legacy rows for removed powders. The official September 3 patch and current live item formulas take precedence.',
    },
  ],
};
catalog.importedRecipeMeta.weeklyPatchesThrough20260827 = {
  reviewedAt,
  sourceUrls: Object.values(sources),
  alchemyRecipes: Object.keys(alchemyRecipes).length,
  processingRecipes: Object.keys(processingRecipes).length,
  embeddedIcons: itemRecords.length,
};
catalog.importedRecipeMeta.weeklyPatchesThrough20260903 = {
  reviewedAt: currentReviewDate,
  sourceUrls: [sources.september3],
  renamedItems: {[previousOilName]: currentOilName},
  retiredItems,
  revisedProcessingRecipes: [
    'Alchemy Stone Shard',
    'Breath of All Creations',
    "Elion's Tear",
  ],
  refreshedMarketItemIds: {
    'Destruction Spirit Stone': 45298,
    'Guardian Spirit Stone': 45300,
    'Life Spirit Stone': 45302,
  },
};

// Preserve the later, narrowly reviewed recovery routes and retired formulas.
applyTwilightPatch(catalog);
const output = JSON.stringify(catalog, null, 2) + '\n';
if (checkOnly) {
  if (output !== sourceText) {
    throw new Error(
      'The bundled catalog is not the deterministic weekly-patch result. ' +
        'Run tool/apply_weekly_patch_catalog.mjs first.',
    );
  }
  console.log('Weekly patch catalog is deterministic and current.');
} else {
  await writeFile(catalogPath, output, 'utf8');
  console.log('Applied reviewed life-skill patch data through Sep 3, 2026.');
}
