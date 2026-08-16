export const EDANIA_PART_II_SOURCE =
  'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10451&countryType=en-US';
export const EDANIA_PART_II_ASIA_SOURCE =
  'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19693';
export const EDANIA_PART_II_REVIEWED_AT = '2026-08-15';

const codexItem = (id) => `https://bdocodex.com/us/item/${id}/`;
const codexIcon = (path) => `https://bdocodex.com${path}`;

const item = ({
  name,
  id,
  weight,
  path,
  sha256,
  mode = 'processing',
  marketVerification = 'pending',
}) => ({
  name,
  id,
  weight,
  iconUrl: codexIcon(path),
  iconSha256: sha256,
  mode,
  marketVerification,
});

const slots = [
  {
    slot: 'Necklace',
    ekletaId: 11731,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/15_necklace/00011731_1.webp',
    ekletaHash:
      'ef602b6add9761f5f9284a130e912ee5ecbe357ca9c9d90c568dc1b9c2106261',
    twilightId: 821421,
    twilightHash:
      '18f1b088c3fc814a4d2ccaabf351176a499d691623fb546009f0e37e98eab5c0',
    causalityId: 821425,
    causalityHash:
      '16cf8992d11117ea24391f20e3c1391614a1e6e7643e7ac6e284ddd19dbb8838',
    apeironId: 11733,
    apeironWeight: 1,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/15_necklace/00011733_1.webp',
    apeironHash:
      'bbc39bfaaaa3b5d3aff006c4e74d05ee809c4e780bc9e871d512dc747bf49452',
  },
  {
    slot: 'Earring',
    ekletaId: 11896,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/17_earring/00011896_1.webp',
    ekletaHash:
      '6939eaebf473d935e1ba9b6bd84f3a0551e7f004dabe3d44fa1e1f020bfac2fb',
    twilightId: 821422,
    twilightHash:
      '8fa8e0c4ed0723d02f33b3ab078b4f2a6c1f2622b1b5c9c04a83fc31c306a396',
    causalityId: 821426,
    causalityHash:
      'a445e3b516e7196a4c9177f8a9fd3b820a18f074d97334b900bf4bba91685294',
    apeironId: 11898,
    apeironWeight: 0.4,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/17_earring/00011898_1.webp',
    apeironHash:
      '1a784a794db8206b35e103e6cf4b1e197c281c2d2aa97d2969f6b71b614f63df',
  },
  {
    slot: 'Ring',
    ekletaId: 12142,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/16_ring/00012142_1.webp',
    ekletaHash:
      '5428add4d384feaedf41d64110ab363339ee13b25352bebf11d04dcda786d73f',
    twilightId: 821423,
    twilightHash:
      '2e6b92383e22d0dad5e3b4c38c0b22b16f16d1abe7a50fae4487848b21dd9192',
    causalityId: 821427,
    causalityHash:
      '90ad08ce804ce11d3be7a0de1291e7868c9e0c7366b53db16951ab5c353a187e',
    apeironId: 12144,
    apeironWeight: 0.17,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/16_ring/00012144_1.webp',
    apeironHash:
      '60355352ad772cd62ceb2d8636169d72f4451b049afb80927954d502f6ae9fd2',
  },
  {
    slot: 'Belt',
    ekletaId: 12296,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/18_belt/00012296_1.webp',
    ekletaHash:
      '3fc680f0e2ade57d22c25eba9643de2f69c01ff41880dc922b346b908df9d3df',
    twilightId: 821424,
    twilightHash:
      '3c1e80c96e545baff9f99bd8ea5a2e38d88544a9adedeb36498b4817099e371d',
    causalityId: 821428,
    causalityHash:
      '9cc5ae72b2c3252b5643aa86b966e0daf9863e5700864ad4dbe81d72075390e3',
    apeironId: 12298,
    apeironWeight: 0.5,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/18_belt/00012298_1.webp',
    apeironHash:
      '2a7cb8e3da3a6bd54d0235b1710979959a556ac644c3dfe7186f255ef20d3579',
  },
];

