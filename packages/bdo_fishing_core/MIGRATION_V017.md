# Stable v0.1.7 Fishing migration

The Fish Companion performs one offline migration before its localhost service
starts. It reads only `fishing/fishing-journal.json` below the selected personal
data root and writes the companion database to
`fishing/fish-journal.sqlite3` below that same root.

The migration normally runs only when the companion database is absent or
contains no sessions, catches, sales, or durable settings. A non-empty
destination is never merged with or replaced by the legacy file except for the
narrow matching unpublished-v1 repair documented below. The source JSON
remains in place, and its exact bytes are also archived as
`migration-archive/v0.1.7/fishing-journal.<sha256>.json`.

## Exact mapping

- Legacy session and loadout IDs are preserved verbatim.
- `fishing` maps to `rod`; `harpooning` maps to `harpoon`.
- Session creation, start, and update timestamp strings are preserved verbatim.
  The end timestamp is deterministically calculated from the start timestamp
  plus `durationMinutes` because v0.1.7 did not store an end timestamp.
- Location, loadout ID/name, mastery, tool, retained-fish count, notes, and
  received silver are stored in dedicated companion fields.
- `silverReceived` remains labelled legacy received silver. It is not converted
  into a sale, and `total_value` remains zero.
- v0.1.7 stored only an aggregate fish count. Migrated sessions therefore have
  no fabricated catch items/species and are marked `legacy-aggregate-only`.
- The journal shows each migrated aggregate's fish total, notes, and legacy
  received silver. These records are read-only: edit, recalculation, and sale
  actions are unavailable, so the current app cannot reinterpret or sell the
  same legacy record again.
- v0.1.7 stored no map point or zone colour. No zone colour is generated.
- The current schema requires an internal fishing-style value. Migrated records
  use `afk` only inside SQLite as a storage compatibility value. Their public
  API returns style as unknown, the UI identifies them as legacy aggregate
  data, and AFK/active session or stats filters exclude them.

Every valid legacy loadout becomes an accessible current profile in source
order. No profile is selected as active because v0.1.7 did not store that
personal choice. The current profile contract accepts
all 1,000 loadouts allowed by v0.1.7, 160-character exact IDs,
120-character exact nonblank names, optional exact 200-character tool strings,
and exact 4,000-character notes. Creation and update timestamp strings are
also retained and validated together without normalization. Names remain
non-unique just as they were in v0.1.7; when names compare equal without case,
the UI derives a method/mastery/occurrence suffix for selection while leaving
the durable name and identity untouched. Arbitrary or blank old tool strings
remain editable and usable instead of being replaced by a current suggestion.
Fishing level, trading level, and auto-fishing reduction remain explicitly
unset because v0.1.7 loadouts did not contain them; opening and saving a profile
does not fabricate those personal calculation inputs.

Every original loadout is additionally kept verbatim in the migration archive
setting and exact JSON backup. On a new migration, the Fish profile manager
confirms that all loadouts were imported and shows the retained backup path. A nonzero
archive-only count from the earlier unpublished v1 migration is treated as a
repair condition, not as successful migration.

## Idempotence and storage boundary

The committed marker includes both migration version and source SHA-256. A
matching rerun adds nothing. The database transaction commits every profile,
the complete loadout archive, aggregate sessions, and marker together. When a
matching unpublished v1 marker is found, migration v2 enriches the profiles
already present with their notes/timestamps and appends every loadout v1 had
omitted. Existing profile edits and the active selection remain intact, and
the already migrated sessions are not inserted again. A source profile which
v1 did import but the user subsequently deleted stays deleted; the marker and
profile notice report that preserved choice separately from available profiles
and from migration omissions.
The durable profile store allows 1,016 records so that the worst-case v1
upgrade can retain all 1,000 valid legacy loadouts plus all 16 current-only
profiles that a user could have created after that preview migration. Fresh
v0.1.7 source validation remains capped at its original 1,000 loadouts.
If a profile created after unpublished v1 reused the exact id of a loadout that
v1 could not represent, both remain accessible: the current profile and active
selection stay untouched, while the legacy profile receives a deterministic
current id and retains its exact original id as durable migration metadata.
Legacy aggregate-session references are redirected to that migrated profile.

The immutable Fishing map, species, location, price, recognition, and related
reference databases/datasets remain bundled with the installed package. They
are product/reference content, not personal profile or journal databases.
Disposable online-derived reference cache files use a separate, explicitly
supplied cache root. The process-wide WebView2 profile uses the explicitly
supplied shared `<selected root>/webview2` directory, and both Fish and
Gathering close their native controllers before a root move. Fish panel opacity
is session-only rather than browser-persisted. No immutable/reference file is
copied below the selected personal-data root; only the user-created journal and
profile database, its SQLite sidecars, the shared browser profile, and the
retained legacy migration archive live there.
