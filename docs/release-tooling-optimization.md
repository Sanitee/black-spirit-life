# Release-tooling optimizations

Implemented tooling, not a new application release. The standing Live release
contract remains controlling: promote the complete approved Beta snapshot,
preserve its behavior, exclude publisher personal state, and verify installed
parity and preservation of each user's data. Live Release owns publication.

## Enabled changes

- **Verified historical-input reuse.** The existing candidate builder now caches
  the pinned previous feed/full package. The key includes repository, tag,
  channel, role, filename, expected size and SHA-256. Every use validates the
  complete hash and actual content identity; the feed must describe the pinned
  package. A run receives an independently validated copy.
- **Bounded download retries.** Transient transport failures retry only that
  historical input (three attempts by default). Each attempt has a unique
  partial file. Only a complete verified file becomes a cache entry. Integrity
  failures are not retried, hidden, or replaced. This is not byte-range resume.
- **Pruned source discovery.** Generated trees are excluded before recursion.
  The builder uses one inventory for its four source-boundary classifications.
  The independent source verifier uses the same discovery implementation but
  retains its own exclusion policy. Hidden/untracked production files remain
  visible, and unreadable paths, in-scope reparse points and case collisions
  fail closed. Existing tracked-generated-file checks remain separate.
- **Earlier prerequisites.** Before large historical downloads: resolve tools,
  check installed versions, required local inputs/script syntax, dependency
  metadata, source identity/cleanliness/privacy and release identity. The
  independent verifier's nonzero exit now explicitly stops the builder.
- **Stage measurements.** Stage starts/ends are printed. A completion or caught
  failure saves `stage-metrics.json` in that unique candidate run. It records
  duration, outcome and known byte/cache data; unavailable measurements are
  null, not fabricated zeroes. Raw exceptions and personal paths are not put in
  the metrics. An abrupt process termination may prevent the final save.
- **One tooling self-test command.** Maintained positive/negative fixtures test
  the helpers and actual extracted builder validators on PowerShell 5.1 and 7.
  Test logs, a hash-bound test list and outcomes are kept in an ignored unique
  `build/release-tooling-tests` directory.

These changes do not cache compilation, skip privacy scans, remove the clean
build/staging boundary, reuse installed checks, alter the updater, or publish
anything. Timing records are explicitly **not resume receipts or release
verification**. Existing pinned Velopack caching is retained, not a new feature.

## Operator workflow

1. Read the standing release contract and optimization playbook. Confirm the
   actual current Beta and coordinate with the Live Release owner.
2. Adopt the reviewed tooling commit. Preserve its complete `tool/release`
   directory and fixtures; do not copy just the builder.
3. Prepare the next reviewed source/version as usual. Existing version, tag,
   previous-commit/hash and ancestry gates are intentionally retained. This
   patch does **not** make an old version's constants valid for a new version or
   permit building a random tooling checkout. Review them for each release;
   do not disable them to make the command pass.
4. Resolve dependencies in the selected build checkout using the pinned lock
   and already approved toolchain. The release builder still uses `--no-pub`.
   A fresh Windows checkout may need the established symlink-capable build
   environment; preflight does not silently change Windows settings.
5. Run the tooling fixtures, then the unchanged application/release acceptance
   gates appropriate to the approved release plan.

```powershell
# Run from the selected repository root, once in each supported shell.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tool\test_release_tooling.ps1
pwsh.exe -NoProfile -NonInteractive -File .\tool\test_release_tooling.ps1
```

`-ExecutionPolicy Bypass` here is process-local and does not change machine or
user policy. The test runner executes a fixed maintained test list, captures
child exit codes and stops on failure. These are tooling tests, not a substitute
for the full application, privacy, installed lifecycle and parity checks.

The ordinary candidate command automatically enables caching and preflight:

```powershell
.\tool\build_public_stable_candidate.ps1 `
    -PublicGitHubRepository 'https://github.com/OWNER/REPOSITORY' `
    -ConfirmPublicCandidateOnly `
    -FlutterPath 'D:\Tools\flutter\bin\flutter.bat'
```

Use the actual approved repository/tool path. This still prepares artifacts
only; it never uploads or declares publication complete.

### Optional inputs

| Parameter | Meaning |
| --- | --- |
| `ReleaseInputCacheRoot` | Absolute ordinary directory; default is this checkout's `build/release-input-cache`. A shared **tool-owned** root preserves reuse between isolated release checkouts. Never choose Beta content, personal-data or protected evidence folders. |
| `PreviousFeedPath` | Read-only existing pinned historical feed to import on a cache miss. |
| `PreviousPackagePath` | Read-only existing pinned historical full package to import on a miss. |
| `OfflinePinnedInputs` | Reject a historical-input cache miss unless a valid local import is provided. This does **not** make Flutter, Velopack-tool acquisition or publication fully offline. |
| `MinimumFreeBytes` | Optional larger reserve for the project volume. Effective minimum is at least three previous-package sizes plus three previous-feed sizes. This conservative staging floor is **not** a guarantee of enough space for a full build; check other output/cache volumes too. |

All local imports must match the reviewed size/hash **and** actual package/feed
identity. A filename, timestamp or same byte count cannot authorize reuse.
Historical caching never replaces a fresh current-channel/publication check.

### Corruption, interruption and concurrent use

- A key-specific exclusive lock rejects competing acquisition. OS handles are
  released when the process exits; a retained `.lock` filename is not ownership.
- Partial/corrupt files are retained for diagnosis and never consumed or
  silently deleted. No automatic cache cleanup is included.
- After an integrity rejection, investigate the exact entry. To retry without
  altering evidence, choose a fresh tool-owned cache directory and obtain a
  valid input. Do not weaken the expected hash or content checks.
- Cache validation is not a source freeze. Re-enumerate/rehash when a source may
  have changed; never reuse a source list as a staged/installed file inventory.

## Repeat the real-input measurement

This optional measurement uses local **reviewed previous-release inputs** and
the actual builder's constants and validators. It performs no downloads, builds
or installations and retains its cache/copies under ignored build output.

```powershell
.\test\tool\measure_release_input_cache.ps1 `
    -PublicGitHubRepository 'https://github.com/OWNER/REPOSITORY' `
    -PreviousFeedPath 'D:\ApprovedPreviousRelease\releases.win-x64-stable.json' `
    -PreviousPackagePath 'D:\ApprovedPreviousRelease\previous-full.nupkg'
```

Record cold/import and warm measurements separately. `downloadedBytes` counts
bytes written to download files (including partial retries), not HTTP overhead.
Do not equate local import timing with cold network-download timing.

## Adoption status and remaining work

See [validation evidence](release-tooling-validation-2026-09-17.md). Only the
implemented subset above is enabled. The larger playbook still contains work:
central release metadata, validated build/helper/stage reuse, resumable upload,
publication orchestration, and patch-churn/lifecycle optimizations.

Keep the previous tooling revision for rollback. If an optimization fails,
revert its exact tooling commit in a separate reviewed checkout; never reset
the working Beta, touch user profiles, or overwrite accepted release evidence.
Do not deploy an app update just to adopt these publisher-side scripts.