const accessoryReforms = [
  {
    slot: 'Necklace',
    cup: 'Cup of Destined Dawn',
    effect: 'Max HP +300',
    ekletaName: 'Dawnbound Ekleta Necklace',
    ekletaId: 11732,
    ekletaWeight: 1,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/15_necklace/00011732_1.webp',
    ekletaHash:
      '3e29c62e75a270ba0b4d4c8ca50a11c8b2346956f2765f4a457ee701cbe54376',
    apeironName: 'Dawnbound Apeiron Necklace',
    apeironId: 11734,
    apeironWeight: 1,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/15_necklace/00011734_1.webp',
    apeironHash:
      '4cf289d504d16701d5e437244f8cdedb6f9df2106fe81881c8fc3a2e4fa95f42',
  },
  {
    slot: 'Earring',
    cup: 'Cup of Reticent Moonbeams',
    effect: 'All AP +3 and Max Stamina +100',
    ekletaName: 'Moonhushed Ekleta Earring',
    ekletaId: 11897,
    ekletaWeight: 0.4,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/17_earring/00011897_1.webp',
    ekletaHash:
      '999a0de3b80d6ee6475b6eeb08c6c9ef9a8292e1d2f08b59a6d7fa5b48e5b0fc',
    apeironName: 'Moonhushed Apeiron Earring',
    apeironId: 11899,
    apeironWeight: 0.4,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/17_earring/00011899_1.webp',
    apeironHash:
      '8d3e742f0751ee5b7a4877fade54dc5f4beb69a3ad6429887ec9f2bb0ebfd9ee',
  },
  {
    slot: 'Ring',
    cup: 'Cup of Callous Sun',
    effect: 'Max HP +125 and Critical Hit Extra Damage +3%',
    ekletaName: 'Sunstarved Ekleta Ring',
    ekletaId: 12143,
    ekletaWeight: 0.17,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/16_ring/00012143_1.webp',
    ekletaHash:
      '5232beb1d9abf9368d58f777f4fc45714f1a0505fcaae5bd7c07db8cf9586c75',
    apeironName: 'Sunstarved Apeiron Ring',
    apeironId: 12145,
    apeironWeight: 0.17,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/16_ring/00012145_1.webp',
    apeironHash:
      '30b9fe479c58eb83905de35047547224358169283ffc577bea783f9303500adb',
  },
  {
    slot: 'Belt',
    cup: 'Cup of Burgeoning Dusk',
    effect: 'All AP +3 and All Damage Reduction +6',
    ekletaName: 'Duskborne Ekleta Belt',
    ekletaId: 12297,
    ekletaWeight: 0.5,
    ekletaPath:
      '/items/new_icon/06_pc_equipitem/00_common/18_belt/00012297_1.webp',
    ekletaHash:
      '3ad1ef926c76eda7422e0762e08b429fc4037166a9191490a8ff4f409abd1fa4',
    apeironName: 'Duskborne Apeiron Belt',
    apeironId: 12299,
    apeironWeight: 0.5,
    apeironPath:
      '/items/new_icon/06_pc_equipitem/00_common/18_belt/00012299_1.webp',
    apeironHash:
      '09262bda656a05d5d417de9fa4a050a2052cb2ce893c43cf9fa85af77cbd7a33',
  },
];

const workshopCrates = [
  {
    name: 'Magnetite Ore Crate',
    id: 55445,
    input: 'Magnetite Ore',
    path: '/items/new_icon/03_etc/07_productmaterial/00055445.webp',
    hash: 'f9dd629dd53848cb2d061cf81ecc7b59270d7351a83885974b5baa8f5b2ba75f',
  },
  {
    name: 'Rough Marble Crate',
    id: 55446,
    input: 'Rough Marble',
    path: '/items/new_icon/03_etc/07_productmaterial/00055446.webp',
    hash: '2a0488ec68da9dac722fd8cddaabb34d6dd23353b83cf8d0cc64a440b1c41b61',
  },
  {
    name: 'Magnetite Ingot Crate',
    id: 55447,
    input: 'Magnetite Ingot',
    path: '/items/new_icon/03_etc/07_productmaterial/00055447.webp',
    hash: '90f12ed2ca6d26815e39d3406f6ca7e83e6cd785988c46905debf5a1584ae639',
  },
  {
    name: 'Marble Crate',
    id: 55448,
    input: 'Polished Marble',
    path: '/items/new_icon/03_etc/07_productmaterial/00055448.webp',
    hash: '0d79ca71e0171c3120c442a253b1b3f83ad6939dfe6bc19916c595389e913a13',
  },
];

const godslayerExchanges = [
  {
    slot: 'Helmet',
    emberName: 'Embers of Ynix - Helmet',
    emberId: 821461,
    emberHash:
      'c3d08d8c1efa1cf516131b4dc1267cd29efc407113d53ca7122cd167c7e83590',
    boxName: "Edana - Godslayer's Courage Box",
    boxId: 620397,
    boxHash:
      '936cc4b79d2ffad06d441d5d13dd47ae4829a02bc49251edb16a5312d92fdd8f',
  },
  {
    slot: 'Armor',
    emberName: 'Embers of Ynix - Armor',
    emberId: 821462,
    emberHash:
      'acf79a5e0a6ea95fbbb8a7655525df2267d6b8e4833b37bea32f90ffb63eeade',
    boxName: "Edana - Godslayer's Abstinence Box",
    boxId: 620398,
    boxHash:
      '27f5bae99c226981b2da803b0102154761e802ce2643682aff1ff9ad4f0fe526',
  },
  {
    slot: 'Gloves',
    emberName: 'Embers of Ynix - Gloves',
    emberId: 821463,
    emberHash:
      '99552e68171249f16fe7fd5023a438b353a22c741c46af744f0974210723f4e6',
    boxName: "Edana - Godslayer's Justice Box",
    boxId: 620399,
    boxHash:
      '37a3686e2f32c24ee673838188fbb45e3086a1c1d683d5c9124747c1d4691be7',
  },
  {
    slot: 'Shoes',
    emberName: 'Embers of Ynix - Shoes',
    emberId: 821464,
    emberHash:
      '5720920112ac431c922506f2f24f8196c6e8a9d67ffb79e7bc0943dd637f7200',
    boxName: "Edana - Godslayer's Wisdom Box",
    boxId: 620400,
    boxHash:
      'dc6d0dde4f87518dd0391c94f39717db4a3bb0a0e26718266e2b4d0e85ddb2e2',
  },
];

