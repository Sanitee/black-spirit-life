import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const expectedSources = Object.freeze({
  'exploration.json':
    '2bededd520be17ef50b99ba87e17cf00a1958053580272461d60ac4975236170',
  'plantzone_drops.json':
    'c70b4397c800eacca554d12fa2436615c58139bf0c77801002f983d4f5cfb08d',
  'distances_tk2pzk.json':
    '695afdd060343b89ba8af2a4716a2429f267963b61ee96bb108175f08fcd303b',
  'worker_static.json':
    'd8af3f3e5e5ab1889b57e2b285099556533c7b22effbef741560a3ae14273bd7',
  'region_workers.json':
    '42a78602817633b6737e194ce29a3425b9656a894fae86efcc2ccd32e8b4ebde',
});

const packageRoot = resolve(import.meta.dirname, '..');
const sourceDirectory = resolve(process.argv[2] ?? '');
const outputPath = resolve(
  process.argv[3] ??
    join(packageRoot, 'assets', 'data', 'worker_economics.json'),
);
const mapPath = join(packageRoot, 'assets', 'data', 'resource_map.json');

if (!process.argv[2]) {
  throw new Error(
    'Pass the bdo-empire src/bdo_empire/data directory as the first argument.',
  );
}

const sourceBytes = {};
for (const [name, expectedSha256] of Object.entries(expectedSources)) {
  const bytes = readFileSync(join(sourceDirectory, name));
  const actualSha256 = createHash('sha256').update(bytes).digest('hex');
  if (actualSha256 !== expectedSha256) {
    throw new Error(
      `${name} checksum mismatch.\n` +
        `Expected: ${expectedSha256}\nActual:   ${actualSha256}`,
    );
  }
  sourceBytes[name] = bytes;
}

const parseSource = (name) => JSON.parse(sourceBytes[name].toString('utf8'));
const exploration = parseSource('exploration.json');
const drops = parseSource('plantzone_drops.json');
const distancesByRegion = parseSource('distances_tk2pzk.json');
const workerStatic = parseSource('worker_static.json');
const workersByRegion = parseSource('region_workers.json');
const resourceMap = JSON.parse(readFileSync(mapPath, 'utf8'));

const productionResourceIds = new Set(
  resourceMap.workerNodes
    .filter((node) => node.isProductionNode && node.isResourceNode)
    .map((node) => String(node.id)),
);
const mapNodeIds = new Set(
  resourceMap.workerNodes.map((node) => String(node.id)),
);

const townByRegion = new Map();
for (const [nodeId, node] of Object.entries(exploration)) {
  if (node.is_worker_npc_town) {
    townByRegion.set(String(node.region_key), String(nodeId));
  }
}

const speciesLabel = (workerType) => {
  switch (Number(workerType)) {
    case 0:
      return 'Human';
    case 1:
      return 'Goblin';
    case 2:
      return 'Giant';
    default:
      return `Worker type ${workerType}`;
  }
};

const round = (value, digits = 4) => {
  const scale = 10 ** digits;
  return Math.round((value + Number.EPSILON) * scale) / scale;
};

const medianLevel40Profile = (workerType, characterKey) => {
  const stat = workerStatic[String(characterKey)];
  if (!stat) {
    throw new Error(`Missing worker_static record ${characterKey}.`);
  }

  let workSpeed = Number(stat.wspd);
  let movementBonus = 0;
  let luck = Number(stat.luck);
  for (let level = 2; level <= 40; level += 1) {
    workSpeed += (Number(stat.wspd_lo) + Number(stat.wspd_hi)) / 2;
    movementBonus += (Number(stat.mspd_lo) + Number(stat.mspd_hi)) / 2;
    luck += (Number(stat.luck_lo) + Number(stat.luck_hi)) / 2;
  }
  const movementSpeed =
    Number(stat.mspd) * (1 + movementBonus / 1_000_000);
  const species = Number(stat.species);
  return {
    id: `${workerType}:${characterKey}`,
    label: speciesLabel(workerType),
    workerType: Number(workerType),
    characterKey: Number(characterKey),
    isGiant: [2, 4, 8].includes(species),
    workSpeed: round(workSpeed / 1_000_000, 2),
    movementSpeed: round(movementSpeed / 100, 2),
    luck: round(luck / 10_000, 2),
  };
};

const towns = {};
for (const [regionId, townNodeId] of [...townByRegion.entries()].sort(
  ([left], [right]) => Number(left) - Number(right),
)) {
  const regionWorkers = workersByRegion[regionId];
  if (!regionWorkers || !mapNodeIds.has(townNodeId)) {
    continue;
  }
  const profiles = Object.entries(regionWorkers)
    .map(([workerType, characterKey]) =>
      medianLevel40Profile(workerType, characterKey),
    )
    .sort(
      (left, right) =>
        left.workerType - right.workerType ||
        left.characterKey - right.characterKey,
    );
  towns[townNodeId] = {
    nodeId: townNodeId,
    regionId: Number(regionId),
    baseWorkerSlots: 1,
    profiles,
  };
}

