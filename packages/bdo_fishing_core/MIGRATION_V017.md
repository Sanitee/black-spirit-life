# Importing v0.1.7 Fishing saves

Before the local service starts, the app can import `fishing/fishing-journal.json` into `fishing/fish-journal.sqlite3` under the selected save folder. The source stays in place and is copied byte-for-byte to `migration-archive/v0.1.7/fishing-journal.<sha256>.json`.

Import normally runs only when the destination has no sessions, catches, sales or saved settings. It never merges into or replaces a used database, except for the specific unpublished-v1 repair below.

## What is kept

- Exact session/profile IDs, names, notes and creation/start/update timestamps.
- Method: `fishing` becomes `rod`; `harpooning` becomes `harpoon`.
- Location, profile, mastery, tool, fish count and received silver.
- End time is calculated from start time plus `durationMinutes`, because the old format did not store it.

Old sessions contain totals, not individual fish. They are read-only `legacy-aggregate-only` records: no invented catches, species, sales or map colours; no editing, recalculation or resale. `silverReceived` remains legacy received silver, and `total_value` stays zero.

SQLite uses `afk` only to satisfy its internal schema. The public API reports unknown style; AFK/active filters exclude these records.

## Profiles

Import all valid profiles in source order without choosing an active one. Preserve duplicate names and blank/custom tools. Selection labels may add method/mastery/occurrence to distinguish duplicates without changing saved names.

Keep the old limits: 1,000 profiles, 160-character IDs, 120-character nonblank names, optional 200-character tools and 4,000-character notes. Validate timestamps together without changing their text. Fishing level, Trading level and auto-fishing reduction stay unset; opening or saving a profile must not invent them.

Keep a complete loadout archive and report the backup location. An archive-only count from the unpublished v1 importer is a repair condition, not a complete import.

## Repeat imports and v1 repair

A marker stores the migration version and source SHA-256. Profiles, archive, sessions and marker commit in one transaction. A matching rerun adds nothing.

For the matching unpublished v1 marker, v2 adds omitted profiles and restores available notes/timestamps. It preserves user edits and active selection, avoids duplicate sessions and does not restore profiles the user deleted. The marker distinguishes those deletions from omissions.

The destination allows 1,016 profiles: 1,000 legacy plus 16 created after v1. New legacy input is still capped at 1,000. If an omitted legacy ID conflicts with a newer profile, preserve the newer one; assign the imported profile a deterministic ID, retain its original ID as metadata and redirect its legacy session references.

## Save and reference files

Bundled map, species, price and recognition data are reference files, not personal saves. Disposable online reference caches use a separate supplied cache root.

Personal journals, profiles, SQLite sidecars, archives and the shared `<selected root>/webview2` browser profile stay under the selected save folder. Fishing and Gathering close browser controllers before moving that folder. Fish panel opacity is session-only. Never copy immutable reference files into personal saves.