const origins = [
  {
    tier: 'WON',
    shardId: 821430,
    shardHash:
      '59e49186146fdc4ac64bf8b9da6d406d24aee4d133a94cd6849a4d2939048cf9',
    crystalId: 15294,
    crystalHash:
      'de61a2916e420108408d6488788c6d87d63e22ae51a5cb11c69ed404e59841e5',
    edaniaAp: 90,
    npcPrice: 1200000000,
  },
  {
    tier: 'BON',
    shardId: 821431,
    shardHash:
      '2ec3afa16877f2537d49c7afc01be6deeea59d41937a9640af19b573e29811ea',
    crystalId: 15295,
    crystalHash:
      '9e7be3e5f2cde1a8788903c985d8b2c403cd2caa3e5f5806521d1974f898b4e0',
    edaniaAp: 120,
    npcPrice: 1500000000,
  },
  {
    tier: 'JIN',
    shardId: 821432,
    shardHash:
      '83f745889298856246b3db0b5681106c75466a06f08fdb8b557cdf162e92b1b9',
    crystalId: 15296,
    crystalHash:
      'f33b20e9aea141e562a223dcdfe4671da97a3f2c3b34425fa0c1c41b815b69f6',
    edaniaAp: 150,
    npcPrice: 1700000000,
  },
  {
    tier: 'HAN',
    shardId: 821433,
    shardHash:
      '33e00bd5c741cdcb57a142dfbed95c35eee1636775c3945de3d60d4fa9f91bd5',
    crystalId: 15297,
    crystalHash:
      'cf09dbc9f6b00a076224062bbc9852f61371334dfa1c4deefd1b4c9e8246856d',
    edaniaAp: 180,
    npcPrice: 2000000000,
  },
];

const reforgeEffects = [
  ['All AP', '+5'],
  ['All Accuracy', '+9'],
  ['All Damage Reduction', '+7'],
  ['All Evasion', '+13'],
  ['Max HP', '+300'],
  ['Critical Hit Rate', '+6%'],
  ['Back Attack Extra Damage', '+2.5%'],
  ['Down Attack Extra Damage', '+2.5%'],
  ['Air Attack Extra Damage', '+2.5%'],
  ['Critical Hit Extra Damage', '+1.5%'],
  ["Black Spirit's Rage Recovery", '+0.6%'],
];

const hanIconGroups = [
  [
    '/items/new_icon/03_etc/07_productmaterial/00821259.webp',
    '06fde5866ec481e471199bd0190fcb98b444bd3f677d29917db274cbb4c8ebeb',
  ],
  [
    '/items/new_icon/03_etc/07_productmaterial/00821259.webp',
    '06fde5866ec481e471199bd0190fcb98b444bd3f677d29917db274cbb4c8ebeb',
  ],
  ...Array.from({ length: 3 }, () => [
    '/items/new_icon/03_etc/07_productmaterial/00821261.webp',
    '2744436cf396daa9e6aa555b9dcd301999cdb7b0d8100ded4f463f462282aaa4',
  ]),
  ...Array.from({ length: 6 }, () => [
    '/items/new_icon/03_etc/07_productmaterial/00821264.webp',
    'b565e9fc5b9b15a5659b6a46df0cbad3a9a28c58e4d7e8e61acc7e9496fcec92',
  ]),
];

const baseIconGroups = [
  ...Array.from({ length: 2 }, () => [
    '/items/new_icon/03_etc/07_productmaterial/000820953.webp',
    'b4902e7fa9de8bd58f283a558c9c4f88f019afe333033e16ec4fc5da64886bc7',
  ]),
  ...Array.from({ length: 3 }, () => [
    '/items/new_icon/03_etc/07_productmaterial/000820955.webp',
    '33e0c4d5c746753f3e5effb32aca8511b6c2ab2cc726d71f57c03bef57c45660',
  ]),
  ...Array.from({ length: 6 }, () => [
    '/items/new_icon/03_etc/07_productmaterial/000820958.webp',
    '27adc5f2e07d5cec342bd37d4df732b885117fb3b41656cf3f22e4463487efd0',
  ]),
];

