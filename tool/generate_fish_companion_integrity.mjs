import { createHash } from 'node:crypto';
import {
  readdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import { join, relative, sep } from 'node:path';

const packageRoot = join('packages', 'bdo_fishing_core');
const payloadRoot = join(packageRoot, 'assets', 'fish_companion');
const manifestPath = join(
  payloadRoot,
  'data',
  'install-critical-manifest.v1.json',
);
const integrityPath = join(
  packageRoot,
  'assets',
  'fish_companion_integrity.json',
);

const sha256 = (bytes) =>
  createHash('sha256').update(bytes).digest('hex');
const normalized = (path) => relative(payloadRoot, path).split(sep).join('/');

function filesUnder(root) {
  const result = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== '__pycache__') result.push(...filesUnder(path));
    } else if (entry.isFile() && !entry.name.endsWith('.pyc')) {
      result.push(path);
    }
  }
  return result;
}

function receipt(path) {
  const bytes = readFileSync(join(payloadRoot, ...path.split('/')));
  return { path, byteCount: bytes.length, sha256: sha256(bytes) };
}

const immutablePaths = [
  'runtime/fish_companion_service.exe',
  'static/app.css',
  'static/app.js',
  'static/index.html',
];
const snapshotPaths = [
  'data/cache/derived-index.v1.json',
  'data/cache/fish.json',
  'data/cache/meta.json',
  'data/cache/zone_mask.v8.bin',
  'data/cache/zones.json',
];
writeFileSync(
  manifestPath,
  `${JSON.stringify(
    {
      schemaVersion: 1,
      immutableFiles: immutablePaths.map(receipt),
      snapshotFiles: snapshotPaths.map(receipt),
    },
    null,
    2,
  )}\n`,
);

const files = ['static', 'backend', 'recognizer', 'data']
  .flatMap((root) => filesUnder(join(payloadRoot, root)))
  .sort((left, right) => {
    const leftPath = normalized(left).toLowerCase();
    const rightPath = normalized(right).toLowerCase();
    return leftPath < rightPath ? -1 : leftPath > rightPath ? 1 : 0;
  });
let sourceByteCount = 0;
const lines = files.map((path) => {
  const bytes = readFileSync(path);
  sourceByteCount += bytes.length;
  return `${normalized(path)}|${bytes.length}|${sha256(bytes)}`;
});
const service = readFileSync(
  join(payloadRoot, 'runtime', 'fish_companion_service.exe'),
);
const integrity = {
  source:
    'Black Spirit Life 0.1.12 Fish payload with local-only empty-on-first-run personal storage',
  sourceFileCount: files.length,
  sourceByteCount,
  sourceAggregateSha256: sha256(Buffer.from(lines.join('\n'), 'utf8')),
  serviceByteCount: service.length,
  serviceSha256: sha256(service),
};
writeFileSync(integrityPath, `${JSON.stringify(integrity, null, 2)}\n`);
process.stdout.write(`${JSON.stringify(integrity)}\n`);
