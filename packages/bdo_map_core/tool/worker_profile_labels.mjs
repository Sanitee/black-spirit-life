// Worker species from the pinned worker_static data, cross-checked against the
// English PC client character-name table (2026-10-31). Not combat race enums.
const labels = Object.freeze([
  'Goblin', 'Human', 'Giant', 'Papu', 'Fadus', 'Dwarf',
  'Dokkebi', 'Dolswe', 'Shellfolk',
]);

export function workerSpeciesLabel(species) {
  if (typeof species !== 'number' &&
      !(typeof species === 'string' && /^\d+$/.test(species))) {
    return `Worker type ${species}`;
  }
  const value = Number(species);
  return Number.isInteger(value) && value >= 0 && value < labels.length
    ? labels[value]
    : `Worker type ${species}`;
}