export const EDANIA_PART_II_ITEMS = [
  ...slots.flatMap((entry) => [
    item({
      name: `Ekleta ${entry.slot}`,
      id: entry.ekletaId,
      weight: entry.apeironWeight,
      path: entry.ekletaPath,
      sha256: entry.ekletaHash,
      marketVerification: 'not_marketable',
    }),
    item({
      name: `Twilight of the End - ${entry.slot}`,
      id: entry.twilightId,
      weight: 0.1,
      path: `/items/new_icon/03_etc/07_productmaterial/00${entry.twilightId}.webp`,
      sha256: entry.twilightHash,
      marketVerification: 'verified',
    }),
    item({
      name: `Causality Shardstone - ${entry.slot}`,
      id: entry.causalityId,
      weight: 0.1,
      path: `/items/new_icon/03_etc/07_productmaterial/00${entry.causalityId}.webp`,
      sha256: entry.causalityHash,
    }),
    item({
      name: `Apeiron ${entry.slot}`,
      id: entry.apeironId,
      weight: entry.apeironWeight,
      path: entry.apeironPath,
      sha256: entry.apeironHash,
      marketVerification: 'verified',
    }),
  ]),
  ...accessoryReforms.flatMap((entry) => [
    item({
      name: entry.ekletaName,
      id: entry.ekletaId,
      weight: entry.ekletaWeight,
      path: entry.ekletaPath,
      sha256: entry.ekletaHash,
      marketVerification: 'not_marketable',
    }),
    item({
      name: entry.apeironName,
      id: entry.apeironId,
      weight: entry.apeironWeight,
      path: entry.apeironPath,
      sha256: entry.apeironHash,
      marketVerification: 'not_marketable',
    }),
  ]),
  ...workshopCrates.map((entry) =>
    item({
      name: entry.name,
      id: entry.id,
      weight: 30,
      path: entry.path,
      sha256: entry.hash,
      marketVerification: 'not_marketable',
    }),
  ),
  ...godslayerExchanges.flatMap((entry) => [
    item({
      name: entry.emberName,
      id: entry.emberId,
      weight: 0.1,
      path: `/items/new_icon/03_etc/07_productmaterial/${String(entry.emberId).padStart(8, '0')}.webp`,
      sha256: entry.emberHash,
      marketVerification: 'not_marketable',
    }),
    item({
      name: entry.boxName,
      id: entry.boxId,
      weight: 0.1,
      path: `/items/new_icon/09_cash/${String(entry.boxId).padStart(8, '0')}.webp`,
      sha256: entry.boxHash,
      marketVerification: 'not_marketable',
    }),
  ]),
  ...origins.flatMap((entry) => [
    item({
      name: `${entry.tier} Origin Shard`,
      id: entry.shardId,
      weight: 0.1,
      path: `/items/new_icon/03_etc/07_productmaterial/00${entry.shardId}.webp`,
      sha256: entry.shardHash,
    }),
    item({
      name: `${entry.tier} Wandering Origin Crystal`,
      id: entry.crystalId,
      weight: 0.1,
      path:
        `/items/new_icon/03_etc/11_enchant_material/000${entry.crystalId}_1.webp`,
      sha256: entry.crystalHash,
      marketVerification: 'not_marketable',
    }),
  ]),
  item({
    name: 'Fused Crystal of Decimation',
    id: 15298,
    weight: 0.1,
    path: '/items/new_icon/03_etc/11_enchant_material/00015298_1.webp',
    sha256:
      '51887ca81c4b368eacba777913e439c4e6d40b68aa12bf89c544f1c3ed91cac1',
    marketVerification: 'verified',
  }),
  item({
    name: 'Fusion Shard',
    id: 821471,
    weight: 0.1,
    path: '/items/new_icon/03_etc/07_productmaterial/00821471.webp',
    sha256:
      'b5cbf9a6b9202f8fae95b0d7a5f5599ea8289385ab1bd9665cae81ccf446a701',
    marketVerification: 'verified',
  }),
  ...reforgeEffects.flatMap(([effect], index) => {
    const baseStart = 820953;
    const hanStart = 821260;
    const basePrefix = 'Reforge Stone - ';
    const hanPrefix = 'HAN Reforge Stone - ';
    return [
      item({
        name: `${basePrefix}${effect}`,
        id: baseStart + index,
        weight: 1,
        path: baseIconGroups[index][0],
        sha256: baseIconGroups[index][1],
        marketVerification: 'verified',
      }),
      item({
        name: `${hanPrefix}${effect}`,
        id: hanStart + index,
        weight: 1,
        path: hanIconGroups[index][0],
        sha256: hanIconGroups[index][1],
      }),
    ];
  }),
  item({
    name: "Nev's Fragment",
    id: 821460,
    weight: 0.1,
    path: '/items/new_icon/03_etc/07_productmaterial/00821460.webp',
    sha256:
      'b60c6d0a2beb72e51c12fd252208455f4eb7d1608093af1d1cdcab088a3944cd',
    marketVerification: 'verified',
  }),
  item({
    name: "Margahan's Artifact",
    id: 933501,
    weight: 1,
    path: '/items/new_icon/06_pc_equipitem/00_common/00_etc/00933501.webp',
    sha256:
      '02888ebc5ef7cb13d3db2ae67ee3aaf59eeac767745fb56039dcc26abe3b679c',
    marketVerification: 'verified',
  }),
  item({
    name: "Margahan's Fragment",
    id: 767359,
    weight: 0.3,
    path: '/items/new_icon/03_etc/00767359.webp',
    sha256:
      'f58915141a5b41dee15bac7380f006dd0f084d923cd02fddbe12e53ba63ed0f1',
    marketVerification: 'verified',
  }),
  item({
    name: 'Olivine Ore',
    id: 4415,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004415.webp',
    sha256:
      '460a6cc2ae202b78212f4db6f8b540ee6d340ae313d5464ef93c2e77f780c521',
    marketVerification: 'verified',
  }),
  item({
    name: 'Magical Olivine Powder',
    id: 4496,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004496.webp',
    sha256:
      '4dd37ef9aa0449c965427e05eb40c81364b8bbd43c83c9aa6e36a2d6a50dfc65',
    marketVerification: 'verified',
  }),
  item({
    name: 'Rough Marble',
    id: 4016,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004016.webp',
    sha256:
      'f34de6b43f48aee469f19c1c50b4248d157db55202a7c6a6f371e2c8d7ecb94d',
  }),
  item({
    name: 'Polished Marble',
    id: 4096,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004096.webp',
    sha256:
      '4b287551d97254e544419bf3f3329145be001be2c3f5d9cb0d60e04a5b757e32',
  }),
  item({
    name: 'Pure Marble',
    id: 4097,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004097.webp',
    sha256:
      '65214ce11eb629c86a212b19a579f63f8b9152723de037a0d69463fe6622c517',
    marketVerification: 'verified',
  }),
  item({
    name: 'Magnetite Ore',
    id: 4017,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004017.webp',
    sha256:
      'b0394fb318630fcb7359f76c6adb40fc82394e4d8b54ba40492b43927f2a14a8',
  }),
  item({
    name: 'Melted Magnetite Shard',
    id: 4098,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004098.webp',
    sha256:
      '4170ac121f02045547e69ef3c20ddc418ffddb26f313bea901419a6b86debf1e',
  }),
  item({
    name: 'Magnetite Ingot',
    id: 4099,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004099.webp',
    sha256:
      '936b7972c173bb0b34faadef1ffb61728535c8f37295bdefb659e685214b8cae',
  }),
  item({
    name: 'Pure Magnetite Crystal',
    id: 4100,
    weight: 0.3,
    path: '/items/new_icon/03_etc/07_productmaterial/00004100.webp',
    sha256:
      'ff3e832d3a4a9f07b59fb7ed8fddf7bdc1f785cce987e16cc447360edf0be7c0',
    marketVerification: 'verified',
  }),
  item({
    name: 'Perfume of Verdure',
    id: 890,
    weight: 0.2,
    path: '/items/new_icon/03_etc/07_productmaterial/00000890.webp',
    sha256:
      'e8e5933c4b14880b67345e83173b9fe7379e0ad717bbefca5bb35ba84d2a324c',
    mode: 'alchemy',
    marketVerification: 'verified',
  }),
  item({
    name: 'Viridian Draught',
    id: 800,
    weight: 0.2,
    path: '/items/new_icon/03_etc/08_potion/00000800.webp',
    sha256:
      '45b266e8289164999f5d204137061df34c32c82f39092132c392179babd115a9',
    mode: 'alchemy',
    marketVerification: 'verified',
  }),
  item({
    name: 'Dawn Black Stone',
    id: 820984,
    weight: 0.1,
    path: '/items/new_icon/03_etc/07_productmaterial/00820984.webp',
    sha256:
      '2344f102dd4a29ba5a996fc72d78d1a3265f6f109e552b0b50f3146a4bb0faf3',
  }),
];

