// Preserve the original bundled artwork byte for byte. No image conversion.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';

const sourceUrl = new URL('../../../assets/data/app-data.json', import.meta.url);
const catalog = JSON.parse(readFileSync(sourceUrl, 'utf8'));
const icons = [
  [15672, 'Corrupted Magic Crystal', '16ad111ec79c5ff6219b1cd7075dfb25b7f90569245e62fc0f6771d17cb54ed0'],
  [15257, 'Crystal of Precise Destruction', '8e5f76fa7b837d597c2e458ed9d6cff57ef7139608f4cede87f71f2efbcf736b'],
  [15256, 'Crystal of Brutal Decimation', 'aa68e3c542b6129d7a2c0cf3d066f9586eb6ae6835fe19662778a727a5044f31'],
  [15690, "Glorious Crystal of Gallantry - Ah'krad", '253d2e17b3eeed58d33374ff2e972efd8a51f0850679d95d5a982d294828d936'],
  [15736, "Girin's Tear", '2dbd94e5862d71f5e2ea4510c0c344f38775e3f79b99e021c0f070f1b502ed36'],
];
const entries = [];
for (const [id, name, expected] of icons) {
  const source = catalog.processing.itemIcons[name];
  if (!source?.startsWith('data:image/webp;base64,')) throw new Error(`Missing original: ${name}`);
  const bytes = Buffer.from(source.split(',')[1], 'base64');
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  if (sha256 !== expected) throw new Error(`Artwork changed: ${name}`);
  const asset = `assets/icons/items/${id}.webp`;
  const target = new URL(`../${asset}`, import.meta.url);
  if (existsSync(target) && !readFileSync(target).equals(bytes)) throw new Error(`Destination differs: ${asset}`);
  writeFileSync(target, bytes);
  entries.push({ id, name, asset, byteLength: bytes.length, sha256, source: `assets/data/app-data.json#processing.itemIcons[${JSON.stringify(name)}]` });
}
writeFileSync(new URL('../assets/icons/items/matchlock-advice-provenance.json', import.meta.url), JSON.stringify({ owner: 'Pearl Abyss', transformation: 'None; unchanged bundled WebP bytes', entries }, null, 2) + '\n');
console.log(`Verified ${entries.length} original matchlock advice icons.`);
