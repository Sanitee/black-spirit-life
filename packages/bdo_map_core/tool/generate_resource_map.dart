import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _sourceCommit = '289c833d34851dc84f3a647a2d9cf604eda9c93a';
const _sourceUri =
    'https://raw.githubusercontent.com/fffam/'
    'blackdesert-somethinglovely-map/'
    '$_sourceCommit/src/data.json';
const _sourceSha256 =
    '030d87ad1b752ad07df521aa9faef5b03fd2164a8e13726ebc31b3b0313d4c49';
const _gatheringSourceBaseUri =
    'https://raw.githubusercontent.com/fffam/'
    'blackdesert-somethinglovely-map/'
    '$_sourceCommit/src/gathering';
const _gatheringPointProvenanceId = 'somethinglovely-mit-gathering-points';
const _edaniaSeedSha256 =
    '458f86cafebc01514cb353f4332c0897fa73d0e522827f990820287a99ce255d';
const _edaniaExtractorCommit = '2e4ace61e2a3967663cb36580edb7201b7ca3fd4';
const _edaniaWorldSha256 =
    '9555d1a84c45e347f7d464ed16e69eeb6066478f8ced0833d2100d55ff7ca4c6';
const _edaniaItemsSha256 =
    'e36491ceffd3885de03688e8bf689f25cf9ba688767a8cc20267f3ca826ccb2b';
const _edaniaNodeProvenanceId = 'na-client-edania-node-facts-2026-reference';
const _currentNodeSeedSha256 =
    '752dc2af7c7350d1e8154984d12dd200559460d51c6ffde521099a6a52ef375c';
const _currentNodeProvenanceId =
    'bdo-codex-current-worldmap-nodes-2026-08-15-reference';
const _currentNodeSourceRetrievedAt = '2026-08-15T16:55:00.000Z';
const _currentNodeCount = 1052;
const _currentExplorationNodeCount = 610;
const _currentProductionNodeCount = 442;
const _currentLinkedProductionNodeCount = 437;
const _currentNodeProductCount = 285;
const _vendorSeedSha256 =
    '49f555739d0c8fc7d5ec1c3fdfb22368b432f81d2084475fe2aa133e48ae1f21';
const _vendorProvenanceId =
    'bdo-codex-vendor-npc-locations-2026-08-15-reference';
const _vendorSourceRetrievedAt = '2026-08-15T12:00:00.000Z';
const _vendorItemCount = 52;
const _vendorSeedListingCount = 1256;
const _vendorSpawnCount = 285;
const _mappedVendorSpawnCount = 274;
const _vendorLocationCount = 284;
const _curatedVendorLocationCount = 266;
const _mappedVendorListingCount = 1243;
const _unmappedVendorSpawnCount = 11;
const _vendorInteractionObjectNames = <String, String>{
  'npc:44102:2': "Finlin's Signboard",
  'npc:62319:1': 'Sol Magia - Exchange',
  'npc:62319:2': 'Sol Magia - Exchange',
  'npc:62319:3': 'Sol Magia - Exchange',
  'npc:59605:1': 'Sol Magia Exchange',
  'npc:59605:2': 'Sol Magia Exchange',
  'npc:59605:3': "Syca's Scale - Exchange",
  'npc:59591:2': "Vaha's Heart - Exchange",
  'npc:59591:3': "Vaha's Sky - Exchange",
  'npc:59773:3': "Yolu's Nail - Exchange",
  'npc:59773:1': "Yolu's Pupil - Exchange",
  'npc:59773:2': "Yolu's Tail - Exchange",
  'npc:22472:0': "Syca's Cradle Sol Magia",
  'npc:22388:0': "Vaha's Cradle - Sol Magia",
  'npc:59591:1': "Vaha's Sky - Sol Magia",
};
const _canonicalVendorSourceAliases = <String, String>{
  'npc:40605:2': 'npc:40605:1',
  'npc:45322:1': 'npc:45124:1',
};
const _excludedVendorLocationIndexes = <String, Set<int>>{
  'npc:44013:1': <int>{1},
};
const _reviewedVendorLocationCoordinates = <String, List<(double x, double z)>>{
  'npc:40605:1': <(double, double)>[(-145016, 140597)],
  'npc:40605:2': <(double, double)>[(-145016, 140597)],
  'npc:45124:1': <(double, double)>[(577825, 278057)],
  'npc:45322:1': <(double, double)>[(577849, 278073)],
  'npc:44013:1': <(double, double)>[(366130, -46583), (366130, -46583.2)],
};
const _currentResourceNodeTypes = <String>{
  'Excavation',
  'Farm',
  'Fish Drying Yard',
  'Gathering',
  'Lumbering',
  'Mining',
  'Mushrooms',
};
const _rusalkaSeedSha256 =
    'cba044ea2d0cc68bc732adf5d26d5fe19b3f2c98f61e5fc2f29ba5e609f72179';
const _rusalkaPointProvenanceId = 'bdo-codex-rusalka-coral-points-reference';
const _rusalkaSourceUrl = 'https://bdocodex.com/us/npc/28115/';
const _rusalkaSourceRetrievedAt = '2026-07-28T18:05:00Z';
const _rusalkaPixelOriginX = 68600.0;
const _rusalkaPixelOriginY = 72200.0;
const _rusalkaPixelScale = 25.0;
const _stillcoralSeedSha256 =
    'de076ea5fbd4ad075b4442391314c4671dc9bb449b1e0350277c521f46ffdd2f';
const _stillcoralPointProvenanceId =
    'bdo-codex-stillcoral-coastal-points-reference';
const _stillcoralSourceRetrievedAt = '2026-08-01';
const _stillcoralFieldSourceId = 'field-source:stillcoral-coastal-gathering';
const _bdoCodexPixelOriginX = 68600.0;
const _bdoCodexPixelOriginY = 72200.0;
const _bdoCodexPixelScale = 25.0;
const _drieghanAnimalPointProvenanceId =
    'bdo-codex-drieghan-animal-points-reference';
const _tshiraRotationProvenanceId = 'bdo-workshop-tshira-rotation-facts-2026';
const _drieghanSourceRetrievedAt = '2026-07-28T20:30:00Z';
const _tshiraRotationRetrievedAt = '2026-07-28T20:15:00Z';
const _tshiraRotationSpotId = 'gathering:tshira-snake-scorpion-rotation';
const _tshiraNodeX = 104760.0;
const _tshiraNodeZ = -273497.0;
const _tshiraRouteFocusRadius = 30000.0;
const _tshiraRouteFocusX = 105950.0;
const _tshiraRouteFocusZ = -299439.0;
const _marniSniperSeedSha256 =
    '91a0caa6d65308aa26d4e28d1d65b505e627cd47b77cfd95a66249fd42abcecd';
const _marniSniperProvenanceId =
    'pearl-abyss-marni-sniper-hunting-guide-2026-08-01';
const _marniSniperRetrievedAt = '2026-08-01T10:00:00Z';
const _marniSniperFieldSourceId = 'field-source:marni-sniper-hunting';
const _citronOrchardSpotId = 'gathering:maslans-yulas-citron-orchard';
const _citronFieldSourceId = 'field-source:citron-tree';
const _citronProvenanceId = 'bdo-codex-citron-orchard-facts-2026-08-12';
const _citronReviewedAt = '2026-08-12T10:00:00Z';
const _wildBeehiveSourceId = 'field-source:wild-beehive';
const _wildBeehiveProvenanceId = 'bdo-codex-wild-beehive-facts-2026-09-09';
const _dairyCowFieldSourceId = 'field-source:dairy-cow';
const _dairyCowProvenanceId = 'pearl-abyss-dairy-cow-farms-reference';
const _dairyCowReviewedAt = '2026-08-27T00:00:00Z';
const _truffleOfficialPatchProvenanceId =
    'pearl-abyss-truffle-location-update-2022-11-02';
const _truffleOfficialReviewedAt = '2026-08-28T00:00:00Z';
const _truffleOfficialPatchUrl =
    'https://www.console.playblackdesert.com/News/Notice/Detail?'
    'boardNo=12103&boardType=2&countryType=en-US';