const ingredient = (name, qty, extra = undefined) => ({
  name,
  qty,
  ...(extra ?? {}),
});

const fixedProcessingRecipe = ({
  method,
  ingredients,
  marketId,
  outputMin = 1,
  outputMax = 1,
  variants,
  defaultVariantId,
}) => ({
  type: 'processing',
  baseOutput: (outputMin + outputMax) / 5,
  group: `Processing - ${method}`,
  method,
  ...(marketId == null ? {} : { marketId: String(marketId) }),
  outputMin,
  outputMax,
  ingredients,
  ...(defaultVariantId == null ? {} : { defaultVariantId }),
  ...(variants == null ? {} : { variants }),
});

const processingVariant = ({
  id,
  label,
  routeId,
  batchMultiplier,
  ingredients,
  outputMin,
  outputMax,
  type,
  method,
  baseOutput,
}) => ({
  id,
  label,
  routeId,
  batchMultiplier,
  ...(type == null ? {} : { type }),
  ...(method == null ? {} : { method }),
  baseOutput: baseOutput ?? (outputMin + outputMax) / 5,
  outputMin,
  outputMax,
  ingredients,
});

export const EDANIA_PART_II_PROCESSING_RECIPES = Object.fromEntries([
  ...slots.flatMap((entry) => {
    const shared = [
      ingredient('Caphras Stone', 10),
      ingredient('Magical Shard', 10),
    ];
    const causalityName = `Causality Shardstone - ${entry.slot}`;
    const causalityIngredients = [
      ingredient(`Twilight of the End - ${entry.slot}`, 5),
      ...shared,
      ingredient('Essence of Dawn', 10),
    ];
    const causalityBatchIngredients = [
      ingredient(`Twilight of the End - ${entry.slot}`, 50),
      ingredient('Caphras Stone', 100),
      ingredient('Magical Shard', 100),
      ingredient('Essence of Dawn', 100),
      ingredient('Black Stone Powder', 1),
    ];
    return [
      [
        causalityName,
        fixedProcessingRecipe({
          method: 'Heating',
          ingredients: causalityIngredients,
          defaultVariantId: 'heating-1x',
          variants: [
            processingVariant({
              id: 'heating-1x',
              label: 'Heating',
              routeId: 'heating',
              batchMultiplier: 1,
              ingredients: causalityIngredients,
              outputMin: 1,
              outputMax: 1,
            }),
            processingVariant({
              id: 'heating-10x',
              label: 'Heating',
              routeId: 'heating',
              batchMultiplier: 10,
              ingredients: causalityBatchIngredients,
              outputMin: 10,
              outputMax: 10,
            }),
          ],
        }),
      ],
      [
        `Apeiron ${entry.slot}`,
        fixedProcessingRecipe({
          method: 'Heating',
          marketId: entry.apeironId,
          ingredients: [
            ingredient(`Twilight of the End - ${entry.slot}`, 10),
            ...shared,
          ],
        }),
      ],
    ];
  }),
  ...origins.map((entry) => [
    `${entry.tier} Wandering Origin Crystal`,
    fixedProcessingRecipe({
      method: 'Simple Alchemy',
      ingredients: [
        ingredient(`${entry.tier} Origin Shard`, 100),
        ingredient('Caphras Stone', 100),
        ingredient('Magical Shard', 100),
      ],
    }),
  ]),
  [
    'Fused Crystal of Decimation',
    fixedProcessingRecipe({
      method: 'Simple Alchemy',
      marketId: 15298,
      ingredients: [
        ingredient('Crystal of Brutal Decimation', 1),
        ingredient('Fusion Shard', 30),
        ingredient('Caphras Stone', 100),
        ingredient('Magical Lightstone Crystal', 300),
        ingredient('Black Stone', 500),
      ],
    }),
  ],
  ...reforgeEffects.map(([effect], index) => [
    `HAN Reforge Stone - ${effect}`,
    fixedProcessingRecipe({
      method: 'Heating',
      ingredients: [
        ingredient(`Reforge Stone - ${effect}`, 5),
        ingredient("Nev's Fragment", 30),
        ingredient('Caphras Stone', 100),
        ingredient('Magical Shard', 100),
        ingredient('Magical Lightstone Crystal', 200),
      ],
    }),
  ]),
  [
    "Margahan's Artifact",
    fixedProcessingRecipe({
      method: 'Manufacture',
      marketId: 933501,
      ingredients: [
        ingredient("Margahan's Fragment", 100),
        ingredient('Pure Magnetite Crystal', 100),
        ingredient('Pure Marble', 100),
      ],
    }),
  ],
  [
    'Magical Olivine Powder',
    fixedProcessingRecipe({
      method: 'Grinding',
      marketId: 4496,
      outputMin: 4,
      outputMax: 6,
      ingredients: [
        ingredient('Olivine Ore', 1),
        ingredient('Pure Powder Reagent', 1),
      ],
    }),
  ],
  [
    'Polished Marble',
    fixedProcessingRecipe({
      method: 'Grinding',
      outputMin: 1,
      outputMax: 4,
      ingredients: [ingredient('Rough Marble', 10)],
    }),
  ],
  [
    'Pure Marble',
    fixedProcessingRecipe({
      method: 'Heating',
      ingredients: [
        ingredient('Polished Marble', 3),
        ingredient('Metal Solvent', 2),
      ],
    }),
  ],
  [
    'Melted Magnetite Shard',
    fixedProcessingRecipe({
      method: 'Heating',
      outputMin: 1,
      outputMax: 4,
      ingredients: [ingredient('Magnetite Ore', 5)],
    }),
  ],
  [
    'Magnetite Ingot',
    fixedProcessingRecipe({
      method: 'Heating',
      outputMin: 1,
      outputMax: 4,
      ingredients: [ingredient('Melted Magnetite Shard', 10)],
    }),
  ],
  [
    'Pure Magnetite Crystal',
    fixedProcessingRecipe({
      method: 'Heating',
      ingredients: [
        ingredient('Magnetite Ingot', 3),
        ingredient('Metal Solvent', 2),
      ],
    }),
  ],
  [
    'Dawn Black Stone',
    fixedProcessingRecipe({
      method: 'Heating',
      ingredients: [ingredient('Essence of Dawn', 20)],
      defaultVariantId: 'heating-1x',
      variants: [
        processingVariant({
          id: 'heating-1x',
          label: 'Heating',
          routeId: 'heating',
          batchMultiplier: 1,
          ingredients: [ingredient('Essence of Dawn', 20)],
          outputMin: 1,
          outputMax: 1,
        }),
        processingVariant({
          id: 'heating-10x',
          label: 'Heating',
          routeId: 'heating',
          batchMultiplier: 10,
          ingredients: [
            ingredient('Essence of Dawn', 200),
            ingredient('Black Stone Powder', 1),
          ],
          outputMin: 10,
          outputMax: 10,
        }),
      ],
    }),
  ],
]);

