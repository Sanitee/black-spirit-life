import { readFileSync, writeFileSync } from 'node:fs';

const blockedAssets = new Set([
  'assets/rotations/luneye_matchlock_buffs_1424.png',
  'assets/rotations/luneye_matchlock_crystals_1321.png',
  'assets/rotations/luneye_sniper_buffs_1505.png',
  'assets/rotations/tshira_evil_2024_rotation.jpg',
]);

function sanitized(value) {
  if (Array.isArray(value)) {
    return value
      .filter(
        (entry) =>
          !(
            entry &&
            typeof entry === 'object' &&
            (blockedAssets.has(entry.asset) ||
              blockedAssets.has(entry.reference))
          ),
      )
      .map(sanitized);
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, sanitized(entry)]),
    );
  }
  return value;
}

for (const path of [
  'packages/bdo_gathering_companion/assets/data/spots.json',
  'packages/bdo_gathering_companion/assets/rotations/provenance.json',
]) {
  const source = JSON.parse(readFileSync(path, 'utf8'));
  writeFileSync(path, `${JSON.stringify(sanitized(source), null, 2)}\n`);
}