const distancesByNode = new Map();
for (const [regionId, distanceRows] of Object.entries(distancesByRegion)) {
  const townNodeId = townByRegion.get(regionId);
  if (!townNodeId || !towns[townNodeId]) {
    continue;
  }
  for (const row of distanceRows) {
    if (!Array.isArray(row) || row.length < 2) {
      throw new Error(`Invalid distance row in region ${regionId}.`);
    }
    const nodeId = String(row[0]);
    if (!productionResourceIds.has(nodeId)) {
      continue;
    }
    const distance = Number(row[1]);
    if (!Number.isFinite(distance) || distance < 0) {
      throw new Error(
        `Invalid distance ${row[1]} for town ${townNodeId}, node ${nodeId}.`,
      );
    }
    // The pinned source uses ten million as an unreachable-path sentinel.
    if (distance >= 10_000_000) {
      continue;
    }
    const townDistances = distancesByNode.get(nodeId) ?? {};
    townDistances[townNodeId] = distance;
    distancesByNode.set(nodeId, townDistances);
  }
}

const sortedYieldMap = (value) =>
  Object.fromEntries(
    Object.entries(value ?? {})
      .map(([itemId, quantity]) => [String(itemId), round(Number(quantity), 8)])
      .filter(([, quantity]) => Number.isFinite(quantity) && quantity >= 0)
      .sort(([left], [right]) => Number(left) - Number(right)),
  );

const productionNodes = {};
for (const nodeId of [...productionResourceIds].sort(
  (left, right) => Number(left) - Number(right),
)) {
  const drop = drops[nodeId];
  if (!drop) {
    throw new Error(`No production economics record for map node ${nodeId}.`);
  }
  const townDistances = distancesByNode.get(nodeId) ?? {};
  if (Object.keys(townDistances).length === 0) {
    throw new Error(`No worker-town distance for map node ${nodeId}.`);
  }
  productionNodes[nodeId] = {
    nodeId,
    baseWorkload: Number(drop.workload),
    workerTypes: [...new Set(exploration[nodeId]?.worker_types ?? [])]
      .map(Number)
      .sort((left, right) => left - right),
    standardYields: sortedYieldMap(drop.unlucky),
    giantYields: sortedYieldMap(drop.unlucky_gi ?? drop.unlucky),
    luckyBonusYields: sortedYieldMap(drop.lucky),
    townDistances: Object.fromEntries(
      Object.entries(townDistances).sort(
        ([left], [right]) => Number(left) - Number(right),
      ),
    ),
  };
}

const output = {
  schemaVersion: 1,
  manifest: {
    datasetVersion: '2026.07.01-bdo-empire-0.8.1-stable',
    generatedAt: '2026-07-29T00:00:00.000Z',
    sourceRepository: 'https://github.com/Thell/bdo-empire',
    sourceCommit: '4a24b6f42926543e5f3eae5c8c559ebd689b698c',
    sourcePackageVersion: '0.8.1',
    sourceLicenseExpression: 'Unlicense',
    upstreamWorkermanCommit: 'cb4965a5be4e68f231c4bbad7b7a87003e27038b',
    permittedUse:
      'The bdo-empire calculation code is retained under the Unlicense. ' +
      'Workerman-derived factual inputs are project-owner approved for ' +
      'attributed use in the completely free, noncommercial Black Spirit Life ' +
      'fan project; no separate Workerman licence file was found. Retain ' +
      'credits and respond promptly to any substantiated correction or removal ' +
      'request from Shrddr.',
    sourceSha256: expectedSources,
    assumptions: [
      'Expected drop quantities and workload come from the pinned source files.',
      'Worker profiles are arithmetic level-40 medians without skill bonuses.',
      'Every verified town starts with one base worker slot; user availability still needs configuration.',
    ],
  },
  towns,
  productionNodes,
};

if (Object.keys(productionNodes).length !== productionResourceIds.size) {
  throw new Error('Not every mapped resource production node was emitted.');
}
if (Object.keys(towns).length !== 30) {
  throw new Error(
    `Expected 30 worker towns from the pinned source, got ${Object.keys(towns).length}.`,
  );
}

writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
const outputBytes = readFileSync(outputPath);
const outputSha256 = createHash('sha256').update(outputBytes).digest('hex');
console.log(
  JSON.stringify(
    {
      outputPath,
      bytes: outputBytes.length,
      sha256: outputSha256,
      towns: Object.keys(towns).length,
      productionNodes: Object.keys(productionNodes).length,
    },
    null,
    2,
  ),
);