const referenceRecipe = ({ method, group, ingredients = [] }) => ({
  type: 'processing',
  baseOutput: 1,
  group,
  method,
  outputMin: 1,
  outputMax: 1,
  ingredients,
  recipeRole: 'manual_conversion',
});

export const EDANIA_PART_II_REFERENCE_ITEMS = Object.fromEntries([
  ...slots.map((entry) => [
    `Ekleta ${entry.slot}`,
    referenceRecipe({
      method: 'Quest Exchange',
      group: 'Reference - Ekleta Accessories',
    }),
  ]),
  ...accessoryReforms.flatMap((entry) => [
    [
      entry.ekletaName,
      referenceRecipe({
        method: 'Item Reform',
        group: 'Reference - Accessory Reform',
        ingredients: [
          ingredient(`Ekleta ${entry.slot}`, 1),
          ingredient(entry.cup, 1),
        ],
      }),
    ],
    [
      entry.apeironName,
      referenceRecipe({
        method: 'Item Reform',
        group: 'Reference - Accessory Reform',
        ingredients: [
          ingredient(`Apeiron ${entry.slot}`, 1),
          ingredient(entry.cup, 1),
        ],
      }),
    ],
  ]),
  ...workshopCrates.map((entry) => [
    entry.name,
    referenceRecipe({
      method: 'Mineral Workshop',
      group: 'Reference - Worker Crates',
      ingredients: [
        ingredient(entry.input, 10),
        ingredient('Black Stone Powder', 1),
      ],
    }),
  ]),
  ...godslayerExchanges.flatMap((entry) => [
    [
      entry.emberName,
      referenceRecipe({
        method: 'Godslayer Content',
        group: 'Reference - Godslayer',
      }),
    ],
    [
      entry.boxName,
      referenceRecipe({
        method: 'Quest Exchange',
        group: 'Reference - Godslayer',
        ingredients: [ingredient(entry.emberName, 100)],
      }),
    ],
  ]),
]);

const verdureAlchemyIngredients = [
  ingredient('Trace of Nature', 5),
  ingredient('Everlasting Herb', 5),
  ingredient('Clear Liquid Reagent', 5),
  ingredient('Oil of Tranquility', 6),
  ingredient('Magical Olivine Powder', 50),
];

