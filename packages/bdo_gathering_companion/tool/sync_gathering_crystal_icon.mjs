// Copy the already-bundled game icon unchanged; no network or image conversion.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';

const catalog = JSON.parse(readFileSync(new URL('../../../assets/data/app-data.json', import.meta.url), 'utf8'));
const name = 'Crystal of Breathing Verdure';
const source = catalog.itemIcons[name] ?? catalog.processing.itemIcons[name];
if (!source?.startsWith('data:image/webp;base64,')) throw new Error('Missing reviewed WebP icon');
const bytes = Buffer.from(source.split(',')[1], 'base64');
const expected = '592e5c76223e5ca1bed1a277fe33c2bfd9f36c45fc6f4c00097a25042eba5f2b';
if (createHash('sha256').update(bytes).digest('hex') !== expected) throw new Error('Source artwork changed; review before copying');
const destination = new URL('../assets/icons/items/15288.webp', import.meta.url);
if (existsSync(destination) && !readFileSync(destination).equals(bytes)) throw new Error('Existing destination differs; review it first');
writeFileSync(destination, bytes);
console.log(`Verified and copied ${name} (${bytes.length} bytes).`);
