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
- **No duplicate bundle scan work.** One enumeration supplies the same native,
  text and forbidden-file rules; the main EXE is marker-scanned once. Checks
  across source, package and installation boundaries remain separate.
- **Retryable draft uploads.** A separate helper checks the reviewed manifest,
  local bytes and existing remote identity, reuses digest-verified assets and
  retries only missing uploads. It uses explicit timeouts, bounded attempts and
  sanitized attempt logs. It cannot create, publish or delete a release.

These changes do not cache compilation, skip privacy scans, remove the clean
build/staging boundary, reuse installed checks, or alter the updater. The
candidate builder prepares only; the separate uploader writes only to an
existing draft after explicit confirmation and never publishes it. Timing
records are explicitly **not resume receipts or release
verification**. Existing pinned Velopack caching is retained, not a new feature.

## Operator workflow

### Keep routine updates small

Do the approved release, not unrelated development. Do not add refactors,
dependency upgrades, repository cleanup or the optimization backlog to an
ordinary release. Read the standing playbook's **Routine releases: remove
unnecessary work** section for the complete operating rule.

Run each distinct required gate against the final inputs, and retain its
evidence. An upload error does not require another build or another local
install rehearsal when the verified artifacts have not changed. Retry only
the failed upload, checking the remote state first. Do not improvise different
upload formats or replace releases to work around a transient failure.

Keep actual public-route verification separate from local lifecycle checks.
Replaying the same local fresh-install, repair or stress case in a public-route
script does not test the public download. Removing such a repeat requires
checking the exact artifact hashes and earlier passing result, not assuming
that a previous run passed. Existing lifecycle scripts are unchanged by this
tooling patch.

The payload verifier now enumerates the unchanged built bundle once for its
native, text and forbidden-file rules, and scans the main EXE once instead of
twice. All existing rules remain. The inventory is not reused after packaging
or installation, where the bytes and verification obligations differ.

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

### Upload an already verified candidate without rebuilding it

`tool/release/publish_verified_release.ps1` synchronizes only the four entries in
the approved candidate manifest's `publicUploadArtifacts` with an **existing
draft**. It never builds, creates a release/tag, publishes, deletes remote state
or overwrites a conflicting artifact. A completed upload is not a completed
release: the owner still performs publication and the distinct public checks.

Use this after reviewing the non-upload acceptance evidence. The generated
manifest alone (including its historical `remainingBlockers` text) is not proof
that those checks passed. Pin its reviewed hash and the exact repository, tag
and commit; do not recalculate an approval hash merely to accept changed files.
Supply credentials through `GITHUB_TOKEN`, without printing them or putting
them in a command or log.

```powershell
.\tool\release\publish_verified_release.ps1 `
    -ManifestPath 'D:\ApprovedRelease\public-candidate-manifest.json' `
    -ApprovedManifestSha256 '<reviewed SHA-256>' `
    -ExpectedRepository 'OWNER/REPOSITORY' `
    -ExpectedTag 'v<approved version>' `
    -ExpectedSourceCommit '<reviewed full commit>' `
    -ConfirmReviewedArtifactReadiness `
    -ConfirmDraftAssetUpload
```

Replace the placeholders with reviewed release inputs. Retry the same command
against the same immutable manifest after a recoverable interruption: matching
uploaded assets are reused and an uploaded provisional name can be finalized
without retransmitting its bytes. Missing remote digests, identity changes,
unexpected assets and byte conflicts stop rather than trigger destructive
cleanup. Resolve a conflict explicitly; do not change the manifest, rebuild,
or switch to an upload command that overwrites files to bypass it.

Defaults are three upload attempts, a two-second inspection/retry delay,
60-second JSON-request timeout and 300-second upload timeout. Override
`MaxUploadAttempts`, `RetryDelaySeconds`, `JsonTimeoutSeconds` or
`UploadTimeoutSeconds` only for a concrete transport need. Authentication and
invalid-request failures stop instead of repeatedly sending the same request.
Sanitized attempt records are appended to `draft-upload-receipts.jsonl` beside
the manifest, or to an explicit absolute `ReceiptPath`. These logs explain
progress; they never substitute for rechecking remote digests on a resumed run.
An incomplete remote asset without a digest is retained and reported for owner
review, not silently deleted or treated as a successful upload.

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
central release metadata, validated build/helper/stage reuse, complete
publication orchestration, and patch-churn/lifecycle optimizations. Draft asset
retry/reconciliation is now implemented; final publication and public-route
verification remain separate owner steps.

The 2026-09-18 follow-up passed all six tooling suites on Windows PowerShell
5.1.26100.9444 and PowerShell 7.6.5. Each run included 12 cache scenarios and
39 inventory, 80 preflight/metrics, 81 builder-integration, 140 payload-scan and
63 draft-upload assertions. Combined runs took about 11 seconds per shell;
these are **tooling test timings**, not predicted release times. Local evidence:

- `build/release-tooling-tests/self-tests-20e9cb69248846df8df7288ce7221374`
- `build/release-tooling-tests/self-tests-deeed5d2a6354e50be2c8b9c9e40bd52`

Upload tests used mocked requests and disposable synthetic files. No public
upload, new application build, installer run or saved-data modification was
performed for this tooling-only change. Actual release-time improvement remains
to be measured on the next authorized release. No automatic recovery is claimed
for incomplete digest-less remote assets or conflicting draft state.

Keep the previous tooling revision for rollback. If an optimization fails,
revert its exact tooling commit in a separate reviewed checkout; never reset
the working Beta, touch user profiles, or overwrite accepted release evidence.
Do not deploy an app update just to adopt these publisher-side scripts.