export const EDANIA_PART_II_ALCHEMY_RECIPES = {
  'Perfume of Verdure': {
    type: 'alchemy',
    baseOutput: 1,
    group: 'Perfumes',
    method: 'Alchemy Tool (Skilled 1+)',
    marketId: '890',
    ingredients: verdureAlchemyIngredients,
    defaultVariantId: 'alchemy-tool',
    variants: [
      {
        id: 'alchemy-tool',
        label: 'Alchemy Tool',
        routeId: 'alchemy-tool',
        batchMultiplier: 1,
        type: 'alchemy',
        method: 'Alchemy Tool (Skilled 1+)',
        baseOutput: 1,
        ingredients: verdureAlchemyIngredients,
      },
      {
        id: 'simple-alchemy',
        label: 'Simple Alchemy',
        routeId: 'simple-alchemy',
        batchMultiplier: 1,
        type: 'simple_alchemy',
        method: 'Simple Alchemy',
        baseOutput: 1,
        outputMin: 1,
        outputMax: 1,
        ingredients: [
          ingredient('Perfume of Swiftness', 1),
          ingredient('Shining Powder', 3),
          ingredient('Magical Olivine Powder', 35),
        ],
      },
    ],
  },
  'Viridian Draught': {
    type: 'simple_alchemy',
    baseOutput: 1,
    group: 'Draughts',
    method: 'Simple Alchemy',
    marketId: '800',
    outputMin: 1,
    outputMax: 1,
    ingredients: [
      ingredient('Elixir of Mastery', 3, {
        options: ['Elixir of Mastery', 'Elixir of Improved Mastery'],
        substituteGroup: 'Viridian Draught:mastery elixir',
        substituteRatios: {
          'Elixir of Mastery': 1,
          'Elixir of Improved Mastery': 1 / 3,
        },
      }),
      ingredient('Elixir of Time', 3, {
        options: ['Elixir of Time', 'Elixir of Flowing Time'],
        substituteGroup: 'Viridian Draught:time elixir',
        substituteRatios: {
          'Elixir of Time': 1,
          'Elixir of Flowing Time': 1 / 3,
        },
      }),
      ingredient('Tears of the Falling Moon', 1),
      ingredient('Magical Olivine Powder', 10),
    ],
  },
};

const source = (title, url, supports) => ({ title, url, supports });
const officialSource = (supports) =>
  source('Official Edania Part II patch notes', EDANIA_PART_II_SOURCE, supports);
const codexSource = (record, supports) =>
  source(`BDO Codex item: ${record.name}`, codexItem(record.id), supports);

const acquisition = (record, kind, summary, supports) => ({
  canonicalName: record.name,
  itemId: record.id,
  status: 'reviewed',
  reviewedAt: EDANIA_PART_II_REVIEWED_AT,
  routes: [
    {
      kind,
      summary,
      availability: 'permanent',
      confidence: 'high',
      sources: [
        officialSource(supports),
        codexSource(record, ['identity', 'acquisition']),
      ],
    },
  ],
});

const recordByName = Object.fromEntries(
  EDANIA_PART_II_ITEMS.map((record) => [record.name, record]),
);