const _truffleOfficialOverviewUrls = <String, String>{
  'Serendia':
      'https://s1.playblackdesert.com/web/CONSOLE/Upload/News/'
      '0e2e3f005da20221123051140062.jpg',
  'Calpheon':
      'https://s1.playblackdesert.com/web/CONSOLE/Upload/News/'
      '52fd099f9a320221123051151586.jpg',
  'Mediah':
      'https://s1.playblackdesert.com/web/CONSOLE/Upload/News/'
      'c8a6f47b2e620221123051204131.jpg',
  'Drieghan':
      'https://s1.playblackdesert.com/web/CONSOLE/Upload/News/'
      '98c6f1e565a20221123051215139.jpg',
};
const _datasetVersion = '2026.09.09-beta-v4';
const _datasetGeneratedAt = '2026-09-09T02:30:00Z';
const _expectedResourceSectionCounts = <String, int>{
  'plantsWood': 123,
  'oresMinerals': 58,
  'meat': 18,
  'bloodHides': 30,
  'mushrooms': 27,
  'seafoodMarine': 57,
  'other': 45,
};
const _otherResourceItemIds = <int>{
  5951, // Trace of Chaos
  5952, // Trace of Despair
  5954, // Trace of the Earth
  5955, // Trace of Ascension
  5956, // Trace of Savagery
  5957, // Trace of Origin
  5958, // Trace of Battle
  5959, // Trace of Hunting
  5960, // Trace of Nature
  5961, // Trace of Violence
  5963, // Trace of Memory
  6656, // Purified Water
  6657, // Bag of Muddy Water
  7702, // Cooking Honey
  9064, // Egg
  9065, // Milk
  44230, // Ancient Civilization Follower's Seal
  44255, // Dull Bone Fragment
  44258, // Ancient Artifact Shard
};
const _plantWoodResourceItemIds = <int>{
  5401, // Sunrise Herb
  5402, // Silver Azalea
  5404, // Dry Mane Grass
  5405, // Silk Honey Grass
  5421, // Pile of Sunrise Herbs
  5422, // Bunch of Silver Azaleas
  5425, // Bunch of Silk Honey Grass
  5532, // Bracken
  5522, // Vedelona
  7360, // Citron
  44287, // Withered Leaf
};
const _oreMineralResourceItemIds = <int>{
  4010, // Sulfur
  4405, // Rough Diamond
  4998, // Sharp Black Crystal Shard
  44118, // Black Dirt
  44257, // Weathered Rock Fragment from Ruins Site
  44260, // Obscuring Golem Fragment
  44356, // Dry Rock Fragment
  752023, // Mass of Pure Magic
};
const _bloodHideResourceItemIds = <int>{
  5804, // Fleece
  44035, // Tough Bear Hide
};
const _meatResourceItemIds = <int>{
  7921, // Chicken Meat
};
const _seafoodMarineResourceItemIds = <int>{
  4476, // Red Coral
  4477, // Blue Coral
  6504, // Green Coral
  6509, // Giant Pearl Clam
  6511, // Lobster
  6515, // Oyster
  6516, // Shrimp
  8246, // Crawfish
  821255, // Rusalka's Coral
};
const _stillcoralUsefulProducts = <int, String>{
  4476: 'Red Coral',
  4477: 'Blue Coral',
  4998: 'Sharp Black Crystal Shard',
  6501: 'Coral Piece',
  6504: 'Green Coral',
  6509: 'Giant Pearl Clam',
  6511: 'Lobster',
  6515: 'Oyster',
  6516: 'Shrimp',
  8246: 'Crawfish',
};
const _stillcoralTradeProducts = <int, String>{
  55880: 'Oyster Shell with Pearls',
  55881: 'Glittering Coral',
  55883: 'Giant Pearl Clam Shell',
};
const _coralStonebackCrabNormalProducts = <int, String>{
  821255: "Rusalka's Coral",
  6533: 'Coral Crystal',
  6501: 'Coral Piece',
  4411: 'Rough Blue Crystal',
  4406: 'Rough Translucent Crystal',
  4203: 'Platinum Ore',
  4201: 'Silver Ore',
  4006: 'Rough Stone',
};
const _drieghanAnimalPointSources = <_BdoCodexNpcPointSource>[
  _BdoCodexNpcPointSource(
    npcId: 21758,
    pageTitle: 'Stone Cobra',
    resourceId: 'item:7922',
    target: 'Stone Cobra',
    label: 'Stone Cobra gathering location',
    kind: 'butchering',
    overrideOption: '--bdo-codex-21758-source',
    expectedPointCount: 266,
    normalizedSha256:
        'b3d4e92a00453284a3560d153716191bd4fdccb204c9782e82c5ab6611ff08ca',
  ),
  _BdoCodexNpcPointSource(
    npcId: 21757,
    pageTitle: 'Rock Scorpion',
    resourceId: 'item:7924',
    target: 'Rock Scorpion',
    label: 'Rock Scorpion gathering location',
    kind: 'butchering',
    overrideOption: '--bdo-codex-21757-source',
    expectedPointCount: 253,
    normalizedSha256:
        '710606f384ace1b35f0a5502b7e6d8ae5c6fa0a734b7c8d6ab17bf25f1c13800',
  ),
];
const _logGatheringResource = _GatheringPointResource(
  itemId: 4605,
  name: 'Log',
  category: 'Timber & sap',
  aliases: <String>['tree log', 'lumbering log', 'wood log'],
  kind: 'lumbering',
);
const _gatheringPointSources = <_GatheringPointSource>[
  _GatheringPointSource(
    itemId: 7922,
    equivalentItemIds: <int>[7922],
    sourceFilename: 'item-7922.json',
    sha256: '57efb89e5bd7c3316aa7c82348bf55c09c6445e362f5e0fe60f6e50ae99a3abd',
    overrideOption: '--gathering-7922-source',
    target: 'Snake',
    label: 'Snake',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 7922,
        name: 'Snake Meat',
        category: 'Gathering meat',
        aliases: <String>['snake', 'cobra meat', 'cobra'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6019,
    equivalentItemIds: <int>[6019, 6222],
    sourceFilename: 'item-6019.json',
    sha256: 'ef2a172cadfe3be8cb0b95a7dd79631bbe69b295db9c14fdd488de45d02e85ce',
    overrideOption: '--gathering-6019-source',
    target: 'Snake',
    label: 'Snake',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6019,
        name: 'Snake Skin',
        category: 'Gathering hide',
        aliases: <String>['snake hide', 'fancy reptile skin'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6222,
        name: 'Cobra Blood',
        category: 'Gathering blood',
        aliases: <String>['snake blood'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 7924,
    equivalentItemIds: <int>[6224, 7924],
    sourceFilename: 'item-7924.json',
    sha256: '8bef47e9a93f87eb70ae48278d7653d53588fdb4a38de1c151cee13949949564',
    overrideOption: '--gathering-7924-source',
    target: 'Scorpion',
    label: 'Scorpion',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 7924,
        name: 'Scorpion Meat',
        category: 'Gathering meat',
        aliases: <String>['scorpion', 'rock scorpion'],
        kind: 'butchering',
      ),
      _GatheringPointResource(
        itemId: 6224,
        name: 'Scorpion Blood',
        category: 'Gathering blood',
        aliases: <String>['rock scorpion blood'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 7902,
    equivalentItemIds: <int>[6002, 6202, 7902],
    sourceFilename: 'item-7902.json',
    sha256: 'b355ccaceacbed25155d1e0898c6666739bfee4ea97c7a848a0a15d8dd0e0c7c',
    overrideOption: '--gathering-7902-source',
    target: 'Sheep',
    label: 'Sheep',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 7902,
        name: 'Lamb Meat',
        category: 'Gathering meat',
        aliases: <String>['sheep meat', 'lamb'],
        kind: 'butchering',
      ),
      _GatheringPointResource(
        itemId: 6202,
        name: 'Sheep Blood',
        category: 'Gathering blood',
        aliases: <String>['lamb blood'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 6002,
        name: 'Sheep Hide',
        category: 'Gathering hide',
        aliases: <String>['lamb hide', 'soft hide'],
        kind: 'tanning',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6214,
    equivalentItemIds: <int>[6014, 6214, 7913],
    sourceFilename: 'item-6214.json',
    sha256: '237d579c4d5b21ca0be7e6120faf396606b05d805b63826f7034fbfa3b760c69',
    overrideOption: '--gathering-6214-source',
    target: 'Wolf',
    label: 'Wolf',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6014,
        name: 'Wolf Hide',
        category: 'Gathering hide',
        aliases: <String>['wolf skin'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6214,
        name: 'Wolf Blood',
        category: 'Gathering blood',
        aliases: <String>['wolf'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7913,
        name: 'Wolf Meat',
        category: 'Gathering meat',
        aliases: <String>['wolf', 'red meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6201,
    equivalentItemIds: <int>[6001, 6201, 7901],
    sourceFilename: 'item-6201.json',
    sha256: 'ad35c723c5e584df38c06af7bb3647c811ee25c255cbaa27acc220a092a6c92f',
    overrideOption: '--gathering-6201-source',
    target: 'Deer',
    label: 'Deer',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6001,
        name: 'Deer Hide',
        category: 'Gathering hide',
        aliases: <String>['deer skin'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6201,
        name: 'Deer Blood',
        category: 'Gathering blood',
        aliases: <String>['deer'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7901,
        name: 'Deer Meat',
        category: 'Gathering meat',
        aliases: <String>['deer', 'red meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6203,
    equivalentItemIds: <int>[6003, 6203, 7903],
    sourceFilename: 'item-6203.json',
    sha256: 'aa2f8fa06d7c5d328669fd56657e056c09d560ff55a63fc48dd952b715b453ec',
    overrideOption: '--gathering-6203-source',
    target: 'Fox',
    label: 'Fox',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6003,
        name: 'Fox Hide',
        category: 'Gathering hide',
        aliases: <String>['fox skin'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6203,
        name: 'Fox Blood',
        category: 'Gathering blood',
        aliases: <String>['fox'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7903,
        name: 'Fox Meat',
        category: 'Gathering meat',
        aliases: <String>['fox', 'red meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6205,
    equivalentItemIds: <int>[6005, 6205, 7905],
    sourceFilename: 'item-6205.json',
    sha256: 'ee77fe8d1a3743ceb40805b0c02091e8e32aa3a138120d79622fd5360ecd2dac',
    overrideOption: '--gathering-6205-source',
    target: 'Pig',
    label: 'Pig',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6005,
        name: 'Pig Hide',
        category: 'Gathering hide',
        aliases: <String>['pig skin'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6205,
        name: 'Pig Blood',
        category: 'Gathering blood',
        aliases: <String>['pig'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7905,
        name: 'Pork',
        category: 'Gathering meat',
        aliases: <String>['pig', 'pig meat', 'pork meat', 'red meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6206,
    equivalentItemIds: <int>[6006, 6206, 7906],
    sourceFilename: 'item-6206.json',
    sha256: '4108457ecc2ee0eefdffe288b0fa55c5de8977f8c5eda85375192a6f6ed5c693',
    overrideOption: '--gathering-6206-source',
    target: 'Cow / Ox',
    label: 'Cow / Ox',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6006,
        name: 'Ox Hide',
        category: 'Gathering hide',
        aliases: <String>['cow hide', 'cow skin', 'ox skin'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6206,
        name: 'Ox Blood',
        category: 'Gathering blood',
        aliases: <String>['cow blood'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7906,
        name: 'Beef',
        category: 'Gathering meat',
        aliases: <String>['cow meat', 'ox meat', 'red meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 5420,
    equivalentItemIds: <int>[5420],
    sourceFilename: 'a10430.json',
    sha256: '128becad9cc712ec07e9cb49dd5f68329cfc031e77f30c1b9c62bc9164b91500',
    overrideOption: '--gathering-a10430-source',
    target: 'Truffle Mushroom',
    label: 'Truffle Mushroom',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 5420,
        name: 'Truffle Mushroom',
        category: 'Mushrooms',
        aliases: <String>['truffle', 'truffles'],
        kind: 'gathering with bare hands or a hoe',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 5406,
    equivalentItemIds: <int>[5406],
    sourceFilename: 'a10432.json',
    sha256: '803c43d0159a27dfa06d7871fcdc9f5c5bb028a0676fb7d2e0ddca812fddaaa3',
    overrideOption: '--gathering-a10432-source',
    target: 'Everlasting Herb',
    label: 'Everlasting Herb',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 5406,
        name: 'Everlasting Herb',
        category: 'Plants & flowers',
        aliases: <String>['everlasting herb plant', 'wild herb'],
        kind: 'gathering with bare hands or a hoe',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 5601,
    equivalentItemIds: <int>[5601, 5602],
    sourceFilename: 'a10465.json',
    sha256: '88d380468ec9f583a6919ccf0cd4d48e9aec34e4830e670085cf9c3986f221fb',
    overrideOption: '--gathering-a10465-source',
    target: 'Insectivore Plant',
    label: 'Historical Insectivore Plant location',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 5601,
        name: 'Insectivore Plant Powder',
        category: 'Gatherables',
        aliases: <String>['carnivorous plant powder', 'insectivore powder'],
        kind: 'gathering with bare hands or a hoe',
      ),
      _GatheringPointResource(
        itemId: 5602,
        name: 'Insectivore Plant Sap',
        category: 'Gatherables',
        aliases: <String>['carnivorous plant sap', 'insectivore sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 5020,
    equivalentItemIds: <int>[4616, 5020],
    sourceFilename: 'a11913.json',
    sha256: 'b091809e05977900c145f8ec6bb232d3d6860e793189e24ee15a266a01453d33',
    overrideOption: '--gathering-a11913-source',
    target: 'Thuja',
    label: 'Thuja',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4616,
        name: 'Thuja Timber',
        category: 'Timber & sap',
        aliases: <String>['thuja tree', 'thuja wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5020,
        name: 'Thuja Sap',
        category: 'Timber & sap',
        aliases: <String>['thuja tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4601,
    equivalentItemIds: <int>[4601, 5001],
    sourceFilename: 'a10537.json',
    sha256: 'b99dec35f837c01ad104385b1021b4fb57792a991b86c1a720eac3d555c04a2a',
    overrideOption: '--gathering-a10537-source',
    target: 'Ash Tree',
    label: 'Representative historical Ash Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4601,
        name: 'Ash Timber',
        category: 'Timber & sap',
        aliases: <String>['ash tree', 'ash wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5001,
        name: 'Ash Sap',
        category: 'Timber & sap',
        aliases: <String>['ash tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4604,
    equivalentItemIds: <int>[4604, 5004],
    sourceFilename: 'a10503.json',
    sha256: '8a3f907f10df6df0a2b21995585ee71e4a80ac54b57ac9093bf6e6267d34d891',
    overrideOption: '--gathering-a10503-source',
    target: 'Birch Tree',
    label: 'Representative historical Birch Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4604,
        name: 'Birch Timber',
        category: 'Timber & sap',
        aliases: <String>['birch tree', 'birch wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5004,
        name: 'Birch Sap',
        category: 'Timber & sap',
        aliases: <String>['birch tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4607,
    equivalentItemIds: <int>[4607, 5010],
    sourceFilename: 'a10511.json',
    sha256: '4b55e76e1b41d42797e5bafc1ffd2d2dbb7dba4ec265cfaf7da00833fc79bd15',
    overrideOption: '--gathering-a10511-source',
    target: 'Cedar Tree',
    label: 'Representative historical Cedar Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4607,
        name: 'Cedar Timber',
        category: 'Timber & sap',
        aliases: <String>['cedar tree', 'cedar wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5010,
        name: 'Cedar Sap',
        category: 'Timber & sap',
        aliases: <String>['cedar tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4606,
    equivalentItemIds: <int>[4606, 5009],
    sourceFilename: 'a10509.json',
    sha256: 'be5b1200ceb21610a3e7f1be1c3bb4369f941cf439137b1f97ce9b5c3837ae4f',
    overrideOption: '--gathering-a10509-source',
    target: 'Fir Tree',
    label: 'Representative historical Fir Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4606,
        name: 'Fir Timber',
        category: 'Timber & sap',
        aliases: <String>['fir tree', 'fir wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5009,
        name: 'Fir Sap',
        category: 'Timber & sap',
        aliases: <String>['fir tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4602,
    equivalentItemIds: <int>[4602, 5002],
    sourceFilename: 'a10525.json',
    sha256: '974e62646ff4d5e56929ea33f692f5b68fecf03930378419aa49471ba08e117b',
    overrideOption: '--gathering-a10525-source',
    target: 'Maple Tree',
    label: 'Representative historical Maple Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4602,
        name: 'Maple Timber',
        category: 'Timber & sap',
        aliases: <String>['maple tree', 'maple wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5002,
        name: 'Maple Sap',
        category: 'Timber & sap',
        aliases: <String>['maple tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4603,
    equivalentItemIds: <int>[4603, 5003],
    sourceFilename: 'a10558.json',
    sha256: '8426fe22724d93daff6ffefc9a697c4db10c150aa187a753a98fb36f4daf4472',
    overrideOption: '--gathering-a10558-source',
    target: 'Pine Tree',
    label: 'Representative historical Pine Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4603,
        name: 'Pine Timber',
        category: 'Timber & sap',
        aliases: <String>['pine tree', 'pine wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5003,
        name: 'Pine Sap',
        category: 'Timber & sap',
        aliases: <String>['pine tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4609,
    equivalentItemIds: <int>[4609, 5013],
    sourceFilename: 'a10584.json',
    sha256: '9ab492a0814ecc58b4f6e03052d51f1043929034a4d3568ddb12e2117edc76d5',
    overrideOption: '--gathering-a10584-source',
    target: 'Acacia Tree',
    label: 'Representative historical Acacia Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4609,
        name: 'Acacia Timber',
        category: 'Timber & sap',
        aliases: <String>['acacia tree', 'acacia wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5013,
        name: 'Acacia Sap',
        category: 'Timber & sap',
        aliases: <String>['acacia tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4611,
    equivalentItemIds: <int>[4611, 5014],
    sourceFilename: 'a10578.json',
    sha256: '9a110df8f54d2bda98b856a304863093800247bd3c55c6a33a0638bd008d088c',
    overrideOption: '--gathering-a10578-source',
    target: 'Elder Tree',
    label: 'Representative historical Elder Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4611,
        name: 'Elder Tree Timber',
        category: 'Timber & sap',
        aliases: <String>['elder tree', 'elder wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5014,
        name: 'Elder Tree Sap',
        category: 'Timber & sap',
        aliases: <String>['elder sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4608,
    equivalentItemIds: <int>[4608, 5012],
    sourceFilename: 'a10620.json',
    sha256: '67e1989e1441141a941ce1b845e34e9a2c1da74e369bab0bb382fcbc9edccdef',
    overrideOption: '--gathering-a10620-source',
    target: 'White Cedar Tree',
    label: 'Representative historical White Cedar Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4608,
        name: 'White Cedar Timber',
        category: 'Timber & sap',
        aliases: <String>['white cedar tree', 'white cedar wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5012,
        name: 'White Cedar Sap',
        category: 'Timber & sap',
        aliases: <String>['white cedar tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 4619,
    equivalentItemIds: <int>[4619, 5023],
    sourceFilename: 'a11956.json',
    sha256: '88d49a1040219699908ecf6c3b61cab9e645f41575d197c6900b1bb0cd0f44b8',
    overrideOption: '--gathering-a11956-source',
    target: 'Thornwood Tree',
    label: 'Historical Thornwood Tree location',
    maximumPointCount: 300,
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 4619,
        name: 'Thornwood Timber',
        category: 'Timber & sap',
        aliases: <String>['thornwood tree', 'thornwood wood'],
        kind: 'lumbering',
      ),
      _GatheringPointResource(
        itemId: 5023,
        name: 'Thornwood Sap',
        category: 'Timber & sap',
        aliases: <String>['thorn tree sap'],
        kind: 'fluid collecting',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 5538,
    equivalentItemIds: <int>[5538],
    sourceFilename: 'a11981.json',
    sha256: '62bd62c5f14470fa0cadd13298492f5ec5e691f1b064f3b7ec6b7b64cd999a39',
    overrideOption: '--gathering-a11981-source',
    target: 'Delotia',
    label: 'Delotia',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 5538,
        name: 'Delotia',
        category: 'Gatherables',
        aliases: <String>['delotia flower', 'wild delotia'],
        kind: 'gathering with bare hands or a hoe',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 5526,
    equivalentItemIds: <int>[5526],
    sourceFilename: 'a10207.json',
    sha256: '772a5c7a609366d4a22ab5f562080dcc1038d769fee9e15658ad1b5a950af001',
    overrideOption: '--gathering-a10207-source',
    target: 'Violet Flower',
    label: 'Violet Flower',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 5526,
        name: 'Violet Flower',
        category: 'Gatherables',
        aliases: <String>['violet', 'violet wildflower'],
        kind: 'gathering with bare hands or a hoe',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 5517,
    equivalentItemIds: <int>[5517],
    sourceFilename: 'a10415.json',
    sha256: 'cd9f88bd599bb5db14f7019218edefd11155b93fb4a86a343d9c0914841c1e97',
    overrideOption: '--gathering-a10415-source',
    target: 'Volcanic Umbrella Mushroom',
    label: 'Volcanic Umbrella Mushroom',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 5517,
        name: 'Volcanic Umbrella Mushroom',
        category: 'Mushrooms',
        aliases: <String>['volcanic mushroom', 'umbrella mushroom'],
        kind: 'gathering with bare hands or a hoe',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6213,
    equivalentItemIds: <int>[6013, 6213, 7912],
    sourceFilename: 'item-6213.json',
    sha256: '1d5c80cdaa3cc4ea8c96d18aef844469963afc959881f2c1e094576153b4cf9d',
    overrideOption: '--gathering-6213-source',
    target: 'Bear',
    label: 'Bear',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6013,
        name: 'Bear Hide',
        category: 'Gathering hide',
        aliases: <String>[
          'balenos bear hide',
          'bear skin',
          'brown bear hide',
          'red bear hide',
          'serendia bear hide',
        ],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6213,
        name: 'Bear Blood',
        category: 'Gathering blood',
        aliases: <String>[
          'balenos bear blood',
          'brown bear blood',
          'red bear blood',
          'serendia bear blood',
        ],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7912,
        name: 'Bear Meat',
        category: 'Gathering meat',
        aliases: <String>[
          'balenos bear meat',
          'brown bear meat',
          'red bear meat',
          'serendia bear meat',
        ],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6216,
    equivalentItemIds: <int>[6216, 7915],
    sourceFilename: 'item-6216.json',
    sha256: 'ee9872f47834952894bf7a18474b3de9693005913875d2e6df0c35f3351771d0',
    overrideOption: '--gathering-6216-source',
    target: 'Wasteland Cheetah Dragon',
    label: 'Cheetah Dragon',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6216,
        name: 'Cheetah Dragon Blood',
        category: 'Gathering blood',
        aliases: <String>['cheetah blood', 'wasteland cheetah dragon blood'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7915,
        name: 'Cheetah Dragon Meat',
        category: 'Gathering meat',
        aliases: <String>['cheetah meat', 'wasteland cheetah dragon meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6218,
    equivalentItemIds: <int>[6218, 7917],
    sourceFilename: 'item-6218.json',
    sha256: 'f305c376e42e6421bc37d8fd2ab08ed9031fcc18fffbcfdd3df3094fa547cded',
    overrideOption: '--gathering-6218-source',
    target: 'Fan Flamingo',
    label: 'Flamingo',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6218,
        name: 'Flamingo Blood',
        category: 'Gathering blood',
        aliases: <String>['fan flamingo blood'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7917,
        name: 'Flamingo Meat',
        category: 'Gathering meat',
        aliases: <String>['fan flamingo meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6208,
    equivalentItemIds: <int>[6008, 6208, 7908],
    sourceFilename: 'item-6208.json',
    sha256: 'f4f5b52b55b9b14666bf5b5d954fb17b8369d1d91e36a788ba738eed79fbd045',
    overrideOption: '--gathering-6208-source',
    target: 'Lizard',
    label: 'Lizard',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6008,
        name: 'Lizard Hide',
        category: 'Gathering hide',
        aliases: <String>[
          'iguana hide',
          'salamander hide',
          'sandceratops hide',
        ],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6208,
        name: 'Lizard Blood',
        category: 'Gathering blood',
        aliases: <String>[
          'iguana blood',
          'salamander blood',
          'sandceratops blood',
        ],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7908,
        name: 'Lizard Meat',
        category: 'Gathering meat',
        aliases: <String>[
          'iguana meat',
          'salamander meat',
          'sandceratops meat',
        ],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6210,
    equivalentItemIds: <int>[6010, 6210, 7910],
    sourceFilename: 'item-6210.json',
    sha256: '3e7fac1e814bcebb5ff132baa89e431e727b22cc73e85259aaa5c45515b0d7e7',
    overrideOption: '--gathering-6210-source',
    target: 'Raccoon',
    label: 'Raccoon',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6010,
        name: 'Raccoon Hide',
        category: 'Gathering hide',
        aliases: <String>['brown raccoon hide', 'thief raccoon hide'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6210,
        name: 'Raccoon Blood',
        category: 'Gathering blood',
        aliases: <String>['brown raccoon blood', 'thief raccoon blood'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7910,
        name: 'Raccoon Meat',
        category: 'Gathering meat',
        aliases: <String>['brown raccoon meat', 'thief raccoon meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6212,
    equivalentItemIds: <int>[6012, 6212, 7911],
    sourceFilename: 'item-6212.json',
    sha256: '52e739dc1f80c0b1aa49e089848cabc6e902cfa22bb74125d2c0eab3a3fcde76',
    overrideOption: '--gathering-6212-source',
    target: 'Weasel',
    label: 'Weasel',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6012,
        name: 'Weasel Hide',
        category: 'Gathering hide',
        aliases: <String>['ferocious weasel hide'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6212,
        name: 'Weasel Blood',
        category: 'Gathering blood',
        aliases: <String>['ferocious weasel blood'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7911,
        name: 'Weasel Meat',
        category: 'Gathering meat',
        aliases: <String>['ferocious weasel meat'],
        kind: 'butchering',
      ),
    ],
  ),
  _GatheringPointSource(
    itemId: 6204,
    equivalentItemIds: <int>[6004, 6204, 7904],
    sourceFilename: 'item-6204.json',
    sha256: '1d067355b1c29a5330851794a443a011516b6ca38ce68dc0e7a2151a0bea85dc',
    overrideOption: '--gathering-6204-source',
    target: 'Stone Rhino',
    label: 'Rhino',
    resources: <_GatheringPointResource>[
      _GatheringPointResource(
        itemId: 6004,
        name: 'Rhino Hide',
        category: 'Gathering hide',
        aliases: <String>['baby stone rhino hide', 'stone rhino hide'],
        kind: 'tanning',
      ),
      _GatheringPointResource(
        itemId: 6204,
        name: 'Rhino Blood',
        category: 'Gathering blood',
        aliases: <String>['baby stone rhino blood', 'stone rhino blood'],
        kind: 'fluid collecting',
      ),
      _GatheringPointResource(
        itemId: 7904,
        name: 'Rhino Meat',
        category: 'Gathering meat',
        aliases: <String>['baby stone rhino meat', 'stone rhino meat'],
        kind: 'butchering',
      ),
    ],
  ),
];

const _fieldOnlyResources = <_GatheringPointResource>[
  _GatheringPointResource(
    itemId: 7701,
    name: 'Wild Beehive',
    category: 'Cooking materials',
    aliases: <String>['wild beehives', 'beehive', 'beehives'],
    kind: 'hunting with a matchlock',
  ),
  _GatheringPointResource(
    itemId: 9065,
    name: 'Milk',
    category: 'Farm produce',
    aliases: <String>['cow milk', 'dairy', 'milkable cow', 'milking'],
    kind: 'cow milking minigame',
  ),
  _GatheringPointResource(
    itemId: 7360,
    name: 'Citron',
    category: 'Farm produce',
    aliases: <String>['citron fruit', 'citron tree', 'yulas citron'],
    kind: 'gathering with bare hands',
  ),
  _GatheringPointResource(
    itemId: 5440,
    name: 'Insectivore Plant Flower',
    category: 'Gatherables',
    aliases: <String>[
      'carnivorous plant flower',
      'naga marsh poisonous plant flower',
      'poisonous plant flower',
    ],
    kind: 'defeating poisonous plants',
  ),
  _GatheringPointResource(
    itemId: 5441,
    name: 'Insectivore Plant Leaf',
    category: 'Gatherables',
    aliases: <String>[
      'carnivorous plant leaf',
      'naga marsh poisonous plant leaf',
      'poisonous plant leaf',
    ],
    kind: 'defeating poisonous plants',
  ),
  _GatheringPointResource(
    itemId: 5442,
    name: 'Insectivore Plant Stalk',
    category: 'Gatherables',
    aliases: <String>[
      'carnivorous plant stalk',
      'naga marsh poisonous plant stalk',
      'poisonous plant stalk',
    ],
    kind: 'defeating poisonous plants',
  ),
  _GatheringPointResource(
    itemId: 5443,
    name: 'Insectivore Plant Root',
    category: 'Gatherables',
    aliases: <String>[
      'carnivorous plant root',
      'naga marsh poisonous plant root',
      'poisonous plant root',
    ],
    kind: 'defeating poisonous plants',
  ),
];

Future<void> main(List<String> arguments) async {
  final sourceOverride = _option(arguments, '--source');
  final outputOverride = _option(arguments, '--output');
  final sourceBytes = sourceOverride == null
      ? await _download(Uri.parse(_sourceUri))
      : await File(sourceOverride).readAsBytes();
  final actualDigest = sha256.convert(sourceBytes).toString();
  if (actualDigest != _sourceSha256) {
    stderr.writeln(
      'Source checksum mismatch.\n'
      'Expected: $_sourceSha256\n'
      'Actual:   $actualDigest',
    );
    exitCode = 2;
    return;
  }
  final gatheringSourcePayloads = await _loadGatheringPointSources(arguments);
  if (gatheringSourcePayloads == null) {
    return;
  }
  final edaniaSeed = await _loadEdaniaSeed(arguments);
  if (edaniaSeed == null) {
    return;
  }
  final currentNodeSeed = await _loadCurrentNodeSeed(arguments);
  if (currentNodeSeed == null) {
    return;
  }
  final marniSniperSeed = await _loadMarniSniperSeed(arguments);
  if (marniSniperSeed == null) {
    return;
  }
  final rusalkaSeed = await _loadRusalkaSeed(arguments);
  if (rusalkaSeed == null) {
    return;
  }
  final stillcoralSeed = await _loadStillcoralSeed(arguments);
  if (stillcoralSeed == null) {
    return;
  }
  final vendorSeed = await _loadVendorSeed(arguments);
  if (vendorSeed == null) {
    return;
  }
  final drieghanAnimalPayloads = await _loadDrieghanAnimalPointSources(
    arguments,
  );
  if (drieghanAnimalPayloads == null) {
    return;
  }

  final resourcesById = <String, Map<String, Object?>>{};
  _addCurrentNodeResources(resourcesById, currentNodeSeed);
  final workerNodes = _buildCurrentWorkerNodes(currentNodeSeed, resourcesById);
  _addEdaniaResources(resourcesById, edaniaSeed);
  _addGatheringResources(resourcesById);
  _addMarniHuntingResourceModes(resourcesById, marniSniperSeed);
  _addRusalkaResource(resourcesById, rusalkaSeed);
  _addStillcoralResources(resourcesById, stillcoralSeed);
  _addCoralStonebackCrabResourceModes(resourcesById);
  _addDrieghanAnimalAliases(resourcesById);
  _normalizeNodeOutputNames(workerNodes, resourcesById);
  _assignResourceSections(resourcesById, workerNodes);
  final gatheringPoints = <Map<String, Object?>>[
    ..._buildGatheringPoints(gatheringSourcePayloads),
    ..._buildRusalkaGatheringPoints(rusalkaSeed),
    ..._buildStillcoralGatheringPoints(stillcoralSeed),
  ];
  final occupiedGatheringCoordinates = gatheringPoints
      .map(
        (point) =>
            '${_coordinateComponent((point['x']! as num).toDouble())},'
            '${_coordinateComponent((point['z']! as num).toDouble())}',
      )
      .toSet();
  gatheringPoints.addAll(
    _buildDrieghanAnimalGatheringPoints(
      drieghanAnimalPayloads,
      occupiedCoordinates: occupiedGatheringCoordinates,
    ),
  );
  _sortAndValidateGatheringPoints(gatheringPoints);
  final gatheringSpots = <Map<String, Object?>>[
    _buildTshiraRotationSpot(drieghanAnimalPayloads),
    _buildMarniSniperHuntingSpot(marniSniperSeed, currentNodeSeed),
    _buildCitronOrchardSpot(workerNodes),
    _buildWildBeehiveSpot(workerNodes),
    ..._buildDairyCowSpots(workerNodes),
    ..._buildOfficialTruffleSpots(workerNodes, gatheringPoints),
  ];
  workerNodes.sort((a, b) {
    final first = int.tryParse(a['id']! as String);
    final second = int.tryParse(b['id']! as String);
    if (first != null && second != null) {
      return first.compareTo(second);
    }
    return (a['id']! as String).compareTo(b['id']! as String);
  });
  final resources = resourcesById.values.toList(growable: false)
    ..sort((a, b) {
      final byName = (a['name']! as String).compareTo(b['name']! as String);
      return byName != 0
          ? byName
          : (a['id']! as String).compareTo(b['id']! as String);
    });
  final fieldSources = _buildFieldSources(
    resourcesById,
    marniSniperSeed,
    stillcoralSeed,
  );
  final vendorNpcs = _buildVendorNpcs(vendorSeed);
  final vendorListings = _buildVendorListings(vendorSeed, vendorNpcs);

  final result = <String, Object?>{
    'manifest': <String, Object?>{
      'schemaVersion': 1,
      'datasetVersion': _datasetVersion,
      'generatedAt': _datasetGeneratedAt,
      'coordinateReference': 'Black Desert game-world X/Z; render Y = -Z',
      'provenance': <Map<String, Object?>>[
        <String, Object?>{
          'id': _currentNodeProvenanceId,
          'title':
              'Black Spirit Life current world-map node facts '
              '(BDO Codex research reference)',
          'url': 'https://bdocodex.com/us/worldmap/',
          'license':
              'Pearl Abyss-origin game facts; BDO Codex credited as '
              'research/retrieval reference',
          'permittedUse':
              'The world-map payload retrieved '
              '$_currentNodeSourceRetrievedAt was reduced to factual node '
              'IDs, English names, coordinates, icon/type metadata, CP '
              'costs, links, and output item IDs/names. Raw HTML and '
              'knowledge data are not shipped. It contains all 1,052 '
              'current records: 610 raw exploration-layer records and 442 '
              'raw production-layer records. The 426 source production-link '
              'rows resolve to 425 unique parent-linked children because '
              'one row is a duplicate self-link. Twelve of the 17 upstream '
              'orphans were subsequently matched to named parents from '
              'reviewed BDO Codex node-detail records, leaving five '
              'explicitly unlinked rows. The snapshot also validates 667 '
              'raw exploration-link rows and 285 output items. No parent or '
              'topology is inferred from proximity. The source research '
              'input is excluded from the public repository. The normalized '
              'runtime records are Pearl Abyss-origin game facts retained '
              "under the project's free noncommercial fan-content basis, "
              'with BDO Codex credited as the retrieval/reference source.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _vendorProvenanceId,
          'title':
              'Black Spirit Life vendor and NPC location facts '
              '(BDO Codex research reference)',
          'url': 'https://bdocodex.com/us/item/9001/',
          'license':
              'Pearl Abyss-origin game facts; BDO Codex credited as '
              'research/retrieval reference',
          'permittedUse':
              'The snapshot retrieved $_vendorSourceRetrievedAt reduces '
              'the BDO Codex Sold by NPC tables and matching NPC map arrays '
              'to factual item IDs/names/prices, NPC IDs/spawn IDs, English '
              'names/roles, and exact coordinates. It covers '
              '$_vendorItemCount reviewed planner vendor items, '
              '$_vendorSeedListingCount seller rows, '
              '$_mappedVendorSpawnCount mapped seller spawns, and '
              '$_vendorLocationCount exact locations. '
              'The app-facing map excludes ${_vendorInteractionObjectNames.length} '
              'reviewed signboard or Atoraxxion interaction-object records and '
              'collapses three reviewed duplicate physical points, leaving '
              '$_curatedVendorLocationCount NPC location pins and '
              '$_mappedVendorListingCount item-to-location listings. '
              '$_unmappedVendorSpawnCount seller records without an exact '
              'source location remain excluded and fail closed. Pearl Abyss '
              'NPC artwork is stored separately in a checksum-pinned local '
              'fan-content bundle and is never hotlinked at runtime. The '
              'source research input is excluded from the public repository. '
              'The normalized runtime records are Pearl Abyss-origin game '
              "facts retained under the project's free noncommercial "
              'fan-content basis, with BDO Codex credited as the retrieval/'
              'reference source. Positions remain source-recorded and open '
              'to correction if current-game behavior differs.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _gatheringPointProvenanceId,
          'title':
              'SomethingLovely exact gathering points '
              '(MIT; historical through 2021)',
          'url':
              'https://github.com/fffam/'
              'blackdesert-somethinglovely-map/tree/'
              '$_sourceCommit/src/gathering',
          'license': 'MIT',
          'permittedUse':
              'Exact coordinate arrays for the Snake, Scorpion, Sheep, Wolf, '
              'Deer, Fox, Pig, Cow/Ox, Bear, Cheetah Dragon, Flamingo, '
              'Lizard, Raccoon, Weasel, and Rhino animal families plus '
              'Truffle Mushroom, Everlasting Herb, Insectivore Plant, Thuja, '
              'Delotia, Violet Flower, Volcanic Umbrella Mushroom, and '
              'representative Ash, Birch, Cedar, Fir, Maple, Pine, Acacia, '
              'Elder, White Cedar, and Thornwood tree locations were '
              'transformed and deduplicated under the repository MIT '
              'license. Equivalent byte-identical item files reuse one '
              'pinned payload per coordinate set. Log is attached as a '
              'shared lumbering product to the existing tree coordinates; '
              'it does not add or imply a separate coordinate payload. Very '
              'large tree layers use a deterministic 20 by 15 spatial grid '
              'selection capped at 300 genuine source coordinates per tree '
              'family. Coverage is historical through 2021 and is not '
              'represented as verified current spawn coverage.',
          'attribution': 'Copyright (c) 2016-2021 Famme',
        },
        <String, Object?>{
          'id': _truffleOfficialPatchProvenanceId,
          'title': 'Official Truffle Mushroom location expansion',
          'url': _truffleOfficialPatchUrl,
          'license':
              'Pearl Abyss official fan-content media; noncommercial use',
          'permittedUse':
              'The November 2, 2022 official update names thirteen Truffle '
              'Mushroom gathering areas, lists 87 mushrooms across those '
              'areas, and states that respawn time was reduced by 33%. The '
              'four English official regional overview images are displayed '
              'in this free, unofficial fan application with attribution. '
              'They are regional navigation guides, not exact cave-entrance '
              'photos. They are attached only to named-area navigation '
              'focuses and never to individual historical dots. '
              'Named-area markers reuse independently reviewed node centers '
              'or an existing MIT-licensed historical truffle coordinate as '
              'navigation anchors; no new exact spawn geometry is inferred.',
          'attribution': 'Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _dairyCowProvenanceId,
          'title': 'Official Dairy Cow farm and milking facts',
          'url':
              'https://www.tw.playblackdesert.com/News/Notice/Detail?'
              'boardNo=9671',
          'license': 'Official factual cross-check; no source media copied',
          'permittedUse':
              'Official Pearl Abyss event notices identify Falres Dirt Farm, '
              'Bain Farmland, Wale Farm, Stonetail Horse Ranch, Grana Farm, '
              'and Duvencrune Farmland as places with Dairy Cows, and state '
              'that the milking minigame consumes 10 Energy. Each map marker '
              'reuses the separately reviewed current node coordinate only '
              'as a named farm-center anchor. It is not represented as an '
              'individual cow spawn, coverage circle, or guaranteed exact '
              'interaction position.',
          'attribution': 'Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _rusalkaPointProvenanceId,
          'title':
              'Pearl Abyss Coral Stoneback Crab point facts '
              '(BDO Codex research reference)',
          'url': _rusalkaSourceUrl,
          'license':
              'Pearl Abyss-origin game facts; BDO Codex credited as '
              'research/retrieval reference',
          'permittedUse':
              'Thirty-four maximum-zoom pixel coordinates were transcribed '
              'from the BDO Codex NPC page retrieved '
              '$_rusalkaSourceRetrievedAt and converted with '
              'gameX = (pixelX - 68600) * 25 and '
              'gameZ = (72200 - pixelY) * 25. The source research input is '
              'excluded from the public repository. These normalized Pearl '
              "Abyss-origin point facts are retained under the project's "
              'free noncommercial fan-content basis, with BDO Codex credited '
              'as the research reference. Positions remain source-recorded '
              'and open to correction.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _stillcoralPointProvenanceId,
          'title':
              'Pearl Abyss Stillcoral coastal point facts '
              '(BDO Codex research reference)',
          'url': 'https://bdocodex.com/us/gatherable/10924/',
          'license':
              'Pearl Abyss-origin game facts; BDO Codex credited as '
              'research/retrieval reference',
          'permittedUse':
              '198 maximum-zoom pixel coordinates '
              'were selected from four BDO Codex gatherable pages on '
              '$_stillcoralSourceRetrievedAt: 105 Rainbow Coral, 66 Oyster, '
              'six Giant Pearl Clam, and 21 Sea Fan records. The fixed '
              'review window uses center (88119.647, 44693.294), radius '
              '1,000 pixels, gameX = (pixelX - 68600) * 25, and '
              'gameZ = (72200 - pixelY) * 25. Every output point remains '
              'an individual recorded object position. The dataset does '
              'not connect the dots, claim a route order, or merge these '
              'objects with the separate Coral Stoneback Crab layer. The '
              'source research input is excluded from the public repository. '
              'These normalized Pearl Abyss-origin point facts are retained '
              "under the project's free noncommercial fan-content basis, "
              'with BDO Codex credited as the research reference. Positions '
              'remain source-recorded and open to correction.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': 'pearl-abyss-coral-stoneback-crab-output-facts-2025',
          'title': 'Official Coral Stoneback Crab gathering-output facts',
          'url':
              'https://www.naeu.playblackdesert.com/en-US/News/Detail?'
              'countryType=en-US&groupContentNo=9763',
          'license': 'Official factual cross-check; no source media copied',
          'permittedUse':
              'The normal Coral Stoneback Crab defeat-and-mine sequence '
              'and its listed gathering outputs were retained as factual '
              'search guidance. This official cross-check supplies no '
              'spawn coordinates; exact crab positions remain attributed '
              'only to the separate credited BDO Codex research record.',
          'attribution': 'Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _drieghanAnimalPointProvenanceId,
          'title':
              'Pearl Abyss Stone Cobra and Rock Scorpion point facts '
              '(BDO Codex research reference)',
          'url': 'https://bdocodex.com/us/npc/21758/',
          'license':
              'Pearl Abyss-origin game facts; BDO Codex credited as '
              'research/retrieval reference',
          'permittedUse':
              'The Stone Cobra and Rock Scorpion coordinate arrays from '
              'BDO Codex NPC pages 21758 and 21757 were normalized from '
              'the pages retrieved $_drieghanSourceRetrievedAt and '
              'converted with gameX = (pixelX - 68600) * 25 and '
              'gameZ = (72200 - pixelY) * 25. The source research input is '
              'excluded from the public repository. These normalized Pearl '
              "Abyss-origin point facts are retained under the project's "
              'free noncommercial fan-content basis, with BDO Codex credited '
              'as the research reference. Exact spawn persistence remains '
              'open to current-game correction.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _tshiraRotationProvenanceId,
          'title': 'BDO Workshop Tshira rotation snapshot (July 2026)',
          'url': 'https://bdoworkshop.com/gathering-calculator',
          'license':
              'Factual cross-check only; no site media or route geometry '
              'copied',
          'permittedUse':
              'The current rotation list retrieved '
              '$_tshiraRotationRetrievedAt identifies "Snake and '
              'Scorpions at Tshira Ruins" as a combined butchering '
              'rotation. Its four logged sessions (3.4 hours) reported '
              'roughly a two-to-one Snake-to-Scorpion interaction mix. '
              'The map focus is calculated only from the separately '
              'attributed exact BDO Codex points; no video frames or '
              'traced route were copied.',
          'attribution': 'BDO Workshop; factual snapshot dated 2026-07-04',
        },
        <String, Object?>{
          'id': _marniSniperProvenanceId,
          'title': 'Official Marni sniper hunting guide facts (August 2026)',
          'url': 'https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=74',
          'license':
              'Official factual cross-check; no source media or prose copied',
          'permittedUse':
              'The official guide retrieved $_marniSniperRetrievedAt '
              'identifies the Land of the Morning Light Wild Game Preserve '
              'as an advanced sniper-hunting area containing primarily '
              'boars, bears, and hawks; explains that nearby animals react '
              'to gunshots and that boars, bears, and tigers may charge; and '
              'states that the Marni Sniper Rifle requires Hunting Artisan '
              '10. Official Land of the Morning Light update notes also '
              'identify Forest Crystal and the sniper-hunting crystals as '
              'rare hunting rewards. The Beombawi Valley label is '
              'cross-checked against a '
              'current independent guide. The marker uses the existing '
              'reviewed Beombawi Valley node coordinate as a region anchor. '
              'It is not an exact animal spawn, coverage circle, or traced '
              'route.',
          'attribution':
              'Pearl Abyss Corp.; location wording cross-checked with '
              'GrumpyG',
        },
        <String, Object?>{
          'id': _edaniaNodeProvenanceId,
          'title': 'Minimal NA-client Edania node factual extract',
          'url':
              'https://github.com/iDevelopThings/'
              'bdo-data-extractor/tree/$_edaniaExtractorCommit',
          'license':
              'Pearl Abyss-origin game facts; extractor source separately '
              'credited under its noncommercial licence',
          'permittedUse':
              'The v4 seed retains only reviewed node IDs, English names, '
              'X/Z positions, parent/child links, and item IDs/names from '
              'the user-owned NA client. The extractor is read-only. Its '
              'license covers the extractor code only and grants no rights '
              'in Pearl Abyss data. The source research input is excluded '
              'from the public repository. The normalized runtime records '
              "are Pearl Abyss-origin game facts retained under the project's "
              'free noncommercial fan-content basis; the extractor source '
              'remains separately credited.',
          'attribution':
              'Pearl Abyss Corp.; extractor copyright (c) 2026 '
              'idevelopthings',
        },
        <String, Object?>{
          'id': 'pearl-abyss-edania-production-node-facts-2025',
          'title': 'Official Outer Edania production-node update',
          'url':
              'https://blackdesert.pearlabyss.com/TR/en-us/News/Notice/'
              'Detail?_boardNo=19155',
          'license': 'Official factual cross-check; no media or prose copied',
          'permittedUse':
              'The names, production types, results, and 1 CP cost of the '
              'fifteen August 21, 2025 Edania production nodes were '
              'cross-checked as facts. Coordinates come only from the '
              'separately identified app-normalized NA-client factual '
              'extract.',
          'attribution': 'Pearl Abyss Corp., update dated 2025-08-21',
        },
        <String, Object?>{
          'id': 'pearl-abyss-frozen-halo-node-facts-2026',
          'title': 'Official Frozen Halo production-node update',
          'url':
              'https://blackdesert.pearlabyss.com/TR/en-us/News/Notice/'
              'Detail?_boardNo=19517',
          'license': 'Official factual cross-check; no media or prose copied',
          'permittedUse':
              'The Frozen Halo node and its Purified Water and Bag of Muddy '
              'Water results were cross-checked as facts from the March 26, '
              '2026 update. Coordinates come only from the separately '
              'identified app-normalized NA-client factual extract.',
          'attribution': 'Pearl Abyss Corp., update dated 2026-03-26',
        },
        <String, Object?>{
          'id': 'pearl-abyss-production-node-update-2026-06-04',
          'title': 'Official June 2026 production-node update',
          'url':
              'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/'
              'Detail?_boardNo=13267',
          'license': 'Official factual cross-check; no media or prose copied',
          'permittedUse':
              'The June 4, 2026 additions and output changes at Wolf Hills, '
              'Gervish Mountains, Blood Wolf Settlement, La O\'delle, '
              'Garmoth\'s Nest, Kamasylvia, Valencia, and other listed '
              'nodes were cross-checked as facts. IDs, links, coordinates, '
              'and complete output rows come only from the separately '
              'identified normalized current world-map research record.',
          'attribution': 'Pearl Abyss Corp., update dated 2026-06-04',
        },
        <String, Object?>{
          'id': 'pearl-abyss-inner-edania-production-nodes-2026-08-13',
          'title': 'Official Inner Edania production-node update',
          'url':
              'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/'
              'Detail?_boardNo=19693',
          'license': 'Official factual cross-check; no media or prose copied',
          'permittedUse':
              'The August 13, 2026 Inner Edania production nodes and the '
              'Rough Marble, Magnetite Ore, and Olivine Ore resource chains '
              'were cross-checked as facts. Node IDs, links, coordinates, '
              'and complete output rows come only from the separately '
              'identified normalized current world-map research record.',
          'attribution': 'Pearl Abyss Corp., update dated 2026-08-13',
        },
        <String, Object?>{
          'id': 'bdo-codex-vedelona-item-facts-2026-07-29',
          'title': 'BDO Codex Vedelona item and acquisition facts',
          'url': 'https://bdocodex.com/us/item/5522/',
          'license':
              'Pearl Abyss-origin game facts; BDO Codex credited as a '
              'factual cross-check',
          'permittedUse':
              'The item identity and bare-hands-or-hoe gathering method were '
              'reviewed as factual acquisition guidance. No page media or '
              'map geometry is copied. Exact manual plant positions are not '
              'claimed or displayed.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _wildBeehiveProvenanceId,
          'title': 'Current Wild Beehive hunting and processing quest facts',
          'url': 'https://bdocodex.com/us/quest/9042/5/',
          'license':
              'Pearl Abyss-origin game facts; BDO Codex factual cross-check',
          'permittedUse':
              'Current quest text identifies matchlock hunting of beehives in '
              'Balenos Forest treetops. Quest 1001/79 confirms Grinding three '
              'Wild Beehives into Cooking Honey. The existing Balenos Forest '
              'node coordinate is a named area anchor, not an exact beehive '
              'spawn or an invented coverage circle.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': _citronProvenanceId,
          'title': 'BDO Codex Citron Tree and orchard acquisition facts',
          'url': 'https://bdocodex.com/us/npc/11989/',
          'license':
              'Pearl Abyss-origin game facts; BDO Codex credited as a '
              'factual cross-check',
          'permittedUse':
              'The Citron Tree identity, bare-hands gathering method, and '
              "Maslan's Yulas Citron Orchard location were cross-checked "
              'against the current Citron item, gatherable NPC, orchard '
              'worker-node, and daily-quest records. The map marker reuses '
              'the reviewed orchard node coordinate as a named location '
              'anchor. It is not represented as an individual tree spawn, '
              'coverage circle, or invented gathering route.',
          'attribution':
              'BDO Codex; Black Desert IP is owned by Pearl Abyss Corp.',
        },
        <String, Object?>{
          'id': 'pearl-abyss-fan-guidelines',
          'title': 'Pearl Abyss Fan Content Guidelines',
          'url':
              'https://blackdesert.pearlabyss.com/ASIA/en-us/'
              'Policy?_policyNo=42',
          'license': 'Pearl Abyss fan-content policy',
          'permittedUse':
              'Noncommercial unofficial fan content subject to the policy '
              'and third-party rights.',
          'attribution': 'Black Desert IP is owned by Pearl Abyss',
        },
      ],
    },
    'resources': resources,
    'workerNodes': workerNodes,
    'gatheringSpots': gatheringSpots,
    'gatheringPoints': gatheringPoints,
    'gatheringRoutes': <Object?>[],
    'fieldSources': fieldSources,
    'vendorNpcs': vendorNpcs,
    'vendorListings': vendorListings,
  };

  final outputPath =
      outputOverride ??
      '${Directory.current.path}${Platform.pathSeparator}'
          'assets${Platform.pathSeparator}data${Platform.pathSeparator}'
          'resource_map.json';
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  await output.writeAsString('${encoder.convert(result)}\n');
  stdout.writeln(
    'Generated ${output.path}\n'
    '${workerNodes.length} map nodes, ${resources.length} resources, '
    '${gatheringSpots.length} gathering focuses or areas, '
    '${gatheringPoints.length} deduplicated exact gathering points, '
    '${fieldSources.length} field sources, '
    '${vendorNpcs.length} exact vendor markers, '
    '${vendorListings.length} mapped vendor listings.',
  );
}

Future<Map<String, dynamic>?> _loadEdaniaSeed(List<String> arguments) async {
  final sourceOverride = _option(arguments, '--edania-seed');
  final source = File(
    sourceOverride ??
        'tool${Platform.pathSeparator}seeds'
            '${Platform.pathSeparator}edania_v4_seed.json',
  );
  final bytes = await source.readAsBytes();
  final actualDigest = sha256.convert(bytes).toString();
  if (actualDigest != _edaniaSeedSha256) {
    stderr.writeln(
      'Edania seed checksum mismatch.\n'
      'Expected: $_edaniaSeedSha256\n'
      'Actual:   $actualDigest',
    );
    exitCode = 2;
    return null;
  }

  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Edania seed must be a JSON object.');
  }
  if (_integer(decoded['schemaVersion']) != 1) {
    throw const FormatException('Edania seed schemaVersion must be 1.');
  }
  final review = decoded['sourceReview'];
  if (review is! Map<String, dynamic> ||
      review['extractorCommit'] != _edaniaExtractorCommit ||
      review['worldSha256'] != _edaniaWorldSha256 ||
      review['itemsSha256'] != _edaniaItemsSha256 ||
      review['clientRegion'] != 'NA') {
    throw const FormatException(
      'Edania seed source review does not match the pinned NA extract.',
    );
  }
  final gatheringSpots = _mapList(
    decoded['gatheringSpots'],
    'Edania gathering spots',
  );
  if (gatheringSpots.isNotEmpty) {
    throw FormatException(
      'Edania seed must not contain approximate gathering areas; '
      'found ${gatheringSpots.length}.',
    );
  }
  return decoded;
}

Future<Map<String, dynamic>?> _loadMarniSniperSeed(
  List<String> arguments,
) async {
  final sourceOverride = _option(arguments, '--marni-sniper-seed');
  final source = File(
    sourceOverride ??
        'tool${Platform.pathSeparator}seeds'
            '${Platform.pathSeparator}marni_sniper_hunting_2026_08_01_seed.json',
  );
  final bytes = await source.readAsBytes();
  final actualDigest = sha256.convert(bytes).toString();
  if (actualDigest != _marniSniperSeedSha256) {
    stderr.writeln(
      'Marni sniper seed checksum mismatch.\n'
      'Expected: $_marniSniperSeedSha256\n'
      'Actual:   $actualDigest',
    );
    exitCode = 2;
    return null;
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic> ||
      _integer(decoded['schemaVersion']) != 1 ||
      decoded['status'] != 'reviewedCurrentGuideFacts') {
    throw const FormatException(
      'Marni sniper seed must be a reviewed schema-v1 fact record.',
    );
  }
  final review = decoded['sourceReview'];
  if (review is! Map<String, dynamic> ||
      review['provider'] != 'Pearl Abyss' ||
      review['url'] !=
          'https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=74' ||
      review['retrievedAt'] != _marniSniperRetrievedAt ||
      review['rareRewardGuide'] !=
          'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=5387' ||
      review['locationAccuracy'] != 'regionAnchor' ||
      !_requiredString(
        review,
        'distributionBoundary',
      ).contains('no source media or traced spawn geometry')) {
    throw const FormatException(
      'Marni sniper source review does not match the pinned guide review.',
    );
  }
  final anchor = decoded['mapAnchor'];
  final spot = decoded['spot'];
  final sourceRecord = decoded['fieldSource'];
  if (anchor is! Map<String, dynamic> ||
      anchor['nodeId'] != '1797' ||
      anchor['nodeName'] != 'Beombawi Valley' ||
      _number(anchor['x']) != -1198000.0 ||
      _number(anchor['z']) != 1389200.0 ||
      spot is! Map<String, dynamic> ||
      spot['id'] != 'gathering:beombawi-marni-sniper-preserve' ||
      spot['nearestNode'] != anchor['nodeName'] ||
      sourceRecord is! Map<String, dynamic> ||
      sourceRecord['id'] != _marniSniperFieldSourceId) {
    throw const FormatException(
      'Marni sniper seed is not bound to the reviewed Beombawi anchor.',
    );
  }
  const expectedResources = <String>[
    'item:7905',
    'item:6205',
    'item:6005',
    'item:7912',
    'item:6213',
    'item:6013',
    'item:820039',
    'item:820038',
    'item:820037',
    'item:820036',
    'item:820139',
  ];
  if (!_sameStrings(
        _stringListFromSeed(spot['resourceIds'], 'Marni sniper resources'),
        expectedResources,
      ) ||
      _mapList(spot['targets'], 'Marni sniper targets').length != 4) {
    throw const FormatException(
      'Marni sniper target or product coverage changed.',
    );
  }
  return decoded;
}

Future<Map<String, dynamic>?> _loadCurrentNodeSeed(
  List<String> arguments,
) async {
  final sourceOverride = _option(arguments, '--current-node-seed');
  final source = File(
    sourceOverride ??
        'tool${Platform.pathSeparator}seeds'
            '${Platform.pathSeparator}'
            'bdocodex_worldmap_2026_08_15_private_seed.json',
  );
  final bytes = await source.readAsBytes();
  final actualDigest = sha256.convert(bytes).toString();
  if (actualDigest != _currentNodeSeedSha256) {
    stderr.writeln(
      'Current-node seed checksum mismatch.\n'
      'Expected: $_currentNodeSeedSha256\n'
      'Actual:   $actualDigest',
    );
    exitCode = 2;
    return null;
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic> ||
      _integer(decoded['schemaVersion']) != 1 ||
      decoded['status'] != 'privateNoncommercialCandidate') {
    throw const FormatException(
      'Current-node seed must be a schema-v1 private candidate.',
    );
  }
  final review = decoded['sourceReview'];
  if (review is! Map<String, dynamic> ||
      review['provider'] != 'BDO Codex' ||
      review['url'] != 'https://bdocodex.com/us/worldmap/' ||
      review['endpoint'] != 'https://bdocodex.com/ajax.php?l=us' ||
      review['locale'] != 'us' ||
      review['retrievedAt'] != _currentNodeSourceRetrievedAt ||
      review['reuseStatus'] != 'Unconfirmed' ||
      !_requiredString(
        review,
        'distributionBoundary',
      ).contains('do not publish or redistribute') ||
      _integer(review['rawLayerOneCount']) != 610 ||
      _integer(review['rawLayerZeroCount']) != 442 ||
      _integer(review['explorationLinkCount']) != 667 ||
      _integer(review['productionLinkCount']) != 426 ||
      _integer(review['unlinkedLayerZeroCount']) != 17 ||
      _integer(review['repairedMalformedProductionParentCount']) != 1 ||
      _integer(review['reviewedProductionParentCorrectionCount']) != 12 ||
      _integer(review['remainingUnlinkedLayerZeroCount']) != 5 ||
      _integer(review['ignoredMalformedExplorationSelfLinkCount']) != 1) {
    throw const FormatException(
      'Current-node source review does not match the pinned snapshot.',
    );
  }
  final transform = decoded['coordinateTransform'];
  if (transform is! Map<String, dynamic> ||
      transform['gameX'] != '(pixelX - 68600) * 25' ||
      transform['gameZ'] != '(72200 - pixelY) * 25') {
    throw const FormatException(
      'Current-node coordinate transform does not match map calibration.',
    );
  }
  final counts = decoded['counts'];
  if (counts is! Map<String, dynamic> ||
      _integer(counts['nodes']) != _currentNodeCount ||
      _integer(counts['exploration']) != _currentExplorationNodeCount ||
      _integer(counts['production']) != _currentProductionNodeCount ||
      _integer(counts['linkedProduction']) !=
          _currentLinkedProductionNodeCount ||
      _integer(counts['products']) != _currentNodeProductCount) {
    throw const FormatException('Current-node seed counts changed.');
  }
  final products = _mapList(decoded['products'], 'current-node products');
  final productIds = <int>{};
  for (final product in products) {
    final itemId = _integer(product['itemId']);
    if (itemId == null ||
        !_requiredString(product, 'name').trim().isNotEmpty ||
        !_requiredString(product, 'iconPath').endsWith('.webp') ||
        !productIds.add(itemId)) {
      throw FormatException('Invalid current-node product $itemId.');
    }
    const allowed = <String>{'itemId', 'name', 'iconPath'};
    if (product.keys.any((key) => !allowed.contains(key))) {
      throw FormatException(
        'Current-node product $itemId contains an unreviewed field.',
      );
    }
  }
  if (products.length != _currentNodeProductCount) {
    throw FormatException(
      'Expected $_currentNodeProductCount current-node products; '
      'found ${products.length}.',
    );
  }

  final rows = _mapList(decoded['nodes'], 'current nodes');
  final ids = <String>{};
  final rowsById = <String, Map<String, dynamic>>{};
  var productionCount = 0;
  for (final row in rows) {
    final numericId = _integer(row['id']);
    final id = numericId?.toString();
    final parentId = _integer(row['parentId'])?.toString();
    final pixelX = _number(row['pixelX']);
    final pixelY = _number(row['pixelY']);
    final iconType = _integer(row['iconType']);
    final sourceLayerFlag = _integer(row['sourceLayerFlag']);
    final isProductionNode = row['isProductionNode'];
    if (numericId == null ||
        id == null ||
        !ids.add(id) ||
        pixelX == null ||
        pixelY == null ||
        !pixelX.isFinite ||
        !pixelY.isFinite ||
        iconType == null ||
        (sourceLayerFlag != 0 && sourceLayerFlag != 1) ||
        isProductionNode is! bool ||
        _requiredString(row, 'name').trim().isEmpty ||
        _requiredString(row, 'rawName').trim().isEmpty ||
        _requiredString(row, 'nodeType').trim().isEmpty ||
        isProductionNode != (sourceLayerFlag == 0) ||
        parentId == id) {
      throw FormatException('Invalid current node $id.');
    }
    const allowed = <String>{
      'id',
      'name',
      'rawName',
      'nodeType',
      'iconType',
      'sourceLayerFlag',
      'pixelX',
      'pixelY',
      'contributionPoints',
      'linkIds',
      'outputs',
      'isProductionNode',
      'parentId',
    };
    if (row.keys.any((key) => !allowed.contains(key))) {
      throw FormatException('Current node $id contains an unreviewed field.');
    }
    rowsById[id] = row;
    if (isProductionNode) {
      productionCount += 1;
    }
  }
  if (rows.length != _currentNodeCount ||
      productionCount != _currentProductionNodeCount ||
      rows.where((row) => row['isProductionNode'] != true).length !=
          _currentExplorationNodeCount ||
      rows
              .where(
                (row) =>
                    row['isProductionNode'] == true && row['parentId'] != null,
              )
              .length !=
          _currentLinkedProductionNodeCount ||
      rows
              .where(
                (row) =>
                    row['isProductionNode'] == true && row['parentId'] == null,
              )
              .length !=
          5 ||
      !ids.containsAll(const <String>{
        '2030',
        '2053',
        '2060',
        '2068',
        '2079',
        '2084',
      })) {
    throw FormatException(
      'Current-node record boundary changed: ${rows.length} total, '
      '$productionCount production, max IDs ${ids.take(6).join(', ')}.',
    );
  }
  for (final row in rows) {
    final id = _integer(row['id'])!.toString();
    final links = _intListFromSeed(
      row['linkIds'],
      'links for node $id',
    ).map((value) => value.toString()).toSet();
    final parentId = _integer(row['parentId'])?.toString();
    if (links.any((linkId) => !rowsById.containsKey(linkId)) ||
        (parentId != null && !links.contains(parentId))) {
      throw FormatException('Current node $id has an unresolved link.');
    }
    for (final linkId in links) {
      final reverseLinks = _intListFromSeed(
        rowsById[linkId]!['linkIds'],
        'links for node $linkId',
      ).map((value) => value.toString());
      if (!reverseLinks.contains(id)) {
        throw FormatException('Current node link $id / $linkId is asymmetric.');
      }
    }
    for (final output in _mapList(
      row['outputs'],
      'outputs for current node $id',
    )) {
      final itemId = _integer(output['itemId']);
      if (itemId == null ||
          !productIds.contains(itemId) ||
          _requiredString(output, 'name').trim().isEmpty ||
          output['isPrimary'] is! bool) {
        throw FormatException(
          'Current node $id has an invalid output $itemId.',
        );
      }
    }
  }
  return decoded;
}

Future<Map<String, dynamic>?> _loadRusalkaSeed(List<String> arguments) async {
  final sourceOverride = _option(arguments, '--rusalka-seed');
  final source = File(
    sourceOverride ??
        'tool${Platform.pathSeparator}seeds'
            '${Platform.pathSeparator}'
            'rusalka_coral_bdocodex_2026_07_28_private_seed.json',
  );
  final bytes = await source.readAsBytes();
  final actualDigest = sha256.convert(bytes).toString();
  if (actualDigest != _rusalkaSeedSha256) {
    stderr.writeln(
      "Rusalka's Coral seed checksum mismatch.\n"
      'Expected: $_rusalkaSeedSha256\n'
      'Actual:   $actualDigest',
    );
    exitCode = 2;
    return null;
  }

  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException("Rusalka's Coral seed must be a JSON object.");
  }
  if (_integer(decoded['schemaVersion']) != 1 ||
      decoded['status'] != 'privateNoncommercialCandidate') {
    throw const FormatException(
      "Rusalka's Coral seed must be a schema-v1 private candidate.",
    );
  }
  final review = decoded['sourceReview'];
  if (review is! Map<String, dynamic> ||
      review['provider'] != 'BDO Codex' ||
      _integer(review['pageNpcId']) != 28115 ||
      review['url'] != _rusalkaSourceUrl ||
      review['retrievedAt'] != _rusalkaSourceRetrievedAt ||
      review['reuseStatus'] != 'Unconfirmed' ||
      !_requiredString(
        review,
        'distributionBoundary',
      ).contains('do not publish or redistribute')) {
    throw const FormatException(
      "Rusalka's Coral source review does not match the pinned "
      'private BDO Codex review.',
    );
  }
  final transform = decoded['coordinateTransform'];
  if (transform is! Map<String, dynamic> ||
      transform['gameX'] != '(pixelX - 68600) * 25' ||
      transform['gameZ'] != '(72200 - pixelY) * 25') {
    throw const FormatException(
      "Rusalka's Coral coordinate transform does not match the "
      'reviewed map calibration.',
    );
  }
  final resource = decoded['resource'];
  if (resource is! Map<String, dynamic> ||
      resource['id'] != 'item:821255' ||
      _integer(resource['gameItemId']) != 821255 ||
      resource['name'] != "Rusalka's Coral" ||
      !_sameStrings(
        _stringListFromSeed(
          resource['acquisitionModes'],
          "Rusalka's Coral acquisition modes",
        ),
        const <String>['fieldGathering'],
      )) {
    throw const FormatException(
      "Rusalka's Coral resource binding must be item 821255 in "
      'fieldGathering mode.',
    );
  }
  final metadata = decoded['pointMetadata'];
  if (metadata is! Map<String, dynamic> ||
      metadata['target'] != 'Coral Stoneback Crab' ||
      metadata['verification'] != 'communityReported' ||
      metadata['provenanceId'] != 'bdo-codex-rusalka-coral-points-private') {
    throw const FormatException(
      "Rusalka's Coral point metadata does not match the pinned source.",
    );
  }
  if (decoded.containsKey('gatheringSpots') ||
      decoded.containsKey('radiusWorld')) {
    throw const FormatException(
      "Rusalka's Coral seed must contain exact points only.",
    );
  }
  final points = _mapList(decoded['points'], "Rusalka's Coral points");
  final recordIds = <int>{};
  if (points.length != 34) {
    throw FormatException(
      "Rusalka's Coral seed must contain exactly 34 points; "
      'found ${points.length}.',
    );
  }
  for (var index = 0; index < points.length; index += 1) {
    final point = points[index];
    final recordId = _integer(point['sourceNpcRecordId']);
    final pixelX = _number(point['pixelX']);
    final pixelY = _number(point['pixelY']);
    if (recordId == null ||
        !recordIds.add(recordId) ||
        pixelX == null ||
        pixelY == null ||
        !pixelX.isFinite ||
        !pixelY.isFinite) {
      throw FormatException(
        "Rusalka's Coral point $index has invalid source coordinates.",
      );
    }
  }
  return decoded;
}

Future<Map<String, dynamic>?> _loadStillcoralSeed(
  List<String> arguments,
) async {
  final sourceOverride = _option(arguments, '--stillcoral-seed');
  final source = File(
    sourceOverride ??
        'tool${Platform.pathSeparator}seeds'
            '${Platform.pathSeparator}'
            'stillcoral_coastal_gathering_bdocodex_2026_08_01_private_seed.json',
  );
  final bytes = await source.readAsBytes();
  final actualDigest = sha256.convert(bytes).toString();
  if (actualDigest != _stillcoralSeedSha256) {
    stderr.writeln(
      'Stillcoral coastal seed checksum mismatch.\n'
      'Expected: $_stillcoralSeedSha256\n'
      'Actual:   $actualDigest',
    );
    exitCode = 2;
    return null;
  }

  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic> ||
      _integer(decoded['schemaVersion']) != 1 ||
      decoded['status'] != 'privateNoncommercialCandidate' ||
      decoded['seedKind'] != 'reviewedPointSubset' ||
      decoded['verification'] != 'sourceRecordedNotYetVerifiedInGame') {
    throw const FormatException(
      'Stillcoral seed must be the reviewed schema-v1 private point subset.',
    );
  }
  final review = decoded['sourceReview'];
  if (review is! Map<String, dynamic> ||
      review['provider'] != 'BDO Codex' ||
      review['retrievedAt'] != _stillcoralSourceRetrievedAt ||
      review['reuseStatus'] != 'Unconfirmed' ||
      !_requiredString(
        review,
        'distributionBoundary',
      ).contains('do not publish or redistribute')) {
    throw const FormatException(
      'Stillcoral source review does not match the pinned private review.',
    );
  }
  final transform = decoded['coordinateTransform'];
  if (transform is! Map<String, dynamic> ||
      transform['gameX'] != '(pixelX - 68600) * 25' ||
      transform['gameZ'] != '(72200 - pixelY) * 25') {
    throw const FormatException(
      'Stillcoral coordinates do not use the reviewed map calibration.',
    );
  }
  if (!_sameStrings(
    _stringListFromSeed(
      decoded['pointTupleSchema'],
      'Stillcoral point tuple schema',
    ),
    const <String>['sourceOrdinalZeroBased', 'pixelX', 'pixelY'],
  )) {
    throw const FormatException('Stillcoral point tuple schema changed.');
  }
  final selection = decoded['selection'];
  final center = selection is Map<String, dynamic> ? selection['center'] : null;
  if (selection is! Map<String, dynamic> ||
      selection['coordinateSpace'] !=
          'BDO Codex maximum-zoom world-map pixel coordinates' ||
      center is! Map<String, dynamic> ||
      _number(center['pixelX']) != 88119.647 ||
      _number(center['pixelY']) != 44693.294 ||
      _number(selection['radiusPixels']) != 1000.0 ||
      !_requiredString(
        selection,
        'description',
      ).contains('not a claimed route')) {
    throw const FormatException(
      'Stillcoral selection must remain the fixed, route-free review window.',
    );
  }
  if (decoded.containsKey('gatheringRoutes') ||
      decoded.containsKey('route') ||
      decoded.containsKey('pathOrder')) {
    throw const FormatException(
      'Stillcoral seed must contain exact points only, never a route.',
    );
  }

  const expectedTargets =
      <int, ({String name, int count, List<int> productIds})>{
        10924: (
          name: 'Rainbow Coral',
          count: 105,
          productIds: <int>[4476, 4477, 4998, 6501, 6511, 55881],
        ),
        10967: (
          name: 'Oyster',
          count: 66,
          productIds: <int>[4998, 6515, 55880],
        ),
        10913: (
          name: 'Giant Pearl Clam',
          count: 6,
          productIds: <int>[4998, 6509, 6511, 6516, 8246, 55883],
        ),
        10951: (
          name: 'Sea Fan',
          count: 21,
          productIds: <int>[4476, 4477, 4998, 6501, 6504, 6511, 55881],
        ),
      };
  final expectedProductNames = <int, String>{
    ..._stillcoralUsefulProducts,
    ..._stillcoralTradeProducts,
  };
  final targets = _mapList(decoded['targets'], 'Stillcoral targets');
  final seenTargetIds = <int>{};
  var totalPoints = 0;
  for (final target in targets) {
    final targetId = _integer(target['targetId']);
    final expected = targetId == null ? null : expectedTargets[targetId];
    if (targetId == null ||
        expected == null ||
        !seenTargetIds.add(targetId) ||
        target['name'] != expected.name ||
        target['kind'] != 'gatherable object' ||
        target['tool'] != 'Hoe' ||
        target['sourceUrl'] !=
            'https://bdocodex.com/us/gatherable/$targetId/' ||
        target['productsUrl'] !=
            'https://bdocodex.com/query.php?a=drop&type=gatherableproducts&id=$targetId&l=us') {
      throw FormatException(
        'Stillcoral target ${target['targetId']} changed from review.',
      );
    }

    final rawProducts = target['products'];
    if (rawProducts is! List<dynamic>) {
      throw FormatException('Stillcoral ${expected.name} products changed.');
    }
    final productIds = <int>[];
    for (final rawProduct in rawProducts) {
      if (rawProduct is! List<dynamic> || rawProduct.length != 2) {
        throw FormatException('Stillcoral ${expected.name} product changed.');
      }
      final itemId = _integer(rawProduct[0]);
      if (itemId == null ||
          expectedProductNames[itemId] != rawProduct[1] ||
          productIds.contains(itemId)) {
        throw FormatException('Stillcoral ${expected.name} product changed.');
      }
      productIds.add(itemId);
    }
    if (!_sameStrings(
      productIds.map((itemId) => itemId.toString()).toList(growable: false),
      expected.productIds
          .map((itemId) => itemId.toString())
          .toList(growable: false),
    )) {
      throw FormatException(
        'Stillcoral ${expected.name} product coverage changed.',
      );
    }

    final rawPoints = target['points'];
    if (rawPoints is! List<dynamic> || rawPoints.length != expected.count) {
      throw FormatException(
        'Stillcoral ${expected.name} must contain ${expected.count} points.',
      );
    }
    final ordinals = <int>{};
    final coordinates = <String>{};
    for (var index = 0; index < rawPoints.length; index += 1) {
      final rawPoint = rawPoints[index];
      if (rawPoint is! List<dynamic> || rawPoint.length != 3) {
        throw FormatException(
          'Stillcoral ${expected.name} point $index is not a tuple.',
        );
      }
      final ordinal = _integer(rawPoint[0]);
      final pixelX = _number(rawPoint[1]);
      final pixelY = _number(rawPoint[2]);
      if (ordinal == null ||
          ordinal < 0 ||
          !ordinals.add(ordinal) ||
          pixelX == null ||
          pixelY == null ||
          !pixelX.isFinite ||
          !pixelY.isFinite ||
          !coordinates.add('$pixelX,$pixelY')) {
        throw FormatException(
          'Stillcoral ${expected.name} point $index is invalid.',
        );
      }
      final dx = pixelX - 88119.647;
      final dy = pixelY - 44693.294;
      if ((dx * dx) + (dy * dy) > 1000000.000001) {
        throw FormatException(
          'Stillcoral ${expected.name} point $index is outside the review '
          'window.',
        );
      }
    }
    totalPoints += rawPoints.length;
  }
  if (seenTargetIds.length != expectedTargets.length || totalPoints != 198) {
    throw const FormatException(
      'Stillcoral target boundary must remain four sources and 198 points.',
    );
  }
  final counts = decoded['counts'];
  if (counts is! Map<String, dynamic> ||
      _integer(counts['Rainbow Coral']) != 105 ||
      _integer(counts['Oyster']) != 66 ||
      _integer(counts['Giant Pearl Clam']) != 6 ||
      _integer(counts['Sea Fan']) != 21 ||
      _integer(counts['total']) != 198) {
    throw const FormatException('Stillcoral reviewed counts changed.');
  }
  return decoded;
}

Future<Map<String, dynamic>?> _loadVendorSeed(List<String> arguments) async {
  final sourceOverride = _option(arguments, '--vendor-seed');
  final source = File(
    sourceOverride ??
        'tool${Platform.pathSeparator}seeds'
            '${Platform.pathSeparator}'
            'vendor_npcs_bdocodex_2026_08_15_private_seed.json',
  );
  final bytes = await source.readAsBytes();
  final actualDigest = sha256.convert(bytes).toString();
  if (actualDigest != _vendorSeedSha256) {
    stderr.writeln(
      'Vendor seed checksum mismatch.\n'
      'Expected: $_vendorSeedSha256\n'
      'Actual:   $actualDigest',
    );
    exitCode = 2;
    return null;
  }

  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic> ||
      _integer(decoded['schemaVersion']) != 1 ||
      decoded['status'] != 'privateNoncommercialCandidate') {
    throw const FormatException(
      'Vendor seed must be the reviewed schema-v1 private candidate.',
    );
  }
  final review = decoded['sourceReview'];
  if (review is! Map<String, dynamic> ||
      review['provider'] != 'BDO Codex' ||
      review['retrievedAt'] != _vendorSourceRetrievedAt ||
      review['reuseStatus'] != 'Unconfirmed' ||
      !_requiredString(
        review,
        'distributionBoundary',
      ).contains('do not publish or redistribute') ||
      !_requiredString(
        review,
        'portraitPolicy',
      ).contains('checksum-pinned local portrait bundle') ||
      !_requiredString(review, 'portraitPolicy').contains('never hotlinks') ||
      _integer(review['itemCount']) != _vendorItemCount ||
      _integer(review['listingCount']) != _vendorSeedListingCount ||
      _integer(review['vendorSpawnCount']) != _vendorSpawnCount ||
      _integer(review['mappedVendorSpawnCount']) != _mappedVendorSpawnCount ||
      _integer(review['exactLocationCount']) != _vendorLocationCount ||
      _integer(review['unmappedVendorSpawnCount']) !=
          _unmappedVendorSpawnCount) {
    throw const FormatException(
      'Vendor source review does not match the pinned private snapshot.',
    );
  }
  final transform = decoded['coordinateTransform'];
  if (transform is! Map<String, dynamic> ||
      transform['gameX'] != '(pixelX - 68600) * 25' ||
      transform['gameZ'] != '(72200 - pixelY) * 25') {
    throw const FormatException(
      'Vendor coordinates do not use the reviewed map calibration.',
    );
  }

  final items = _mapList(decoded['items'], 'Vendor items');
  if (items.length != _vendorItemCount) {
    throw FormatException('Vendor item count changed: ${items.length}.');
  }
  final itemIds = <int>{};
  final itemNames = <String>{};
  final itemNamesById = <int, String>{};
  final pricesByItemId = <int, int>{};
  for (final item in items) {
    final itemId = _integer(item['itemId']);
    final name = item['name'];
    final price = _integer(item['priceSilver']);
    if (itemId == null ||
        itemId <= 0 ||
        !itemIds.add(itemId) ||
        name is! String ||
        name.trim().isEmpty ||
        !itemNames.add(name.trim().toLowerCase()) ||
        item['itemPageUrl'] != 'https://bdocodex.com/us/item/$itemId/' ||
        price == null ||
        price < 0) {
      throw FormatException('Invalid vendor item ${item['name']}.');
    }
    itemNamesById[itemId] = name.trim();
    pricesByItemId[itemId] = price;
  }

  final vendors = _mapList(decoded['vendors'], 'Vendor NPCs');
  if (vendors.length != _vendorSpawnCount) {
    throw FormatException('Vendor spawn count changed: ${vendors.length}.');
  }
  final vendorIds = <String>{};
  final mappedVendorIds = <String>{};
  final portraitPathPattern = RegExp(
    r'^/items/ui_artwork/(?:ic_[a-z0-9_]+|collected_study)\.webp$',
  );
  var locationCount = 0;
  for (final vendor in vendors) {
    final vendorId = vendor['vendorId'];
    final npcId = _integer(vendor['gameNpcId']);
    final spawnId = _integer(vendor['spawnId']);
    final name = vendor['name'];
    final role = vendor['role'];
    final portraitPath = vendor['sourcePortraitPath'];
    if (vendorId is! String ||
        vendorId != 'npc:$npcId:$spawnId' ||
        !vendorIds.add(vendorId) ||
        npcId == null ||
        npcId <= 0 ||
        spawnId == null ||
        spawnId < 0 ||
        name is! String ||
        name.trim().isEmpty ||
        role is! String ||
        role.trim().isEmpty ||
        portraitPath is! String ||
        !portraitPathPattern.hasMatch(portraitPath) ||
        vendor['sourceUrl'] != 'https://bdocodex.com/us/npc/$npcId/$spawnId/') {
      throw FormatException('Invalid vendor identity $vendorId.');
    }
    final locations = _mapList(
      vendor['locations'],
      'Vendor $vendorId locations',
    );
    final locationIndexes = <int>{};
    for (final location in locations) {
      final index = _integer(location['index']);
      final pixelX = _number(location['pixelX']);
      final pixelY = _number(location['pixelY']);
      final x = _number(location['x']);
      final z = _number(location['z']);
      if (index == null ||
          index < 0 ||
          !locationIndexes.add(index) ||
          pixelX == null ||
          pixelY == null ||
          x == null ||
          z == null ||
          !pixelX.isFinite ||
          !pixelY.isFinite ||
          !x.isFinite ||
          !z.isFinite ||
          (x - ((pixelX - _bdoCodexPixelOriginX) * _bdoCodexPixelScale)).abs() >
              0.001 ||
          (z - ((_bdoCodexPixelOriginY - pixelY) * _bdoCodexPixelScale)).abs() >
              0.001) {
        throw FormatException(
          'Invalid exact vendor location $vendorId:$index.',
        );
      }
      locationCount += 1;
    }
    if (locations.isNotEmpty) {
      mappedVendorIds.add(vendorId);
    }
  }
  if (mappedVendorIds.length != _mappedVendorSpawnCount ||
      locationCount != _vendorLocationCount) {
    throw FormatException(
      'Mapped vendor boundary changed: ${mappedVendorIds.length} spawns, '
      '$locationCount locations.',
    );
  }

  final listings = _mapList(decoded['listings'], 'Vendor listings');
  if (listings.length != _vendorSeedListingCount) {
    throw FormatException('Vendor listing count changed: ${listings.length}.');
  }
  final listingKeys = <String>{};
  for (final listing in listings) {
    final itemId = _integer(listing['itemId']);
    final itemName = listing['itemName'];
    final vendorId = listing['vendorId'];
    final price = _integer(listing['priceSilver']);
    if (itemId == null ||
        !itemIds.contains(itemId) ||
        itemName is! String ||
        itemName.trim() != itemNamesById[itemId] ||
        vendorId is! String ||
        !vendorIds.contains(vendorId) ||
        price != pricesByItemId[itemId] ||
        !listingKeys.add('$itemId:$vendorId') ||
        listing['sellerQueryUrl'] !=
            'https://bdocodex.com/query.php?a=npcs&'
                'type=sellspecialitems&item_id=$itemId&l=us') {
      throw FormatException('Invalid vendor listing $itemId -> $vendorId.');
    }
  }
  final unmapped = _mapList(decoded['unmappedVendors'], 'Unmapped vendors');
  if (unmapped.length != _unmappedVendorSpawnCount ||
      unmapped.any(
        (vendor) =>
            vendor['vendorId'] is! String ||
            mappedVendorIds.contains(vendor['vendorId']) ||
            !vendorIds.contains(vendor['vendorId']) ||
            !_requiredString(vendor, 'reason').contains('No exact location'),
      )) {
    throw const FormatException(
      'Unmapped vendor records do not match the fail-closed boundary.',
    );
  }
  return decoded;
}

List<Map<String, Object?>> _buildVendorNpcs(Map<String, dynamic> seed) {
  _validateVendorCurationBoundary(seed);
  final result = <Map<String, Object?>>[];
  for (final vendor in _mapList(seed['vendors'], 'Vendor NPCs')) {
    final sourceVendorId = vendor['vendorId']! as String;
    if (_vendorInteractionObjectNames.containsKey(sourceVendorId) ||
        _canonicalVendorSourceAliases.containsKey(sourceVendorId)) {
      continue;
    }
    final locations = _mapList(
      vendor['locations'],
      'Vendor $sourceVendorId locations',
    );
    for (final location in locations) {
      final index = _integer(location['index'])!;
      if (_excludedVendorLocationIndexes[sourceVendorId]?.contains(index) ??
          false) {
        continue;
      }
      result.add(<String, Object?>{
        'id': '$sourceVendorId:location:$index',
        'sourceVendorId': sourceVendorId,
        'gameNpcId': _integer(vendor['gameNpcId']),
        'spawnId': _integer(vendor['spawnId']),
        'name': vendor['name'],
        'role': vendor['role'],
        'x': _number(location['x']),
        'z': _number(location['z']),
        'sourceUrl': vendor['sourceUrl'],
        'reviewedAt': _vendorSourceRetrievedAt,
        'verification': 'sourceRecordedNotYetVerifiedInGame',
        'provenanceId': _vendorProvenanceId,
      });
    }
  }
  result.sort((left, right) {
    final byName = (left['name']! as String).compareTo(
      right['name']! as String,
    );
    return byName != 0
        ? byName
        : (left['id']! as String).compareTo(right['id']! as String);
  });
  if (result.length != _curatedVendorLocationCount ||
      result.map((vendor) => vendor['id']).toSet().length != result.length) {
    throw StateError(
      'Expected $_curatedVendorLocationCount curated NPC vendor markers; '
      'found ${result.length}.',
    );
  }
  return result;
}

void _validateVendorCurationBoundary(Map<String, dynamic> seed) {
  final vendorsById = <String, Map<String, dynamic>>{
    for (final vendor in _mapList(seed['vendors'], 'Vendor NPCs'))
      vendor['vendorId']! as String: vendor,
  };
  for (final entry in _vendorInteractionObjectNames.entries) {
    final vendor = vendorsById[entry.key];
    if (vendor == null ||
        vendor['name'] != entry.value ||
        _mapList(vendor['locations'], 'Vendor ${entry.key} locations').length !=
            1) {
      throw FormatException(
        'Reviewed interaction-object boundary changed for ${entry.key}.',
      );
    }
  }
  for (final entry in _reviewedVendorLocationCoordinates.entries) {
    final vendor = vendorsById[entry.key];
    final locations = vendor == null
        ? const <Map<String, dynamic>>[]
        : _mapList(vendor['locations'], 'Vendor ${entry.key} locations');
    if (locations.length != entry.value.length) {
      throw FormatException(
        'Reviewed vendor-coordinate boundary changed for ${entry.key}.',
      );
    }
    for (var index = 0; index < entry.value.length; index++) {
      final location = locations[index];
      final expected = entry.value[index];
      final actualX = (location['x']! as num).toDouble();
      final actualZ = (location['z']! as num).toDouble();
      if (_integer(location['index']) != index ||
          actualX != expected.$1 ||
          actualZ != expected.$2) {
        throw FormatException(
          'Reviewed vendor-coordinate boundary changed for '
          '${entry.key}:$index.',
        );
      }
    }
  }
  for (final entry in _canonicalVendorSourceAliases.entries) {
    final duplicate = vendorsById[entry.key];
    final canonical = vendorsById[entry.value];
    if (duplicate == null ||
        canonical == null ||
        duplicate['name'] != canonical['name'] ||
        duplicate['role'] != canonical['role'] ||
        _mapList(
              duplicate['locations'],
              'Vendor ${entry.key} locations',
            ).length !=
            1 ||
        _mapList(
              canonical['locations'],
              'Vendor ${entry.value} locations',
            ).length !=
            1) {
      throw FormatException(
        'Reviewed duplicate-vendor boundary changed for ${entry.key}.',
      );
    }
  }
  for (final entry in _excludedVendorLocationIndexes.entries) {
    final vendor = vendorsById[entry.key];
    final locations = vendor == null
        ? const <Map<String, dynamic>>[]
        : _mapList(vendor['locations'], 'Vendor ${entry.key} locations');
    final indexes = locations
        .map((location) => _integer(location['index']))
        .toSet();
    if (vendor == null || !indexes.containsAll(entry.value)) {
      throw FormatException(
        'Reviewed duplicate-location boundary changed for ${entry.key}.',
      );
    }
  }
}

List<Map<String, Object?>> _buildVendorListings(
  Map<String, dynamic> seed,
  List<Map<String, Object?>> vendorNpcs,
) {
  final markerIdsBySourceVendorId = <String, List<String>>{};
  for (final vendor in vendorNpcs) {
    (markerIdsBySourceVendorId[vendor['sourceVendorId']! as String] ??=
            <String>[])
        .add(vendor['id']! as String);
  }
  for (final entry in _canonicalVendorSourceAliases.entries) {
    final canonicalMarkerIds = markerIdsBySourceVendorId[entry.value];
    if (canonicalMarkerIds == null || canonicalMarkerIds.isEmpty) {
      throw StateError(
        'Canonical vendor ${entry.value} has no mapped NPC location.',
      );
    }
    markerIdsBySourceVendorId[entry.key] = canonicalMarkerIds;
  }
  final result = <Map<String, Object?>>[];
  final listingKeys = <String>{};
  for (final listing in _mapList(seed['listings'], 'Vendor listings')) {
    final markerIds =
        markerIdsBySourceVendorId[listing['vendorId']] ?? const <String>[];
    for (final markerId in markerIds) {
      final listingKey = '${_integer(listing['itemId'])}:$markerId';
      if (!listingKeys.add(listingKey)) {
        continue;
      }
      result.add(<String, Object?>{
        'itemId': _integer(listing['itemId']),
        'itemName': listing['itemName'],
        'vendorId': markerId,
        'priceSilver': _integer(listing['priceSilver']),
        'provenanceId': _vendorProvenanceId,
      });
    }
  }
  result.sort((left, right) {
    final byItem = (left['itemName']! as String).compareTo(
      right['itemName']! as String,
    );
    return byItem != 0
        ? byItem
        : (left['vendorId']! as String).compareTo(right['vendorId']! as String);
  });
  if (result.length != _mappedVendorListingCount) {
    throw StateError(
      'Expected $_mappedVendorListingCount mapped vendor listings; '
      'found ${result.length}.',
    );
  }
  return result;
}

Future<List<_BdoCodexNpcPointPayload>?> _loadDrieghanAnimalPointSources(
  List<String> arguments,
) async {
  final payloads = <_BdoCodexNpcPointPayload>[];
  final locationBlockPattern = RegExp(
    r'var locations = \[(.*?)\];',
    dotAll: true,
  );
  final pointPattern = RegExp(r'\[\[(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\]');

  for (final source in _drieghanAnimalPointSources) {
    final override = _option(arguments, source.overrideOption);
    final bytes = override == null
        ? await _download(source.uri)
        : await File(override).readAsBytes();
    final html = utf8.decode(bytes, allowMalformed: true);
    final locationBlock = locationBlockPattern.firstMatch(html);
    if (locationBlock == null) {
      throw FormatException(
        '${source.pageTitle} page does not contain a BDO Codex '
        'location array.',
      );
    }

    final points = pointPattern
        .allMatches(locationBlock.group(1)!)
        .map(
          (match) => _BdoCodexPixelPoint(
            rawX: match.group(1)!,
            rawY: match.group(2)!,
            pixelX: double.parse(match.group(1)!),
            pixelY: double.parse(match.group(2)!),
          ),
        )
        .toList(growable: false);
    final normalized = '${points.map((point) => point.canonical).join('\n')}\n';
    final actualDigest = sha256.convert(utf8.encode(normalized)).toString();
    if (points.length != source.expectedPointCount ||
        actualDigest != source.normalizedSha256) {
      stderr.writeln(
        '${source.pageTitle} normalized coordinate payload did not match.\n'
        'Expected: ${source.expectedPointCount} points, '
        '${source.normalizedSha256}\n'
        'Actual:   ${points.length} points, $actualDigest',
      );
      exitCode = 2;
      return null;
    }
    payloads.add(_BdoCodexNpcPointPayload(source: source, points: points));
  }
  return payloads;
}

void _addCurrentNodeResources(
  Map<String, Map<String, Object?>> resourcesById,
  Map<String, dynamic> seed,
) {
  for (final raw in _mapList(seed['products'], 'current-node products')) {
    final gameItemId = _integer(raw['itemId'])!;
    final resourceId = 'item:$gameItemId';
    final name = _requiredString(raw, 'name');
    final existing = resourcesById[resourceId];
    if (existing != null &&
        (existing['gameItemId'] != gameItemId || existing['name'] != name)) {
      throw FormatException(
        'Current-node product $resourceId conflicts with an existing item.',
      );
    }
    resourcesById[resourceId] = <String, Object?>{
      'id': resourceId,
      'gameItemId': gameItemId,
      'name': name,
      'category': _categoryFor(name),
      'aliases': _workerResourceAliases(gameItemId),
      'acquisitionModes': <String>['workerNode'],
    };
  }
}

List<String> _workerResourceAliases(int gameItemId) => switch (gameItemId) {
  5522 => <String>['kamasylvia flower', 'vedelona flower'],
  _ => <String>[],
};

List<Map<String, Object?>> _buildCurrentWorkerNodes(
  Map<String, dynamic> seed,
  Map<String, Map<String, Object?>> resourcesById,
) {
  final result = <Map<String, Object?>>[];
  for (final raw in _mapList(seed['nodes'], 'current nodes')) {
    final id = _integer(raw['id'])!.toString();
    final nodeType = _requiredString(raw, 'nodeType');
    final pixelX = _number(raw['pixelX'])!;
    final pixelY = _number(raw['pixelY'])!;
    final outputs = <Map<String, Object?>>[];
    for (final output in _mapList(raw['outputs'], 'outputs for node $id')) {
      final gameItemId = _integer(output['itemId'])!;
      final resourceId = 'item:$gameItemId';
      final resource = resourcesById[resourceId];
      if (resource == null) {
        throw FormatException(
          'Current node $id references unknown resource $resourceId.',
        );
      }
      outputs.add(<String, Object?>{
        'resourceId': resourceId,
        'gameItemId': gameItemId,
        'name': resource['name'],
        'isPrimary': output['isPrimary'] as bool,
      });
    }
    final isResourceNode =
        outputs.isNotEmpty && _currentResourceNodeTypes.contains(nodeType);
    result.add(<String, Object?>{
      'id': id,
      'name': _requiredString(raw, 'name'),
      'nodeType': nodeType,
      'region': '',
      'x': (pixelX - 68600) * 25,
      'z': (72200 - pixelY) * 25,
      'contributionPoints': _integer(raw['contributionPoints']) ?? 0,
      'linkIds': _intListFromSeed(
        raw['linkIds'],
        'links for node $id',
      ).map((value) => value.toString()).toList(growable: false),
      'outputs': outputs,
      'isResourceNode': isResourceNode,
      'isProductionNode': raw['isProductionNode'] as bool,
      'sourceIconType': _integer(raw['iconType']),
      'sourceLayerFlag': _integer(raw['sourceLayerFlag']),
      if (raw['parentId'] != null)
        'parentId': _integer(raw['parentId'])!.toString(),
      'provenanceId': _currentNodeProvenanceId,
    });
  }
  if (result.length != _currentNodeCount ||
      result.where((node) => node['isProductionNode'] == true).length !=
          _currentProductionNodeCount ||
      result.map((node) => node['id']).toSet().length != result.length ||
      result.any((node) => (node['id'] as String).startsWith('client:'))) {
    throw const FormatException(
      'Current worker-node build did not preserve the pinned node boundary.',
    );
  }
  return result;
}

void _addEdaniaResources(
  Map<String, Map<String, Object?>> resourcesById,
  Map<String, dynamic> seed,
) {
  for (final raw in _mapList(seed['resources'], 'Edania resources')) {
    final resourceId = _requiredString(raw, 'id');
    final gameItemId = _integer(raw['gameItemId']);
    final name = _requiredString(raw, 'name');
    if (gameItemId == null || resourceId != 'item:$gameItemId') {
      throw FormatException(
        'Edania resource $resourceId has an invalid game item ID.',
      );
    }
    final aliases = _stringListFromSeed(
      raw['aliases'],
      'aliases for $resourceId',
    );
    final acquisitionModes = _canonicalAcquisitionModes(
      _stringListFromSeed(
        raw['acquisitionModes'],
        'acquisition modes for $resourceId',
      ),
    );
    final existing = resourcesById[resourceId];
    if (existing == null) {
      resourcesById[resourceId] = <String, Object?>{
        'id': resourceId,
        'gameItemId': gameItemId,
        'name': name,
        'category': _requiredString(raw, 'category'),
        'aliases': aliases,
        'acquisitionModes': acquisitionModes,
      };
      continue;
    }
    if (existing['gameItemId'] != gameItemId) {
      throw FormatException(
        'Edania resource $resourceId conflicts with the historical seed.',
      );
    }
    existing['name'] = name;
    existing['category'] = _requiredString(raw, 'category');
    existing['aliases'] = (<String>{
      ...(existing['aliases'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      ...aliases,
    }.toList()..sort());
    existing['acquisitionModes'] = _canonicalAcquisitionModes(<String>[
      ...(existing['acquisitionModes'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      ...acquisitionModes,
    ]);
  }
}

void _addRusalkaResource(
  Map<String, Map<String, Object?>> resourcesById,
  Map<String, dynamic> seed,
) {
  final raw = seed['resource']! as Map<String, dynamic>;
  final resourceId = _requiredString(raw, 'id');
  final gameItemId = _integer(raw['gameItemId'])!;
  final name = _requiredString(raw, 'name');
  final category = _requiredString(raw, 'category');
  final aliases = _stringListFromSeed(
    raw['aliases'],
    "aliases for Rusalka's Coral",
  );
  final acquisitionModes = _canonicalAcquisitionModes(
    _stringListFromSeed(
      raw['acquisitionModes'],
      "acquisition modes for Rusalka's Coral",
    ),
  );
  final existing = resourcesById[resourceId];
  if (existing == null ||
      existing['gameItemId'] != gameItemId ||
      existing['name'] != name) {
    throw const FormatException(
      "Rusalka's Coral seed conflicts with the reviewed Edania resource.",
    );
  }
  existing['category'] = category;
  existing['aliases'] = (<String>{
    ...(existing['aliases'] as List<Object?>? ?? const <Object?>[])
        .cast<String>(),
    ...aliases,
  }.toList()..sort());
  existing['acquisitionModes'] = acquisitionModes;
}

void _addStillcoralResources(
  Map<String, Map<String, Object?>> resourcesById,
  Map<String, dynamic> seed,
) {
  const definitions =
      <({int itemId, String name, String category, List<String> aliases})>[
        (
          itemId: 4476,
          name: 'Red Coral',
          category: 'Marine material',
          aliases: <String>['rainbow coral red coral', 'sea fan red coral'],
        ),
        (
          itemId: 4477,
          name: 'Blue Coral',
          category: 'Marine material',
          aliases: <String>['rainbow coral blue coral', 'sea fan blue coral'],
        ),
        (
          itemId: 4998,
          name: 'Sharp Black Crystal Shard',
          category: 'Ore & minerals',
          aliases: <String>['sharp shard', 'sharp black shard'],
        ),
        (
          itemId: 6501,
          name: 'Coral Piece',
          category: 'Marine material',
          aliases: <String>['coral fragment'],
        ),
        (
          itemId: 6504,
          name: 'Green Coral',
          category: 'Marine material',
          aliases: <String>['sea fan green coral'],
        ),
        (
          itemId: 6509,
          name: 'Giant Pearl Clam',
          category: 'Seafood',
          aliases: <String>['pearl clam'],
        ),
        (
          itemId: 6511,
          name: 'Lobster',
          category: 'Seafood',
          aliases: <String>['coastal lobster'],
        ),
        (
          itemId: 6515,
          name: 'Oyster',
          category: 'Seafood',
          aliases: <String>['stillcoral oyster'],
        ),
        (
          itemId: 6516,
          name: 'Shrimp',
          category: 'Seafood',
          aliases: <String>['coastal shrimp'],
        ),
        (
          itemId: 8246,
          name: 'Crawfish',
          category: 'Seafood',
          aliases: <String>['crayfish', 'coastal crawfish'],
        ),
      ];
  final usefulSeedProducts = <int>{};
  for (final target in _mapList(seed['targets'], 'Stillcoral targets')) {
    for (final rawProduct in target['products']! as List<dynamic>) {
      final tuple = rawProduct! as List<dynamic>;
      final itemId = _integer(tuple.first)!;
      if (_stillcoralUsefulProducts.containsKey(itemId)) {
        usefulSeedProducts.add(itemId);
      }
    }
  }
  if (usefulSeedProducts.length != _stillcoralUsefulProducts.length ||
      !usefulSeedProducts.containsAll(_stillcoralUsefulProducts.keys)) {
    throw const FormatException(
      'Stillcoral useful product boundary changed after seed validation.',
    );
  }

  for (final definition in definitions) {
    final resourceId = 'item:${definition.itemId}';
    final existing = resourcesById[resourceId];
    if (existing == null) {
      resourcesById[resourceId] = <String, Object?>{
        'id': resourceId,
        'gameItemId': definition.itemId,
        'name': definition.name,
        'category': definition.category,
        'aliases': definition.aliases,
        'acquisitionModes': <String>['fieldGathering'],
      };
      continue;
    }
    if (existing['gameItemId'] != definition.itemId ||
        existing['name'] != definition.name) {
      throw FormatException(
        'Stillcoral resource $resourceId conflicts with the current node '
        'snapshot.',
      );
    }
    existing['category'] = definition.category;
    existing['aliases'] = (<String>{
      ...(existing['aliases'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      ...definition.aliases,
    }.toList()..sort());
    existing['acquisitionModes'] = _canonicalAcquisitionModes(<String>[
      ...(existing['acquisitionModes'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      'fieldGathering',
    ]);
  }
}

void _addCoralStonebackCrabResourceModes(
  Map<String, Map<String, Object?>> resourcesById,
) {
  for (final entry in _coralStonebackCrabNormalProducts.entries) {
    final resourceId = 'item:${entry.key}';
    final resource = resourcesById[resourceId];
    if (resource == null ||
        resource['gameItemId'] != entry.key ||
        resource['name'] != entry.value) {
      throw StateError(
        'Coral Stoneback Crab output $resourceId is absent or conflicts with '
        'the reviewed output name.',
      );
    }
    resource['acquisitionModes'] = _canonicalAcquisitionModes(<String>[
      ...(resource['acquisitionModes'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      'fieldGathering',
    ]);
  }
}

void _normalizeNodeOutputNames(
  List<Map<String, Object?>> workerNodes,
  Map<String, Map<String, Object?>> resourcesById,
) {
  for (final node in workerNodes) {
    final outputs = node['outputs']! as List<Map<String, Object?>>;
    for (final output in outputs) {
      final resourceId = output['resourceId']! as String;
      final resource = resourcesById[resourceId];
      if (resource == null) {
        continue;
      }
      output['gameItemId'] = resource['gameItemId'];
      output['name'] = resource['name'];
    }
  }
}

List<Map<String, dynamic>> _mapList(Object? value, String label) {
  if (value is! List<dynamic>) {
    throw FormatException('$label must be a JSON list.');
  }
  final result = <Map<String, dynamic>>[];
  for (var index = 0; index < value.length; index += 1) {
    final row = value[index];
    if (row is! Map<String, dynamic>) {
      throw FormatException('$label row $index must be an object.');
    }
    result.add(row);
  }
  return result;
}

List<String> _stringListFromSeed(Object? value, String label) {
  if (value is! List<dynamic> || value.any((entry) => entry is! String)) {
    throw FormatException('$label must be a string list.');
  }
  return value.cast<String>().toList(growable: false);
}

List<int> _intListFromSeed(Object? value, String label) {
  if (value is! List<dynamic>) {
    throw FormatException('$label must be an integer list.');
  }
  final result = <int>[];
  for (final entry in value) {
    final integer = _integer(entry);
    if (integer == null) {
      throw FormatException('$label must be an integer list.');
    }
    result.add(integer);
  }
  return result;
}

String _requiredString(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return result;
}

List<String> _canonicalAcquisitionModes(Iterable<String> rawModes) {
  const allowed = <String>['workerNode', 'fieldGathering', 'hunting'];
  final modes = rawModes.toSet();
  if (modes.isEmpty || modes.any((mode) => !allowed.contains(mode))) {
    throw FormatException('Invalid acquisition modes: ${modes.join(', ')}');
  }
  return <String>[
    for (final mode in allowed)
      if (modes.contains(mode)) mode,
  ];
}

bool _sameStrings(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var index = 0; index < actual.length; index += 1) {
    if (actual[index] != expected[index]) {
      return false;
    }
  }
  return true;
}

Future<List<_GatheringPointPayload>?> _loadGatheringPointSources(
  List<String> arguments,
) async {
  final payloads = <_GatheringPointPayload>[];
  final sourceFilenames = <String>{};
  final overrideOptions = <String>{};
  final safeSourceFilename = RegExp(r'^(?:a|item-)\d+\.json$');
  for (final source in _gatheringPointSources) {
    final equivalentItemIds = source.equivalentItemIds.toSet();
    final resourceItemIds = source.resources
        .map((resource) => resource.itemId)
        .toSet();
    if (!equivalentItemIds.contains(source.itemId) ||
        equivalentItemIds.length != source.equivalentItemIds.length ||
        resourceItemIds.length != source.resources.length ||
        equivalentItemIds.length != resourceItemIds.length ||
        equivalentItemIds.any((itemId) => !resourceItemIds.contains(itemId))) {
      throw StateError(
        'Gathering source item ${source.itemId} has inconsistent '
        'equivalent resource bindings.',
      );
    }
    if (!safeSourceFilename.hasMatch(source.sourceFilename) ||
        !sourceFilenames.add(source.sourceFilename) ||
        !source.overrideOption.startsWith('--gathering-') ||
        !source.overrideOption.endsWith('-source') ||
        !overrideOptions.add(source.overrideOption)) {
      throw StateError(
        'Gathering source item ${source.itemId} has an unsafe or duplicate '
        'source filename/override option.',
      );
    }
    final sourceOverride = _option(arguments, source.overrideOption);
    final gitRepository = _option(arguments, '--somethinglovely-git-repo');
    final bytes = sourceOverride != null
        ? await File(sourceOverride).readAsBytes()
        : gitRepository != null
        ? await _readPinnedGitBlob(
            gitRepository,
            'src/gathering/${source.sourceFilename}',
          )
        : await _download(
            Uri.parse(
              '$_gatheringSourceBaseUri/',
            ).resolve(source.sourceFilename),
          );
    final actualDigest = sha256.convert(bytes).toString();
    if (actualDigest != source.sha256) {
      stderr.writeln(
        'Gathering source items '
        '${source.equivalentItemIds.join(', ')} use payload '
        '${source.sourceFilename}, whose checksum did not match.\n'
        'Expected: ${source.sha256}\n'
        'Actual:   $actualDigest',
      );
      exitCode = 2;
      return null;
    }
    payloads.add(_GatheringPointPayload(source: source, bytes: bytes));
  }
  return payloads;
}

Future<List<int>> _readPinnedGitBlob(
  String repository,
  String repositoryPath,
) async {
  final result = await Process.run(
    'git',
    <String>['-C', repository, 'show', '$_sourceCommit:$repositoryPath'],
    stdoutEncoding: null,
    stderrEncoding: systemEncoding,
  );
  if (result.exitCode != 0 || result.stdout is! List<int>) {
    throw ProcessException(
      'git',
      <String>['-C', repository, 'show', '$_sourceCommit:$repositoryPath'],
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return (result.stdout! as List<int>).toList(growable: false);
}

List<Map<String, Object?>> _buildGatheringPoints(
  List<_GatheringPointPayload> payloads,
) {
  final pointsByCoordinate = <String, _GatheringPointAccumulator>{};
  for (final payload in payloads) {
    final decoded = jsonDecode(utf8.decode(payload.bytes));
    if (decoded is! List<dynamic>) {
      throw FormatException(
        'Gathering source item ${payload.source.itemId} must be a JSON list.',
      );
    }
    final selectedRows = _selectGatheringRows(decoded, payload.source);
    for (var index = 0; index < selectedRows.length; index += 1) {
      final row = selectedRows[index];
      if (row is! List<dynamic> || row.length != 2) {
        throw FormatException(
          'Gathering source item ${payload.source.itemId} row $index '
          'must contain exactly two coordinates.',
        );
      }
      final x = _number(row[0]);
      final z = _number(row[1]);
      if (x == null || z == null || !x.isFinite || !z.isFinite) {
        throw FormatException(
          'Gathering source item ${payload.source.itemId} row $index '
          'contains an invalid coordinate.',
        );
      }
      final coordinateKey =
          '${_coordinateComponent(x)},'
          '${_coordinateComponent(z)}';
      final point = pointsByCoordinate.putIfAbsent(
        coordinateKey,
        () => _GatheringPointAccumulator(x: x, z: z),
      );
      point.fieldSourceIds.add(_fieldSourceIdForTarget(payload.source.target));
      point.targets.add(payload.source.target);
      point.labels.add(payload.source.label);
      for (final resource in _resourcesForGatheringSource(payload.source)) {
        point.resourceIds.add(resource.resourceId);
        point.kinds.add(resource.kind);
      }
    }
  }

  final points = pointsByCoordinate.entries
      .map((entry) {
        final point = entry.value;
        final resourceIds = point.resourceIds.toList()..sort();
        final targets = point.targets.toList()..sort();
        final kinds = point.kinds.toList()..sort();
        final labels = point.labels.toList()..sort();
        return <String, Object?>{
          'id': 'gathering-point:${entry.key.replaceAll(',', ':')}',
          'x': point.x,
          'z': point.z,
          'resourceIds': resourceIds,
          'target': targets.join(' / '),
          'kind': kinds.join(' / '),
          'label': labels.join(' / '),
          'fieldSourceIds': point.fieldSourceIds.toList()..sort(),
          'verification': 'stale',
          'provenanceId': _gatheringPointProvenanceId,
        };
      })
      .toList(growable: false);
  points.sort((a, b) {
    final byX = (a['x']! as double).compareTo(b['x']! as double);
    if (byX != 0) {
      return byX;
    }
    final byZ = (a['z']! as double).compareTo(b['z']! as double);
    if (byZ != 0) {
      return byZ;
    }
    return (a['id']! as String).compareTo(b['id']! as String);
  });
  return points;
}

List<dynamic> _selectGatheringRows(
  List<dynamic> decoded,
  _GatheringPointSource source,
) {
  final cap = source.maximumPointCount;
  if (cap == null || decoded.length <= cap) {
    return decoded;
  }
  if (cap <= 0) {
    throw StateError(
      'Gathering point cap must be positive for ${source.target}.',
    );
  }

  final rows = <({List<dynamic> row, double x, double z, int originalIndex})>[];
  for (var index = 0; index < decoded.length; index += 1) {
    final row = decoded[index];
    if (row is! List<dynamic> || row.length != 2) {
      throw FormatException(
        'Gathering source item ${source.itemId} row $index '
        'must contain exactly two coordinates.',
      );
    }
    final x = _number(row[0]);
    final z = _number(row[1]);
    if (x == null || z == null || !x.isFinite || !z.isFinite) {
      throw FormatException(
        'Gathering source item ${source.itemId} row $index '
        'contains an invalid coordinate.',
      );
    }
    rows.add((row: row, x: x, z: z, originalIndex: index));
  }

  var minimumX = rows.first.x;
  var maximumX = rows.first.x;
  var minimumZ = rows.first.z;
  var maximumZ = rows.first.z;
  for (final row in rows.skip(1)) {
    if (row.x < minimumX) minimumX = row.x;
    if (row.x > maximumX) maximumX = row.x;
    if (row.z < minimumZ) minimumZ = row.z;
    if (row.z > maximumZ) maximumZ = row.z;
  }
  final extentX = maximumX - minimumX;
  final extentZ = maximumZ - minimumZ;
  const columns = 20;
  const rowCount = 15;
  final bestByCell =
      <
        int,
        ({
          List<dynamic> row,
          double x,
          double z,
          int originalIndex,
          double distance,
        })
      >{};
  for (final row in rows) {
    final normalizedX = extentX == 0 ? 0.5 : (row.x - minimumX) / extentX;
    final normalizedZ = extentZ == 0 ? 0.5 : (row.z - minimumZ) / extentZ;
    final column = (normalizedX * columns)
        .floor()
        .clamp(0, columns - 1)
        .toInt();
    final gridRow = (normalizedZ * rowCount)
        .floor()
        .clamp(0, rowCount - 1)
        .toInt();
    final centerX = (column + 0.5) / columns;
    final centerZ = (gridRow + 0.5) / rowCount;
    final deltaX = normalizedX - centerX;
    final deltaZ = normalizedZ - centerZ;
    final distance = deltaX * deltaX + deltaZ * deltaZ;
    final cell = gridRow * columns + column;
    final previous = bestByCell[cell];
    if (previous == null ||
        distance < previous.distance ||
        (distance == previous.distance &&
            row.originalIndex < previous.originalIndex)) {
      bestByCell[cell] = (
        row: row.row,
        x: row.x,
        z: row.z,
        originalIndex: row.originalIndex,
        distance: distance,
      );
    }
  }

  final selectedIndices = bestByCell.values
      .map((row) => row.originalIndex)
      .toSet();
  if (selectedIndices.length < cap) {
    final unselected =
        rows
            .where((row) => !selectedIndices.contains(row.originalIndex))
            .toList()
          ..sort((a, b) {
            final byX = a.x.compareTo(b.x);
            if (byX != 0) return byX;
            final byZ = a.z.compareTo(b.z);
            return byZ != 0 ? byZ : a.originalIndex.compareTo(b.originalIndex);
          });
    final needed = cap - selectedIndices.length;
    for (var index = 0; index < needed; index += 1) {
      final candidateIndex = (((index + 0.5) * unselected.length) / needed)
          .floor()
          .clamp(0, unselected.length - 1)
          .toInt();
      selectedIndices.add(unselected[candidateIndex].originalIndex);
    }
  }
  final selected =
      rows.where((row) => selectedIndices.contains(row.originalIndex)).toList()
        ..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
  return selected.take(cap).map((row) => row.row).toList(growable: false);
}

String _fieldSourceIdForTarget(String target) {
  return switch (target) {
    'Snake' || 'Stone Cobra' => 'field-source:snake',
    'Scorpion' || 'Rock Scorpion' => 'field-source:scorpion',
    'Thuja' => 'field-source:thuja-tree',
    _ =>
      'field-source:${target.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '')}',
  };
}

bool _isTreeGatheringTarget(String target) =>
    target == 'Thuja' || target.endsWith('Tree');

Iterable<_GatheringPointResource> _resourcesForGatheringSource(
  _GatheringPointSource source,
) sync* {
  yield* source.resources;
  if (_isTreeGatheringTarget(source.target)) {
    yield _logGatheringResource;
  }
}

List<Map<String, Object?>> _buildFieldSources(
  Map<String, Map<String, Object?>> resourcesById,
  Map<String, dynamic> marniSniperSeed,
  Map<String, dynamic> stillcoralSeed,
) {
  final resourcesBySource = <String, Map<String, _GatheringPointResource>>{};
  final targetBySource = <String, String>{};
  for (final source in _gatheringPointSources) {
    final sourceId = _fieldSourceIdForTarget(source.target);
    targetBySource[sourceId] = source.target;
    final products = resourcesBySource.putIfAbsent(
      sourceId,
      () => <String, _GatheringPointResource>{},
    );
    for (final resource in _resourcesForGatheringSource(source)) {
      products[resource.resourceId] = resource;
    }
  }

  final fieldSources = <Map<String, Object?>>[];
  final sourceIds = resourcesBySource.keys.toList()..sort();
  for (final sourceId in sourceIds) {
    final target = targetBySource[sourceId]!;
    final name = target == 'Thuja' ? 'Thuja Tree' : target;
    final category = _fieldSourceCategory(target);
    final products = resourcesBySource[sourceId]!.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    fieldSources.add(<String, Object?>{
      'id': sourceId,
      'name': name,
      'category': category,
      'aliases': _fieldSourceAliases(target),
      'summary': _fieldSourceSummary(name, category),
      'note': _fieldSourceNote(target),
      'products': <Map<String, Object?>>[
        for (final product in products)
          _fieldProductFromGatheringResource(product, sourceName: name),
      ],
    });
  }

  fieldSources.add(<String, Object?>{
    'id': _dairyCowFieldSourceId,
    'name': 'Dairy Cow',
    'category': 'Animals',
    'aliases': <String>[
      'cow milk',
      'dairy cattle',
      'milk cow',
      'milkable cow',
      'milking',
    ],
    'summary':
        'Interact with a Dairy Cow at one of the named farms and complete '
        'the milking minigame to obtain Milk.',
    'note':
        'Dairy Cows are separate from ordinary Cow / Ox targets used for '
        'meat, blood, and hide. Milking consumes 10 Energy. Farm markers '
        'identify named farm centers rather than individual cow spawn dots.',
    'products': <Map<String, Object?>>[
      <String, Object?>{
        'resourceId': 'item:9065',
        'method': 'Milk',
        'tool': 'Milking minigame',
        'instruction':
            'Interact with a Dairy Cow, choose the milking interaction, and '
            'complete the minigame. Each attempt consumes 10 Energy.',
      },
    ],
  });
  fieldSources.add(<String, Object?>{
    'id': _wildBeehiveSourceId,
    'name': 'Wild Beehive',
    'category': 'Hunting',
    'aliases': <String>['wild beehives', 'beehive', 'beehives'],
    'summary':
        'Shoot beehives from trees in Balenos Forest with a matchlock, then collect them.',
    'note':
        'Grind 3 Wild Beehives into Cooking Honey. The marker shows the forest area, not an exact hive.',
    'products': <Map<String, Object?>>[
      <String, Object?>{
        'resourceId': 'item:7701',
        'method': 'Hunt',
        'tool': 'Hunting Matchlock',
        'instruction':
            'Shoot the beehive with a matchlock and collect the fallen hive. No butcher knife needed.',
      },
    ],
  });
  fieldSources.add(<String, Object?>{
    'id': _citronFieldSourceId,
    'name': 'Citron Tree',
    'category': 'Plants & fruit',
    'aliases': <String>['citron orchard', 'maslan citron', 'yulas citron'],
    'summary':
        "Gather Citron Trees with bare hands inside Maslan's Yulas Citron "
        'Orchard, or send a worker to the orchard production node.',
    'note':
        'The map marks the reviewed orchard focus rather than inventing '
        'individual tree coordinates.',
    'products': <Map<String, Object?>>[
      <String, Object?>{
        'resourceId': 'item:7360',
        'method': 'Gather',
        'tool': 'Bare Hands',
        'instruction':
            "Gather Citron Trees inside Maslan's Yulas Citron Orchard with "
            'bare hands.',
      },
    ],
  });
  fieldSources.add(<String, Object?>{
    'id': 'field-source:vedelona-plant',
    'name': 'Vedelona Plant',
    'category': 'Plants & flowers',
    'aliases': <String>['kamasylvia flower', 'vedelona flower'],
    'summary':
        'Gather wild Vedelona plants in Kamasylvia with bare hands or a hoe.',
    'note':
        'The exact manual plant positions have not been independently '
        'verified, so the map does not draw an approximate region or '
        'invent location dots.',
    'products': <Map<String, Object?>>[
      <String, Object?>{
        'resourceId': 'item:5522',
        'method': 'Gather',
        'tool': 'Bare hands / Hoe',
        'instruction':
            'Gather the Vedelona plant itself with bare hands or a hoe. '
            'Worker nodes at Tooth Fairy Forest, Looney Cabin, and Weenie '
            'Cabin also provide Vedelona as a secondary output.',
      },
    ],
  });
  fieldSources.add(<String, Object?>{
    'id': 'field-source:poisonous-swamp-plant',
    'name': 'Poisonous Swamp Plant',
    'category': 'Plants',
    'aliases': <String>[
      'insectivore plant drops',
      'naga marsh poisonous plant',
      'glish swamp plant',
    ],
    'summary':
        'Defeat Poisonous Swamp Plants around Naga Marsh and Glish Swamp; '
        'these are combat drops, not products of gathering the separate '
        'Insectivore Plant object.',
    'note':
        'Important: characters far above the plant level may receive no '
        'Insectivore Plant Flower. The exact cutoff is not verified, so use '
        'a suitably low-level character when farming the flower.',
    'products': <Map<String, Object?>>[
      for (final resourceId in <String>[
        'item:5440',
        'item:5441',
        'item:5442',
        'item:5443',
      ])
        <String, Object?>{
          'resourceId': resourceId,
          'method': 'Defeat',
          'tool': 'Combat',
          'instruction':
              'Defeat Poisonous Swamp Plants in Naga Marsh or Glish Swamp; '
              'do not try to gather this drop with a tool.',
        },
    ],
  });
  fieldSources.add(_buildStillcoralFieldSource(stillcoralSeed));
  fieldSources.add(<String, Object?>{
    'id': 'field-source:coral-stoneback-crab',
    'name': 'Coral Stoneback Crab',
    'category': 'Coastal gathering',
    'aliases': <String>[
      'coastal crab',
      'land crab',
      'rusalka coral crab',
      'shore crab',
      'stoneback crab',
      'rusalka hunting',
    ],
    'summary':
        'Coral Stoneback Crabs are shore and land targets. Defeat a normal '
        'crab and mine its body for its materials; no swimming route is '
        'implied. A separate hunting variant can also provide '
        "Rusalka's Coral.",
    'note':
        'The 34 crab dots are community-reported exact positions and remain '
        'separate from nearby Oyster, coral, clam, and Sea Fan dots. Treat '
        'this as a private candidate layer until independently verified.',
    'products': <Map<String, Object?>>[
      for (final entry in _coralStonebackCrabNormalProducts.entries)
        <String, Object?>{
          'resourceId': 'item:${entry.key}',
          'method': 'Defeat and mine',
          'tool': 'Pickaxe',
          'instruction':
              'Defeat a normal Coral Stoneback Crab on the coast, then mine '
              'its body with a Pickaxe for ${entry.value}.',
        },
      <String, Object?>{
        'resourceId': 'item:821255',
        'method': 'Hunt and butcher',
        'tool': 'Hunting Matchlock and Butcher Knife',
        'instruction':
            'Defeat the hunting variant with a Hunting Matchlock, then use '
            'a Butcher Knife on its body.',
      },
    ],
  });
  fieldSources.add(_buildMarniSniperFieldSource(marniSniperSeed));

  for (final source in fieldSources) {
    for (final product in (source['products']! as List<Map<String, Object?>>)) {
      final resourceId = product['resourceId']! as String;
      if (!resourcesById.containsKey(resourceId)) {
        throw StateError(
          'Field source ${source['id']} references unknown $resourceId.',
        );
      }
    }
  }
  fieldSources.sort(
    (a, b) => (a['name']! as String).compareTo(b['name']! as String),
  );
  return fieldSources;
}

Map<String, Object?> _buildStillcoralFieldSource(Map<String, dynamic> seed) {
  final targetNamesByProduct = <int, List<String>>{};
  for (final target in _mapList(seed['targets'], 'Stillcoral targets')) {
    final targetName = _requiredString(target, 'name');
    for (final rawProduct in target['products']! as List<dynamic>) {
      final tuple = rawProduct! as List<dynamic>;
      final itemId = _integer(tuple.first)!;
      if (!_stillcoralUsefulProducts.containsKey(itemId)) {
        continue;
      }
      (targetNamesByProduct[itemId] ??= <String>[]).add(targetName);
    }
  }
  return <String, Object?>{
    'id': _stillcoralFieldSourceId,
    'name': 'Stillcoral Coastal Gathering',
    'category': 'Coastal gathering',
    'aliases': <String>[
      'coral gathering',
      'giant pearl clam gathering',
      'lobster gathering',
      'oyster rotation',
      'rainbow coral rotation',
      'stillcoral coast',
    ],
    'summary':
        'Gather Rainbow Coral, Oyster, Giant Pearl Clam, and Sea Fan objects '
        'at 198 recorded coastal positions near Stillcoral.',
    'note':
        'Every dot is an individual source-recorded object position. These '
        'nearby objects remain separate from Coral Stoneback Crab dots; no '
        'line, path order, broad circle, or invented rotation is included.',
    'products': <Map<String, Object?>>[
      for (final entry in _stillcoralUsefulProducts.entries)
        <String, Object?>{
          'resourceId': 'item:${entry.key}',
          'method': 'Gather',
          'tool': 'Hoe',
          'instruction':
              'Use a Hoe on '
              '${targetNamesByProduct[entry.key]!.join(' or ')} for '
              '${entry.value}.',
        },
    ],
  };
}

Map<String, Object?> _buildMarniSniperFieldSource(Map<String, dynamic> seed) {
  final raw = seed['fieldSource']! as Map<String, dynamic>;
  final spot = seed['spot']! as Map<String, dynamic>;
  final resourceIds = _stringListFromSeed(
    spot['resourceIds'],
    'Marni sniper field-source resources',
  );
  return <String, Object?>{
    'id': _requiredString(raw, 'id'),
    'name': _requiredString(raw, 'name'),
    'category': _requiredString(raw, 'category'),
    'aliases': _stringListFromSeed(raw['aliases'], 'Marni sniper aliases'),
    'summary':
        'Sniper-hunt boars, bears, hawks, and rare tigers in the Beombawi '
        'Valley Wild Game Preserve, then butcher each body once for its '
        'available materials and a chance at valuable hunting crystals.',
    'note':
        'This is a region anchor, not an exact spawn dot. A Marni Sniper '
        'Rifle requires Hunting Artisan 10 and is strongly recommended for '
        'this advanced preserve. Nearby animals react to gunfire and boars, '
        'bears, or tigers may charge. Shot quality affects rewards, so no fixed '
        'hourly yield is claimed.',
    'products': <Map<String, Object?>>[
      for (final resourceId in resourceIds)
        _buildMarniSniperProduct(resourceId),
    ],
  };
}

Map<String, Object?> _buildMarniSniperProduct(String resourceId) {
  const commonBoarResources = <String>{'item:7905', 'item:6205', 'item:6005'};
  const commonBearResources = <String>{'item:7912', 'item:6213', 'item:6013'};
  final instruction = switch (resourceId) {
    _ when commonBoarResources.contains(resourceId) =>
      'Shoot Sensitive or Atrocious Boars in the Wild Game Preserve, then '
          'use a Butcher Knife once on the body. That hunting harvest can '
          'award Pork, Pig Blood, and Pig Hide together.',
    _ when commonBearResources.contains(resourceId) =>
      'Shoot Sensitive or Atrocious Bears in the Wild Game Preserve, then '
          'use a Butcher Knife once on the body. That hunting harvest can '
          'award Bear Meat, Bear Blood, and Bear Hide together.',
    'item:820039' =>
      'Crystal of Decimation is a rare sniper-hunting reward from bears and '
          'rare tigers in the Wild Game Preserve.',
    'item:820038' =>
      'Crystal of Bitterness is a rare sniper-hunting reward from bears in '
          'the Wild Game Preserve.',
    'item:820037' =>
      'Crystal of Darkness is a rare sniper-hunting reward from hawks in the '
          'Wild Game Preserve.',
    'item:820036' =>
      'Forest Crystal is a rare Land of the Morning Light sniper-hunting '
          'reward. It is not a guaranteed result from each animal.',
    'item:820139' =>
      'Live Meat is a rare cooking material obtained when butchering Land of '
          'the Morning Light sniper-hunting monsters. It is not guaranteed.',
    _ => throw StateError('Unsupported Marni sniper product $resourceId.'),
  };
  return <String, Object?>{
    'resourceId': resourceId,
    'method': 'Sniper hunt and butcher',
    'tool': 'Sniper Rifle + Butcher Knife',
    'instruction': instruction,
  };
}

String _fieldSourceCategory(String target) {
  if (<String>{
    'Snake',
    'Scorpion',
    'Sheep',
    'Bear',
    'Wasteland Cheetah Dragon',
    'Fan Flamingo',
    'Lizard',
    'Raccoon',
    'Weasel',
    'Stone Rhino',
    'Wolf',
    'Deer',
    'Fox',
    'Pig',
    'Cow / Ox',
  }.contains(target)) {
    return 'Animals';
  }
  if (target == 'Thuja' || target.endsWith('Tree')) {
    return 'Trees';
  }
  if (target.contains('Mushroom')) {
    return 'Mushrooms';
  }
  return 'Plants';
}

List<String> _fieldSourceAliases(String target) {
  return switch (target) {
    'Snake' => <String>['cobra', 'stone cobra', 'snake animal'],
    'Scorpion' => <String>['rock scorpion', 'scorpion animal'],
    'Sheep' => <String>['lamb', 'mountain sheep'],
    'Thuja' => <String>['thuja', 'thuja wood source'],
    'Wasteland Cheetah Dragon' => <String>['cheetah dragon'],
    'Fan Flamingo' => <String>['flamingo'],
    'Stone Rhino' => <String>['rhino'],
    'Cow / Ox' => <String>['cow', 'cattle', 'ox'],
    'Insectivore Plant' => <String>['carnivorous plant', 'insectivore'],
    _ => <String>[target.toLowerCase()],
  };
}

String _fieldSourceSummary(String name, String category) {
  return switch (category) {
    'Animals' =>
      'Defeat $name, then choose the gathering tool for the product you need.',
    'Trees' =>
      'The same $name locations provide timber and Logs with a Lumbering Axe, '
          'or sap with a Fluid Collector.',
    _ => 'Gather $name at the recorded historical locations.',
  };
}

String _fieldSourceNote(String target) {
  return switch (target) {
    'Insectivore Plant' =>
      'Requires Gathering Beginner 10. These dots belong to the gatherable '
          'plant object and provide Powder or Sap, not the Flower, Leaf, '
          'Stalk, or Root combat drops.',
    'Truffle Mushroom' =>
      'Requires Gathering Skilled 5. The official November 2022 update names '
          '13 areas with 87 mushrooms and a 33% shorter respawn time. Exact '
          'dots remain MIT-licensed historical records through 2021 and may '
          'not represent every current spawn.',
    _ when target.endsWith('Tree') =>
      'For performance, this layer contains at most 300 genuine historical '
          'recorded positions chosen by a deterministic 20 by 15 spatial '
          'grid; no coordinates are invented.',
    _ =>
      'Recorded locations are historical through 2021 and may not represent '
          'every current spawn.',
  };
}

Map<String, Object?> _fieldProductFromGatheringResource(
  _GatheringPointResource resource, {
  required String sourceName,
}) {
  final methodAndTool = switch (resource.kind) {
    'butchering' => ('Butcher', 'Butcher Knife'),
    'fluid collecting' => ('Fluid collect', 'Fluid Collector'),
    'tanning' => ('Tan', 'Tanning Knife'),
    'lumbering' => ('Lumber', 'Lumbering Axe'),
    'mining with a pickaxe' => ('Mine', 'Pickaxe'),
    _ => ('Gather', 'Bare Hands or Hoe'),
  };
  final instruction = switch (resource.kind) {
    'butchering' => 'Defeat $sourceName, then use a Butcher Knife on the body.',
    'fluid collecting' =>
      'Use a Fluid Collector on $sourceName to obtain ${resource.name}.',
    'tanning' => 'Defeat $sourceName, then use a Tanning Knife on the body.',
    'lumbering' =>
      'Use a Lumbering Axe on $sourceName to obtain ${resource.name}.',
    'mining with a pickaxe' =>
      'Use a Pickaxe on $sourceName to obtain ${resource.name}.',
    _ => 'Gather $sourceName with Bare Hands or a Hoe.',
  };
  return <String, Object?>{
    'resourceId': resource.resourceId,
    'method': methodAndTool.$1,
    'tool': methodAndTool.$2,
    'instruction': instruction,
  };
}

List<Map<String, Object?>> _buildRusalkaGatheringPoints(
  Map<String, dynamic> seed,
) {
  final resource = seed['resource']! as Map<String, dynamic>;
  final resourceId = _requiredString(resource, 'id');
  if (resourceId != 'item:821255') {
    throw StateError('Coral Stoneback Crab point resource binding changed.');
  }
  final metadata = seed['pointMetadata']! as Map<String, dynamic>;
  final verifiedAt = _requiredString(
    seed['sourceReview']! as Map<String, dynamic>,
    'retrievedAt',
  );
  final points = <Map<String, Object?>>[];
  for (final row in _mapList(seed['points'], "Rusalka's Coral points")) {
    final recordId = _integer(row['sourceNpcRecordId'])!;
    final pixelX = _number(row['pixelX'])!;
    final pixelY = _number(row['pixelY'])!;
    final gameX = (pixelX - _rusalkaPixelOriginX) * _rusalkaPixelScale;
    final gameZ = (_rusalkaPixelOriginY - pixelY) * _rusalkaPixelScale;
    points.add(<String, Object?>{
      'id': 'gathering-point:bdocodex:28115:$recordId',
      'x': gameX,
      'z': gameZ,
      'resourceIds': <String>[
        for (final itemId in _coralStonebackCrabNormalProducts.keys)
          'item:$itemId',
      ],
      'target': _requiredString(metadata, 'target'),
      'kind': _requiredString(metadata, 'kind'),
      'label': _requiredString(metadata, 'label'),
      'fieldSourceIds': <String>['field-source:coral-stoneback-crab'],
      'verification': _requiredString(metadata, 'verification'),
      'provenanceId': _rusalkaPointProvenanceId,
      'verifiedAt': verifiedAt,
    });
  }
  return points;
}

List<Map<String, Object?>> _buildStillcoralGatheringPoints(
  Map<String, dynamic> seed,
) {
  final points = <Map<String, Object?>>[];
  for (final target in _mapList(seed['targets'], 'Stillcoral targets')) {
    final targetId = _integer(target['targetId'])!;
    final targetName = _requiredString(target, 'name');
    final resourceIds = <String>[];
    for (final rawProduct in target['products']! as List<dynamic>) {
      final productTuple = rawProduct! as List<dynamic>;
      final itemId = _integer(productTuple.first)!;
      if (_stillcoralUsefulProducts.containsKey(itemId)) {
        resourceIds.add('item:$itemId');
      }
    }
    for (final rawPoint in target['points']! as List<dynamic>) {
      final tuple = rawPoint! as List<dynamic>;
      final sourceOrdinal = _integer(tuple[0])!;
      final pixelX = _number(tuple[1])!;
      final pixelY = _number(tuple[2])!;
      final gameX = (pixelX - _bdoCodexPixelOriginX) * _bdoCodexPixelScale;
      final gameZ = (_bdoCodexPixelOriginY - pixelY) * _bdoCodexPixelScale;
      points.add(<String, Object?>{
        'id': 'gathering-point:bdocodex:stillcoral:$targetId:$sourceOrdinal',
        'x': gameX,
        'z': gameZ,
        'resourceIds': resourceIds,
        'target': targetName,
        'kind': 'gathering with a hoe',
        'label': '$targetName gathering location',
        'fieldSourceIds': <String>[_stillcoralFieldSourceId],
        'verification': 'communityReported',
        'provenanceId': _stillcoralPointProvenanceId,
        'verifiedAt': '${_stillcoralSourceRetrievedAt}T00:00:00Z',
      });
    }
  }
  if (points.length != 198) {
    throw StateError(
      'Stillcoral point builder must preserve 198 exact points; found '
      '${points.length}.',
    );
  }
  return points;
}

List<Map<String, Object?>> _buildDrieghanAnimalGatheringPoints(
  List<_BdoCodexNpcPointPayload> payloads, {
  required Set<String> occupiedCoordinates,
}) {
  final points = <Map<String, Object?>>[];
  for (final payload in payloads) {
    for (var index = 0; index < payload.points.length; index += 1) {
      final sourcePoint = payload.points[index];
      final gameX =
          (sourcePoint.pixelX - _bdoCodexPixelOriginX) * _bdoCodexPixelScale;
      final gameZ =
          (_bdoCodexPixelOriginY - sourcePoint.pixelY) * _bdoCodexPixelScale;
      final coordinateKey =
          '${_coordinateComponent(gameX)},${_coordinateComponent(gameZ)}';
      if (!occupiedCoordinates.add(coordinateKey)) {
        continue;
      }
      points.add(<String, Object?>{
        'id': 'gathering-point:bdocodex:${payload.source.npcId}:${index + 1}',
        'x': gameX,
        'z': gameZ,
        'resourceIds': <String>[payload.source.resourceId],
        'target': payload.source.target,
        'kind': payload.source.kind,
        'label': payload.source.label,
        'fieldSourceIds': <String>[
          _fieldSourceIdForTarget(payload.source.target),
        ],
        'verification': 'communityReported',
        'provenanceId': _drieghanAnimalPointProvenanceId,
        'verifiedAt': _drieghanSourceRetrievedAt,
        if (_belongsToTshiraRotationFocus(gameX, gameZ))
          'areaId': _tshiraRotationSpotId,
      });
    }
  }
  return points;
}

Map<String, Object?> _buildTshiraRotationSpot(
  List<_BdoCodexNpcPointPayload> payloads,
) {
  final nearbyCounts = <int, int>{};
  for (final payload in payloads) {
    var count = 0;
    for (final sourcePoint in payload.points) {
      final gameX =
          (sourcePoint.pixelX - _bdoCodexPixelOriginX) * _bdoCodexPixelScale;
      final gameZ =
          (_bdoCodexPixelOriginY - sourcePoint.pixelY) * _bdoCodexPixelScale;
      if (_belongsToTshiraRotationFocus(gameX, gameZ)) {
        count += 1;
      }
    }
    nearbyCounts[payload.source.npcId] = count;
  }
  final snakeCount = nearbyCounts[21758] ?? 0;
  final scorpionCount = nearbyCounts[21757] ?? 0;
  if (snakeCount != 21 || scorpionCount != 8) {
    throw StateError(
      'Tshira rotation focus must contain 21 Stone Cobra and '
      '8 Rock Scorpion points; found $snakeCount and $scorpionCount.',
    );
  }

  return <String, Object?>{
    'id': _tshiraRotationSpotId,
    'name': 'Tshira Ruins Snake & Scorpion Rotation',
    'region': 'Drieghan',
    'nearestNode': 'Tshira Ruins',
    'x': _tshiraRouteFocusX,
    'z': _tshiraRouteFocusZ,
    'resourceIds': <String>['item:7922', 'item:7924'],
    'targets': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'Stone Cobra',
        'tool': 'Butcher Knife',
        'resourceIds': <String>['item:7922'],
        'gameNpcIds': <int>[21758],
      },
      <String, Object?>{
        'name': 'Rock Scorpion',
        'tool': 'Butcher Knife',
        'resourceIds': <String>['item:7924'],
        'gameNpcIds': <int>[21757],
      },
    ],
    'quality': 'Current combined rotation',
    'summary':
        'Current July 2026 gathering references still identify the compact '
        'ground south of Tshira Ruins as a combined Snake and Scorpion '
        'butchering rotation. This focus groups $snakeCount exact Stone '
        'Cobra dots and $scorpionCount exact Rock Scorpion dots. No broad '
        'coverage circle or traced video path is drawn.',
    'verification': 'communityReported',
    'provenanceId': _tshiraRotationProvenanceId,
    'verifiedAt': _tshiraRotationRetrievedAt,
  };
}

Map<String, Object?> _buildMarniSniperHuntingSpot(
  Map<String, dynamic> seed,
  Map<String, dynamic> currentNodeSeed,
) {
  final anchor = seed['mapAnchor']! as Map<String, dynamic>;
  final raw = seed['spot']! as Map<String, dynamic>;
  final sourceNode = _mapList(
    currentNodeSeed['nodes'],
    'current nodes',
  ).singleWhere((node) => _integer(node['id'])?.toString() == anchor['nodeId']);
  final sourceX =
      (_number(sourceNode['pixelX'])! - _bdoCodexPixelOriginX) *
      _bdoCodexPixelScale;
  final sourceZ =
      (_bdoCodexPixelOriginY - _number(sourceNode['pixelY'])!) *
      _bdoCodexPixelScale;
  final x = _number(anchor['x'])!;
  final z = _number(anchor['z'])!;
  if (sourceNode['name'] != anchor['nodeName'] ||
      (sourceX - x).abs() > 0.001 ||
      (sourceZ - z).abs() > 0.001) {
    throw const FormatException(
      'Marni sniper region anchor no longer matches Beombawi Valley.',
    );
  }
  final targets = _mapList(raw['targets'], 'Marni sniper targets');
  return <String, Object?>{
    'id': _requiredString(raw, 'id'),
    'name': _requiredString(raw, 'name'),
    'region': _requiredString(raw, 'region'),
    'nearestNode': _requiredString(raw, 'nearestNode'),
    'x': x,
    'z': z,
    'resourceIds': _stringListFromSeed(
      raw['resourceIds'],
      'Marni sniper spot resources',
    ),
    'fieldSourceIds': <String>[_marniSniperFieldSourceId],
    'targets': <Map<String, Object?>>[
      for (final target in targets)
        <String, Object?>{
          'name': _requiredString(target, 'name'),
          'tool': 'Sniper Rifle + Butcher Knife',
          'resourceIds': _stringListFromSeed(
            target['resourceIds'],
            'Marni sniper target resources',
          ),
          'gameNpcIds': _intListFromSeed(
            target['gameNpcIds'],
            'Marni sniper target NPC IDs',
          ),
        },
    ],
    'quality': _requiredString(raw, 'quality'),
    'summary':
        'The marker identifies the Beombawi Valley Wild Game Preserve '
        'region focus, northwest of Dalbeol Village. Animals roam inside '
        'the preserve, so this deliberately draws no fake coverage circle '
        'or fabricated spawn dots.',
    'verification': 'crossChecked',
    'provenanceId': _marniSniperProvenanceId,
    'verifiedAt': _marniSniperRetrievedAt,
  };
}

Map<String, Object?> _buildWildBeehiveSpot(
  List<Map<String, Object?>> workerNodes,
) {
  final forest = workerNodes.singleWhere((node) => node['id'] == '44');
  if (forest['name'] != 'Balenos Forest') {
    throw const FormatException('The reviewed Balenos Forest anchor changed.');
  }
  return <String, Object?>{
    'id': 'gathering:balenos-forest-wild-beehives',
    'name': 'Balenos Forest beehives',
    'region': 'Balenos',
    'nearestNode': 'Balenos Forest',
    'x': forest['x']! as double,
    'z': forest['z']! as double,
    'resourceIds': <String>['item:7701'],
    'fieldSourceIds': <String>[_wildBeehiveSourceId],
    'targets': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'Wild Beehive',
        'tool': 'Hunting Matchlock',
        'resourceIds': <String>['item:7701'],
      },
    ],
    'quality': 'Named hunting area',
    'summary':
        'Look for beehives hanging in the trees around Balenos Forest. Shoot them with a matchlock and collect them. This is an area marker, not an exact hive location.',
    'verification': 'crossChecked',
    'provenanceId': _wildBeehiveProvenanceId,
    'verifiedAt': '2026-09-09T02:30:00Z',
  };
}

Map<String, Object?> _buildCitronOrchardSpot(
  List<Map<String, Object?>> workerNodes,
) {
  final orchard = workerNodes.singleWhere((node) => node['id'] == '1768');
  if (orchard['name'] != "Maslan's Yulas Citron Orchard - Gathering" ||
      orchard['nodeType'] != 'Gathering' ||
      !(orchard['outputs']! as List<Map<String, Object?>>).any(
        (output) => output['resourceId'] == 'item:7360',
      )) {
    throw const FormatException(
      'The reviewed Citron orchard worker node changed unexpectedly.',
    );
  }
  return <String, Object?>{
    'id': _citronOrchardSpotId,
    'name': "Maslan's Yulas Citron Orchard",
    'region': 'Mountain of Eternal Winter',
    'nearestNode': "Maslan's Yulas Citron Orchard",
    'x': orchard['x']! as double,
    'z': orchard['z']! as double,
    'resourceIds': <String>['item:7360'],
    'fieldSourceIds': <String>[_citronFieldSourceId],
    'targets': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'Citron Tree',
        'tool': 'Bare Hands',
        'resourceIds': <String>['item:7360'],
        'gameNpcIds': <int>[11989],
      },
    ],
    'quality': 'Named manual-gathering focus',
    'summary':
        "Citron Trees grow inside Maslan's Yulas Citron Orchard and can be "
        'gathered with bare hands. This marker identifies the named orchard '
        'center; it deliberately does not pretend to be an individual tree '
        'spawn or draw an approximate coverage circle.',
    'verification': 'crossChecked',
    'provenanceId': _citronProvenanceId,
    'verifiedAt': _citronReviewedAt,
  };
}

List<Map<String, Object?>> _buildDairyCowSpots(
  List<Map<String, Object?>> workerNodes,
) {
  const farms =
      <({String nodeId, String nodeName, String locationName, String region})>[
        (
          nodeId: '65',
          nodeName: 'Wale Farm',
          locationName: 'Wale Farm',
          region: 'Balenos',
        ),
        (
          nodeId: '661',
          nodeName: 'Falres Dirt Farm',
          locationName: 'Falres Dirt Farm',
          region: 'Calpheon',
        ),
        (
          nodeId: '663',
          nodeName: 'Bain Farmland',
          locationName: 'Bain Farmland',
          region: 'Calpheon',
        ),
        (
          nodeId: '1158',
          nodeName: 'Stonetail Horse Ranch',
          locationName: 'Stonetail Horse Ranch',
          region: 'Mediah',
        ),
        (
          nodeId: '1623',
          nodeName: 'Grána',
          locationName: 'Grána Farm',
          region: 'Kamasylvia',
        ),
        (
          nodeId: '1650',
          nodeName: 'Duvencrune Farmland',
          locationName: 'Duvencrune Farmland',
          region: 'Drieghan',
        ),
      ];
  final nodesById = <String, Map<String, Object?>>{
    for (final node in workerNodes) node['id']! as String: node,
  };
  return <Map<String, Object?>>[
    for (final farm in farms)
      () {
        final node = nodesById[farm.nodeId];
        if (node == null || node['name'] != farm.nodeName) {
          throw FormatException(
            'The reviewed ${farm.locationName} node changed unexpectedly.',
          );
        }
        return <String, Object?>{
          'id': 'gathering:dairy-cow:${farm.nodeId}',
          'name': '${farm.locationName} Dairy Cows',
          'region': farm.region,
          'nearestNode': farm.locationName,
          'x': node['x']! as double,
          'z': node['z']! as double,
          'resourceIds': <String>['item:9065'],
          'fieldSourceIds': <String>[_dairyCowFieldSourceId],
          'targets': <Map<String, Object?>>[
            <String, Object?>{
              'name': 'Dairy Cow',
              'tool': 'Milking minigame',
              'resourceIds': <String>['item:9065'],
              'gameNpcIds': <int>[],
            },
          ],
          'quality': 'Named milking-area focus',
          'summary':
              'Dairy Cows can be milked near ${farm.locationName}. This '
              'marker identifies the named farm or node center; look nearby '
              'for the cows because it is not an individual spawn dot.',
          'verification': 'crossChecked',
          'provenanceId': _dairyCowProvenanceId,
          'verifiedAt': _dairyCowReviewedAt,
        };
      }(),
  ];
}

List<Map<String, Object?>> _truffleOfficialGuideImages([String? region]) {
  return <Map<String, Object?>>[
    for (final entry in _truffleOfficialOverviewUrls.entries)
      if (region == null || entry.key == region)
        <String, Object?>{
          'assetPath': entry.value,
          'caption':
              'Official ${entry.key} truffle overview — regional guide, '
              'not a photo of this exact dot',
          'provenanceId': _truffleOfficialPatchProvenanceId,
          'verifiedAt': _truffleOfficialReviewedAt,
        },
  ];
}

List<Map<String, Object?>> _buildOfficialTruffleSpots(
  List<Map<String, Object?>> workerNodes,
  List<Map<String, Object?>> gatheringPoints,
) {
  const areas =
      <
        ({
          String slug,
          String name,
          String region,
          String nodeId,
          String nodeName,
          int mushroomCount,
          double? anchorX,
          double? anchorZ,
        })
      >[
        (
          slug: 'eastern-gateway-hidden-cave',
          name: 'Hidden Cave near Eastern Gateway',
          region: 'Serendia',
          nodeId: '309',
          nodeName: 'Eastern Gateway',
          mushroomCount: 7,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'central-guard-camp-hidden-cave',
          name: 'Hidden Cave near Central Guard Camp',
          region: 'Serendia',
          nodeId: '304',
          nodeName: 'Central Guard Camp',
          mushroomCount: 8,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'moretti-plantation-rock-cave',
          name: 'Rock Cave near Moretti Plantation',
          region: 'Serendia',
          nodeId: '323',
          nodeName: 'Moretti Plantation',
          mushroomCount: 5,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'alejandro-farm-cave',
          name: 'Cave near Alejandro Farm',
          region: 'Serendia',
          nodeId: '321',
          nodeName: 'Alejandro Farm',
          mushroomCount: 5,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'watchtower-cave',
          name: 'Cave near Watchtower',
          region: 'Serendia',
          nodeId: '376',
          nodeName: 'Watchtower',
          mushroomCount: 10,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'phoniels-cabin-rock-cave',
          name: "Rock Cave near Phoniel's Cabin",
          region: 'Calpheon',
          nodeId: '722',
          nodeName: "Phoniel's Cabin",
          mushroomCount: 5,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'rhua-tree-stub',
          name: 'Rhua Tree Stub',
          region: 'Calpheon',
          nodeId: '710',
          nodeName: 'Rhua Tree Stub',
          mushroomCount: 5,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'marie-cave',
          name: 'Cave near Marie Cave Node',
          region: 'Calpheon',
          nodeId: '716',
          nodeName: 'Marie Cave',
          mushroomCount: 4,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'glutoni-cave',
          name: 'Glutoni Cave',
          region: 'Calpheon',
          nodeId: '672',
          nodeName: 'Glutoni Cave',
          mushroomCount: 10,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'hasrah-cliff-river-cave',
          name: 'Small Cave near Hasrah Cliff River',
          region: 'Mediah',
          nodeId: '1172',
          nodeName: 'Hasrah Cliff',
          mushroomCount: 4,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'hasrah-ancient-ruins-rock-cave',
          name: 'Rock Cave near Hasrah Ancient Ruins',
          region: 'Mediah',
          nodeId: '1172',
          nodeName: 'Hasrah Cliff',
          mushroomCount: 4,
          anchorX: 217371,
          anchorZ: -108985,
        ),
        (
          slug: 'fountain-of-origin-altar',
          name: 'Altar near Fountain of Origin',
          region: 'Drieghan',
          nodeId: '1663',
          nodeName: 'Fountain of Origin',
          mushroomCount: 8,
          anchorX: null,
          anchorZ: null,
        ),
        (
          slug: 'morning-fog-post-river',
          name: 'River near Morning Fog Post',
          region: 'Drieghan',
          nodeId: '1658',
          nodeName: 'Morning Fog Post',
          mushroomCount: 12,
          anchorX: null,
          anchorZ: null,
        ),
      ];
  final nodesById = <String, Map<String, Object?>>{
    for (final node in workerNodes) node['id']! as String: node,
  };
  final truffleCoordinates = gatheringPoints
      .where((point) => point['target'] == 'Truffle Mushroom')
      .map(
        (point) =>
            '${_coordinateComponent((point['x']! as num).toDouble())},'
            '${_coordinateComponent((point['z']! as num).toDouble())}',
      )
      .toSet();
  final spots = <Map<String, Object?>>[];
  for (final area in areas) {
    final node = nodesById[area.nodeId];
    if (node == null || node['name'] != area.nodeName) {
      throw FormatException(
        'The reviewed ${area.nodeName} truffle anchor changed unexpectedly.',
      );
    }
    final usesHistoricalPoint = area.anchorX != null && area.anchorZ != null;
    final x = area.anchorX ?? node['x']! as double;
    final z = area.anchorZ ?? node['z']! as double;
    if (usesHistoricalPoint &&
        !truffleCoordinates.contains(
          '${_coordinateComponent(x)},${_coordinateComponent(z)}',
        )) {
      throw FormatException(
        '${area.name} no longer references a licensed historical truffle '
        'coordinate.',
      );
    }
    final anchorDescription = usesHistoricalPoint
        ? 'a nearby MIT-licensed historical Truffle Mushroom dot'
        : 'the reviewed ${area.nodeName} node center';
    spots.add(<String, Object?>{
      'id': 'gathering:truffle:${area.slug}',
      'name': area.name,
      'region': area.region,
      'nearestNode': area.nodeName,
      'x': x,
      'z': z,
      'resourceIds': <String>['item:5420'],
      'fieldSourceIds': <String>['field-source:truffle-mushroom'],
      'targets': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'Truffle Mushroom',
          'tool': 'Bare Hands / Hoe',
          'resourceIds': <String>['item:5420'],
          'gameNpcIds': <int>[10430],
        },
      ],
      'quality': 'Official named-area focus',
      'summary':
          'Pearl Abyss lists ${area.mushroomCount} Truffle Mushrooms at this '
          'named area. The marker uses $anchorDescription only as a '
          'navigation focus; it is not a guaranteed cave entrance or a new '
          'exact spawn pin. Use the official regional overview below, then '
          'look in the nearby cave or river area.',
      'verification': 'crossChecked',
      'provenanceId': _truffleOfficialPatchProvenanceId,
      'verifiedAt': _truffleOfficialReviewedAt,
      'guideImages': _truffleOfficialGuideImages(area.region),
    });
  }
  if (areas.fold<int>(0, (sum, area) => sum + area.mushroomCount) != 87) {
    throw StateError('Official Truffle Mushroom count changed.');
  }
  return spots;
}

bool _belongsToTshiraRotationFocus(double x, double z) {
  final dx = x - _tshiraNodeX;
  final dz = z - _tshiraNodeZ;
  return (dx * dx) + (dz * dz) <
      _tshiraRouteFocusRadius * _tshiraRouteFocusRadius;
}

void _sortAndValidateGatheringPoints(List<Map<String, Object?>> points) {
  final ids = <String>{};
  final coordinateKeys = <String>{};
  for (final point in points) {
    final id = point['id']! as String;
    final x = (point['x']! as num).toDouble();
    final z = (point['z']! as num).toDouble();
    final coordinateKey =
        '${_coordinateComponent(x)},${_coordinateComponent(z)}';
    if (!ids.add(id)) {
      throw StateError('Duplicate gathering point ID: $id');
    }
    if (!coordinateKeys.add(coordinateKey)) {
      throw StateError(
        'Gathering point $id duplicates coordinate $coordinateKey across '
        'independently attributed sources.',
      );
    }
  }
  points.sort((a, b) {
    final byX = (a['x']! as num).compareTo(b['x']! as num);
    if (byX != 0) {
      return byX;
    }
    final byZ = (a['z']! as num).compareTo(b['z']! as num);
    if (byZ != 0) {
      return byZ;
    }
    return (a['id']! as String).compareTo(b['id']! as String);
  });
}

String _coordinateComponent(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

void _addGatheringResources(Map<String, Map<String, Object?>> resourcesById) {
  final definitions = <String, _GatheringPointResource>{};
  for (final source in _gatheringPointSources) {
    for (final resource in _resourcesForGatheringSource(source)) {
      final previous = definitions[resource.resourceId];
      if (previous != null &&
          (previous.name != resource.name ||
              previous.category != resource.category)) {
        throw StateError(
          'Conflicting gathering definitions for ${resource.resourceId}.',
        );
      }
      definitions[resource.resourceId] = resource;
    }
  }
  for (final resource in _fieldOnlyResources) {
    definitions[resource.resourceId] = resource;
  }

  for (final resource in definitions.values) {
    final existing = resourcesById[resource.resourceId];
    if (existing == null) {
      resourcesById[resource.resourceId] = <String, Object?>{
        'id': resource.resourceId,
        'gameItemId': resource.itemId,
        'name': resource.name,
        'category': resource.category,
        'aliases': resource.aliases,
        'acquisitionModes': <String>['fieldGathering'],
      };
      continue;
    }
    if (existing['gameItemId'] != resource.itemId ||
        existing['name'] != resource.name) {
      throw FormatException(
        'Historical gathering resource ${resource.resourceId} conflicts '
        'with the current reviewed resource definition.',
      );
    }
    existing['aliases'] = (<String>{
      ...(existing['aliases'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      ...resource.aliases,
    }.toList()..sort());
    existing['acquisitionModes'] = _canonicalAcquisitionModes(<String>[
      ...(existing['acquisitionModes'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      'fieldGathering',
    ]);
  }
}

void _addMarniHuntingResourceModes(
  Map<String, Map<String, Object?>> resourcesById,
  Map<String, dynamic> seed,
) {
  final spot = seed['spot']! as Map<String, dynamic>;
  for (final resourceId in _stringListFromSeed(
    spot['resourceIds'],
    'Marni sniper hunting resources',
  )) {
    var resource = resourcesById[resourceId];
    if (resource == null && resourceId == 'item:820139') {
      resource = <String, Object?>{
        'id': resourceId,
        'gameItemId': 820139,
        'name': 'Live Meat',
        'category': 'Gathering meat',
        'aliases': <String>['morning light sniper meat', 'sniper hunting meat'],
        'acquisitionModes': <String>['hunting'],
      };
      resourcesById[resourceId] = resource;
    }
    if (resource == null) {
      throw StateError('Marni sniper hunting requires $resourceId.');
    }
    resource['acquisitionModes'] = _canonicalAcquisitionModes(<String>[
      ...(resource['acquisitionModes'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      'hunting',
    ]);
  }
}

void _addDrieghanAnimalAliases(
  Map<String, Map<String, Object?>> resourcesById,
) {
  const aliasesByResource = <String, List<String>>{
    'item:7922': <String>[
      'stone cobra',
      'tshira snake',
      'tshira ruins',
      'tshira rotation',
    ],
    'item:7924': <String>[
      'rock scorpion',
      'tshira scorpion',
      'tshira ruins',
      'tshira rotation',
    ],
  };
  for (final entry in aliasesByResource.entries) {
    final resource = resourcesById[entry.key];
    if (resource == null) {
      throw StateError(
        'Drieghan exact-location source requires resource ${entry.key}.',
      );
    }
    resource['aliases'] = (<String>{
      ...(resource['aliases'] as List<Object?>? ?? const <Object?>[])
          .cast<String>(),
      ...entry.value,
    }.toList()..sort());
  }
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) {
    return null;
  }
  if (index + 1 >= arguments.length) {
    throw FormatException('$name requires a value.');
  }
  return arguments[index + 1];
}

Future<List<int>> _download(Uri uri) async {
  Object? lastError;
  StackTrace? lastStackTrace;
  for (var attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await _downloadOnce(uri);
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: attempt * 350));
      }
    }
  }
  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}

Future<List<int>> _downloadOnce(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'BDO-Craft-Planner-Map-Data-Builder/0.1',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Source download returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    return response.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
  } finally {
    client.close(force: true);
  }
}

double? _number(Object? value) {
  return switch (value) {
    num number => number.toDouble(),
    String string => double.tryParse(string),
    _ => null,
  };
}

int? _integer(Object? value) {
  return switch (value) {
    int integer => integer,
    num number => number.round(),
    String string => double.tryParse(string)?.round(),
    _ => null,
  };
}

void _assignResourceSections(
  Map<String, Map<String, Object?>> resourcesById,
  List<Map<String, Object?>> workerNodes,
) {
  final activitiesByResource = <String, Set<String>>{};
  for (final node in workerNodes) {
    final activity = _sectionActivityForNode(node);
    if (activity == null) {
      continue;
    }
    for (final output
        in (node['outputs'] as List<Object?>? ?? const <Object?>[])) {
      final resourceId = (output! as Map<String, Object?>)['resourceId'];
      if (resourceId is String) {
        (activitiesByResource[resourceId] ??= <String>{}).add(activity);
      }
    }
  }

  final actualCounts = <String, int>{};
  for (final entry in resourcesById.entries) {
    final resource = entry.value;
    final section = _resourceSectionFor(
      resource,
      activitiesByResource[entry.key] ?? const <String>{},
    );
    resource['section'] = section;
    actualCounts.update(section, (count) => count + 1, ifAbsent: () => 1);
  }

  if (!_sameSectionCounts(actualCounts, _expectedResourceSectionCounts)) {
    throw StateError(
      'Resource section counts changed. '
      'Expected $_expectedResourceSectionCounts; found $actualCounts.',
    );
  }
}

String? _sectionActivityForNode(Map<String, Object?> node) {
  final nodeType = node['nodeType'] as String? ?? '';
  return switch (nodeType) {
    'Farm' => 'farming',
    'Fish Drying Yard' || 'Fishing' => 'fishing',
    'Forest' || 'Lumbering' => 'lumbering',
    'Mining' => 'mining',
    'Mine' =>
      (node['name'] as String? ?? '').endsWith(' - Excavation')
          ? 'excavation'
          : 'mining',
    'Excavation' => 'excavation',
    'Gathering' || 'Mushrooms' => 'gathering',
    _ => null,
  };
}

String _resourceSectionFor(
  Map<String, Object?> resource,
  Set<String> workerActivities,
) {
  final itemId = _integer(resource['gameItemId']);
  final category = resource['category'] as String? ?? '';

  if (itemId != null && _otherResourceItemIds.contains(itemId)) {
    return 'other';
  }
  if (itemId != null && _plantWoodResourceItemIds.contains(itemId)) {
    return 'plantsWood';
  }
  if (category == 'Gathering meat' ||
      (itemId != null && _meatResourceItemIds.contains(itemId))) {
    return 'meat';
  }
  if (category == 'Gathering blood' ||
      category == 'Gathering hide' ||
      (itemId != null && _bloodHideResourceItemIds.contains(itemId))) {
    return 'bloodHides';
  }
  if (category == 'Mushrooms') {
    return 'mushrooms';
  }
  if (category == 'Seafood' ||
      category == 'Marine material' ||
      workerActivities.contains('fishing') ||
      (itemId != null && _seafoodMarineResourceItemIds.contains(itemId))) {
    return 'seafoodMarine';
  }
  if (category == 'Ore & minerals' ||
      workerActivities.contains('mining') ||
      (itemId != null && _oreMineralResourceItemIds.contains(itemId))) {
    return 'oresMinerals';
  }
  if (category == 'Timber & sap' ||
      category == 'Plants & flowers' ||
      category == 'Farm produce' ||
      category == 'Gatherables' ||
      workerActivities.contains('farming') ||
      workerActivities.contains('lumbering')) {
    return 'plantsWood';
  }
  return 'other';
}

bool _sameSectionCounts(Map<String, int> actual, Map<String, int> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (final entry in expected.entries) {
    if (actual[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

String _categoryFor(String name) {
  final value = name.toLowerCase();
  if (RegExp(r'timber|wood|log|sap|bark|branch').hasMatch(value)) {
    return 'Timber & sap';
  }
  if (value.contains('mushroom')) {
    return 'Mushrooms';
  }
  if (RegExp(
    r'vedelona|azalea|herb|grass|flower|bracken|rosebay|delotia|viola',
  ).hasMatch(value)) {
    return 'Plants & flowers';
  }
  if (RegExp(r'ore|shard|coal|powder|crystal|stone|opal').hasMatch(value)) {
    return 'Ore & minerals';
  }
  if (RegExp(
    r'potato|corn|wheat|barley|grape|strawberry|pumpkin|'
    r'pepper|olive|fig|date palm|nutmeg|teff|sunflower|cotton',
  ).hasMatch(value)) {
    return 'Farm produce';
  }
  if (RegExp(r'fish|octopus|jellyfish|shellfish').hasMatch(value)) {
    return 'Seafood';
  }
  if (RegExp(r'chicken|egg|honey').hasMatch(value)) {
    return 'Farm products';
  }
  return 'Worker material';
}

class _GatheringPointSource {
  const _GatheringPointSource({
    required this.itemId,
    required this.equivalentItemIds,
    required this.sourceFilename,
    required this.sha256,
    required this.overrideOption,
    required this.target,
    required this.label,
    required this.resources,
    this.maximumPointCount,
  });

  final int itemId;
  final List<int> equivalentItemIds;
  final String sourceFilename;
  final String sha256;
  final String overrideOption;
  final String target;
  final String label;
  final List<_GatheringPointResource> resources;
  final int? maximumPointCount;
}

class _GatheringPointResource {
  const _GatheringPointResource({
    required this.itemId,
    required this.name,
    required this.category,
    required this.aliases,
    required this.kind,
  });

  final int itemId;
  final String name;
  final String category;
  final List<String> aliases;
  final String kind;

  String get resourceId => 'item:$itemId';
}

class _GatheringPointPayload {
  const _GatheringPointPayload({required this.source, required this.bytes});

  final _GatheringPointSource source;
  final List<int> bytes;
}

class _GatheringPointAccumulator {
  _GatheringPointAccumulator({required this.x, required this.z});

  final double x;
  final double z;
  final Set<String> fieldSourceIds = <String>{};
  final Set<String> resourceIds = <String>{};
  final Set<String> targets = <String>{};
  final Set<String> kinds = <String>{};
  final Set<String> labels = <String>{};
}

class _BdoCodexNpcPointSource {
  const _BdoCodexNpcPointSource({
    required this.npcId,
    required this.pageTitle,
    required this.resourceId,
    required this.target,
    required this.label,
    required this.kind,
    required this.overrideOption,
    required this.expectedPointCount,
    required this.normalizedSha256,
  });

  final int npcId;
  final String pageTitle;
  final String resourceId;
  final String target;
  final String label;
  final String kind;
  final String overrideOption;
  final int expectedPointCount;
  final String normalizedSha256;

  Uri get uri => Uri.parse('https://bdocodex.com/us/npc/$npcId/');
}

class _BdoCodexPixelPoint {
  const _BdoCodexPixelPoint({
    required this.rawX,
    required this.rawY,
    required this.pixelX,
    required this.pixelY,
  });

  final String rawX;
  final String rawY;
  final double pixelX;
  final double pixelY;

  String get canonical => '$rawX,$rawY';
}

class _BdoCodexNpcPointPayload {
  const _BdoCodexNpcPointPayload({required this.source, required this.points});

  final _BdoCodexNpcPointSource source;
  final List<_BdoCodexPixelPoint> points;
}