export const EDANIA_PART_II_ACQUISITION_INFO = Object.fromEntries([
  ...slots.flatMap((entry) => {
    const ekleta = recordByName[`Ekleta ${entry.slot}`];
    const twilight = recordByName[`Twilight of the End - ${entry.slot}`];
    const apeiron = recordByName[`Apeiron ${entry.slot}`];
    return [
      [
        ekleta.name,
        acquisition(
          ekleta,
          'npc_exchange',
          `After the prerequisite quest, exchange a NOV Kharazad ${entry.slot} for an unenhanced Ekleta ${entry.slot}, or a DEC Kharazad ${entry.slot} for a TET Ekleta ${entry.slot}, through Clorince's recurring exchange. An unenhanced Ekleta ${entry.slot} can be exchanged back for a NOV Kharazad ${entry.slot}.`,
          ['quest-exchange', 'enhancement'],
        ),
      ],
      [
        twilight.name,
        acquisition(
          twilight,
          'monster_drop',
          `Obtain ${twilight.name} from monsters in Edania, or buy it through the Central Market.`,
          ['monster-drop', 'market-eligibility'],
        ),
      ],
      [
        apeiron.name,
        acquisition(
          apeiron,
          'monster_drop',
          `Obtain ${apeiron.name} from Inner Edania bosses and monsters, craft it by Heating, or buy it through the Central Market.`,
          ['boss-drop', 'monster-drop', 'processing'],
        ),
      ],
    ];
  }),
  ...accessoryReforms.flatMap((entry) =>
    [
      [entry.ekletaName, `Ekleta ${entry.slot}`],
      [entry.apeironName, `Apeiron ${entry.slot}`],
    ].map(([reformedName, baseName]) => {
      const record = recordByName[reformedName];
      return [
        reformedName,
        acquisition(
          record,
          'item_reform',
          `Reform ${baseName} with ${entry.cup} to gain ${entry.effect}. Extract with Refined Essence of Emotions to recover the original accessory and cup.`,
          ['item-reform', 'reform-effect', 'extraction'],
        ),
      ];
    }),
  ),
  ...workshopCrates.map((entry) => {
    const record = recordByName[entry.name];
    return [
      entry.name,
      acquisition(
        record,
        'worker_crafting',
        `Craft at a Mineral Workshop with 10 ${entry.input} and 1 Black Stone Powder. This is worker crafting, not character Processing.`,
        ['worker-workshop', 'crate-recipe'],
      ),
    ];
  }),
  ...godslayerExchanges.flatMap((entry) => {
    const ember = recordByName[entry.emberName];
    const box = recordByName[entry.boxName];
    return [
      [
        entry.emberName,
        acquisition(
          ember,
          'quest_item',
          `A ${entry.slot.toLowerCase()}-part Godslayer exchange material. Collect 100 and exchange them with the Ynix Remnant for ${entry.boxName}.`,
          ['godslayer-material', 'quest-exchange'],
        ),
      ],
      [
        entry.boxName,
        acquisition(
          box,
          'npc_exchange',
          `Exchange 100 ${entry.emberName} with the Ynix Remnant for this ${entry.slot.toLowerCase()}-part Godslayer box.`,
          ['godslayer-box', 'quest-exchange'],
        ),
      ],
    ];
  }),
  ...origins.map((entry) => {
    const record = recordByName[`${entry.tier} Origin Shard`];
    return [
      record.name,
      acquisition(
        record,
        'monster_drop',
        `Obtain ${record.name} by defeating monsters in Edania.`,
        ['monster-drop'],
      ),
    ];
  }),
  ...reforgeEffects.map(([effect]) => {
    const record = recordByName[`Reforge Stone - ${effect}`];
    return [
      record.name,
      acquisition(
        record,
        'boss_reward',
        `Obtain ${record.name} from eligible Land of the Morning Light World Boss rewards, or buy it through the Central Market.`,
        ['reforge-material', 'world-boss'],
      ),
    ];
  }),
  ...[
    ['Fusion Shard', 'monster_drop', 'Obtain Fusion Shards by defeating monsters in Edania, or buy them through the Central Market.'],
    ["Nev's Fragment", 'monster_drop', "Obtain Nev's Fragments by defeating monsters in Edania, or buy them through the Central Market."],
    ['Olivine Ore', 'production_node', 'Obtain Olivine Ore from the Tarsis Mountains production node or while gathering Basalt, or buy it through the Central Market.'],
    ['Rough Marble', 'production_node', 'Obtain Rough Marble from the Tarsis Mountains production node or while gathering Marble.'],
    ['Polished Marble', 'processing', 'Grind 10 Rough Marble to make Polished Marble.'],
    ['Pure Marble', 'processing', 'Heat 2 Metal Solvents with 3 Polished Marble to make Pure Marble, or buy it through the Central Market.'],
    ['Magnetite Ore', 'production_node', 'Obtain Magnetite Ore from the Mount Dirfydan production node or while gathering Basalt.'],
    ['Melted Magnetite Shard', 'processing', 'Heat 5 Magnetite Ore to make Melted Magnetite Shards.'],
    ['Magnetite Ingot', 'processing', 'Heat 10 Melted Magnetite Shards to make Magnetite Ingots.'],
    ['Pure Magnetite Crystal', 'processing', 'Heat 2 Metal Solvents with 3 Magnetite Ingots to make a Pure Magnetite Crystal, or buy it through the Central Market.'],
    ['Dawn Black Stone', 'boss_reward', 'Obtain Dawn Black Stones from Dark Rift monsters or make them by Heating Essence of Dawn.'],
  ].map(([name, kind, summary]) => {
    const record = recordByName[name];
    return [
      name,
      acquisition(record, kind, summary, ['identity', 'acquisition']),
    ];
  }),
  [
    "Margahan's Fragment",
    {
      canonicalName: "Margahan's Fragment",
      itemId: 767359,
      status: 'reviewed',
      reviewedAt: EDANIA_PART_II_REVIEWED_AT,
      routes: [
        {
          kind: 'npc_exchange',
          summary:
            "Exchange 200 Magical Lightstone Crystals or 20 Sharp Black Crystal Shards with Resh in Angavu for 1 Margahan's Fragment. It can also appear while gathering Basalt or Marble, and is sold on the Central Market.",
          availability: 'permanent',
          confidence: 'high',
          sources: [
            officialSource(['exchange', 'gathering', 'market-eligibility']),
            codexSource(recordByName["Margahan's Fragment"], [
              'identity',
              'acquisition',
            ]),
          ],
        },
      ],
    },
  ],
]);

export const EDANIA_PART_II_PENDING_MARKET_VERIFICATION =
  EDANIA_PART_II_ITEMS.filter(
    (record) => record.marketVerification === 'pending',
  ).map((record) => ({ name: record.name, itemId: record.id }));

export const EDANIA_PART_II_INFERRED_PROCESSING_OUTPUTS = [
  ['Polished Marble', 1, 4],
  ['Pure Marble', 1, 1],
  ['Melted Magnetite Shard', 1, 4],
  ['Magnetite Ingot', 1, 4],
  ['Pure Magnetite Crystal', 1, 1],
].map(([name, outputMin, outputMax]) => ({
  name,
  outputMin,
  outputMax,
  basis:
    'Uses the planner\'s reviewed standard Processing-family result model; the official patch notes specify the formula but not this output range.',
}));

export const EDANIA_PART_II_UNRESOLVED_ITEMS = [
  {
    name: 'Causality Hammer',
    itemId: null,
    status: 'identity_pending',
    knownUse:
      'Prevents the enhancement level of PRI or higher Ekleta and Apeiron accessories from dropping on failure.',
    source:
      'https://blackdesert.pearlabyss.com/TR/en-us/News/Notice/Detail?_boardNo=19607',
    requiredBeforeBundling:
      'Verify the stable item ID, exact English identity, weight, and artwork hash.',
  },
];

export const EDANIA_PART_II_REFORGE_EFFECTS = Object.fromEntries(
  reforgeEffects.map(([name, value]) => [`HAN Reforge Stone - ${name}`, `${name} ${value}`]),
);

export const EDANIA_PART_II_ORIGIN_CRYSTALS = Object.fromEntries(
  origins.map((entry) => [
    `${entry.tier} Wandering Origin Crystal`,
    {
      edaniaMonsterAp: entry.edaniaAp,
      monsterDamageReduction: 20,
      npcPrice: entry.npcPrice,
    },
  ]),
);
