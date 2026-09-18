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
- **Guarded source promotion.** Explicit reviewed generated directories are
  pruned before copying. File-level release changes require matching original
  and replacement hashes. A new candidate is exposed only after its inventory
  matches and source/overlay stability is rechecked. Existing candidates and
  the working Beta remain untouched.
- **Plan-derived release identity.** The builder, measurement helper and
  lifecycle setup consume a hash-pinned release plan. Version transitions and
  previous package identities no longer depend on editing copied constants.
  The exact expected commit/tag and reviewed ancestry remain enforced.

These changes do not cache compilation, remove the clean build/staging boundary,
waive privacy obligations, or alter the updater. Conditional reuse is limited
to the explicitly hash-bound evidence described below. The
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
that a previous run passed. The maintained lifecycle harness implements this
boundary; old timestamped evidence remains unchanged.

The payload verifier now enumerates the unchanged built bundle once for its
native, text and forbidden-file rules, and scans the main EXE once instead of
twice. All existing rules remain. The inventory is not reused after packaging
or installation, where the bytes and verification obligations differ.

1. Read the standing release contract and optimization playbook. Confirm the
   actual current Beta and coordinate with the Live Release owner.
2. Adopt the reviewed tooling commit. Preserve its complete `tool/release`
   directory and fixtures; do not copy just the builder.
3. Prepare and approve a release-plan JSON and pin its SHA-256. The builder now
   reads transient version, tag, previous-input hashes and reviewed ancestry
   from that plan instead of requiring edits to historical constants. Exact
   source commit/tag, clean-source, ancestry and privacy checks remain. A plan
   does not authorize publication or make an arbitrary tooling checkout an
   approved application snapshot.
4. Resolve dependencies in the selected build checkout using the pinned lock
   and already approved toolchain. The release builder still uses `--no-pub`.
   A fresh Windows checkout may need the established symlink-capable build
   environment; preflight does not silently change Windows settings.
5. Validate the tooling once for its exact inputs/runtime. Rerun the complete
   tooling fixtures when tooling, policy, fixtures or relevant runtime changes;
   do not automatically repeat every synthetic negative case for an app-only
   patch using that unchanged reviewed baseline. Each release still runs its
   own plan/input preflight and all distinct application/release gates. Missing
   or mismatched baseline evidence requires revalidation, not assumed reuse.

```powershell
# Run from the selected repository root, once in each supported shell.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tool\test_release_tooling.ps1
pwsh.exe -NoProfile -NonInteractive -File .\tool\test_release_tooling.ps1
```

`-ExecutionPolicy Bypass` here is process-local and does not change machine or
user policy. The test runner executes a fixed maintained test list, captures
child exit codes and stops on failure. These are tooling tests, not a substitute
for the full application, privacy, installed lifecycle and parity checks.
The test manifest records supporting-file hashes, shell/runtime evidence and
explicit success/input-stability flags. It rejects changed/added tooling inputs
during the test run. This is review evidence, not an automatic stage-skip token;
the operator must still compare all relevant inputs and runtime context.
The Git-history fixtures require Python 3.9+ and Git. If Python is not a usable
executable on PATH, pass `-PythonPath '<resolved Python executable>'` to the
runner (or set `BSL_RELEASE_PYTHON` for this process). The runner restores any
prior value after its child tests; it does not modify machine settings.

The ordinary candidate command automatically enables caching and preflight:

```powershell
.\tool\build_public_stable_candidate.ps1 `
    -ReleasePlanPath 'D:\ApprovedRelease\release-plan.json' `
    -ApprovedReleasePlanSha256 '<reviewed SHA-256>' `
    -ConfirmPublicCandidateOnly `
    -FlutterPath 'D:\Tools\flutter\bin\flutter.bat'
```

Use the actual approved plan/tool path. This still prepares artifacts
only; it never uploads or declares publication complete.

Start from [the runtime schema example](release-plan.v1.example.json), not the
older proposed plan in the standing optimization folder. The example passes
the metadata parser but deliberately contains dummy commits, lengths and hashes:
it is not a usable release approval. Replace those with independently reviewed
current evidence. Keep the plan outside committed candidate source (it contains
the expected candidate commit); the builder freezes a hash-verified copy beside
the generated manifest.

`identity` describes the intended release and previous published version;
`source` pins commits and tags; `historicalInputs` pins the previous feed/full
package; `lifecycle` pins the old setup and synthetic migration fixture version.
The fixture's legacy version, installed previous version, and target version
have different meanings. Do not set them all to the new version to satisfy a
failed assertion. `remainingBlockers` records still-required checks; the plan
does not claim they passed. Beta inventory and reviewed file-level adaptations
remain separately bound promotion evidence, not replaced by the Git commit.

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

### Promote the approved working tree without copying temporary outputs

`tool/release/promote_source.ps1` inventories the actual filesystem, including
dirty and untracked production files. It does not substitute Git HEAD. Supply a
separately reviewed promotion plan with schema version 1, an `approvalReference`,
and explicit arrays named `pruneDirectories`, `omitFiles`, `replaceFiles` and
`addFiles`. Every entry has a relative `path` and a reviewed `reason`.

- `pruneDirectories` names exact transient directory paths. They are excluded
  before descent; their contents are not copied or hashed. There is no implicit
  exclusion for `.git`, `data`, `cache`, or entire product modules. Review the
  intended generated/source-control exclusions explicitly.
- `omitFiles` also requires `expectedSha256` for the original file.
- `replaceFiles` requires `expectedSha256`, `overlayPath` and `overlaySha256`.
- `addFiles` requires `overlayPath` and `overlaySha256`; its target must not exist.

The overlay is a separate read-only input directory, not a whole-module override.
Use an empty ordinary overlay directory if no files are added or replaced.

```powershell
.\tool\release\promote_source.ps1 -Mode Inventory `
    -SourceRoot 'D:\ApprovedBeta' -OverlayRoot 'D:\ReviewedOverlay' `
    -PlanPath 'D:\ApprovedRelease\promotion-plan.json' `
    -ExpectedPlanSha256 '<reviewed promotion-plan SHA-256>'

.\tool\release\promote_source.ps1 -Mode Promote `
    -SourceRoot 'D:\ApprovedBeta' -OverlayRoot 'D:\ReviewedOverlay' `
    -PlanPath 'D:\ApprovedRelease\promotion-plan.json' `
    -ExpectedPlanSha256 '<same reviewed promotion-plan SHA-256>' `
    -ExpectedSourceFingerprint '<reviewed source fingerprint from Inventory>' `
    -OutputRoot 'D:\NewCandidate'
```

The example paths are placeholders, not instructions to create another Beta.
Confirm the actual approved working tree each time. Inventory mode writes no
files. Promote mode requires a new, non-overlapping output location; it exposes
`source/` and `promotion-report.json` only after candidate hashes and source/overlay
stability pass. The report includes retained source and candidate inventories,
every reviewed file adaptation, and explicit pruned-directory reasons.
Failures retain separate staging for diagnosis. No old candidate, rollback,
personal state or source is deleted. This is source promotion evidence, not
application, privacy, lifecycle or publication acceptance.

### Reuse maintained lifecycle setup, not old timestamped scripts

`tool/release/run_lifecycle_rehearsal.ps1` keeps the accepted upgrade/profile
checks in maintained tooling. The associated Python verifiers, Gathering gate
and explicitly synthetic Planner fixture live under `tool/release/lifecycle`.
The source fixture's legacy version is separate from the expected preserved
Planner version and the independently checked installed target version.

Supply the reviewed release plan/hash, candidate manifest/hash, pinned previous
setup, exact candidate `ProjectRoot`, resolved Python/Flutter/Edge executables,
and new separate `EvidenceRoot`/`DisposableBase` directories. The disposable
directory's leaf name must start with `bsl-lifecycle-`. Outputs cannot overlap
source, candidate, tooling or known personal-data locations.

```powershell
$lifecycleInputs = @{
    ReleasePlanPath = 'D:\ApprovedRelease\release-plan.json'
    ApprovedReleasePlanSha256 = '<reviewed plan SHA-256>'
    CandidateManifestPath = 'D:\CandidateRun\public-candidate-manifest.json'
    ApprovedCandidateManifestSha256 = '<reviewed manifest SHA-256>'
    PreviousSetupPath = 'D:\ReviewedInputs\BlackSpiritLife.App-win-x64-stable-Setup.exe'
    ProjectRoot = 'D:\ApprovedCandidateSource'
    EvidenceRoot = 'D:\ReleaseEvidence\local-new-run'
    DisposableBase = 'D:\ReleaseTests\bsl-lifecycle-local-new-run'
    PythonPath = '<resolved Python executable>'
    FlutterPath = '<resolved Flutter launcher>'
    EdgePath = '<resolved Edge executable>'
}
.\tool\release\run_lifecycle_rehearsal.ps1 @lifecycleInputs -Mode LocalFeed -PreflightOnly
```

Preflight verifies inputs without installing, modifying registry/shortcuts,
starting the app or creating lifecycle output. A real rehearsal requires
PowerShell 7 and `-ConfirmDisposableLifecycle` in place of `-PreflightOnly`.
Windows PowerShell 5.1 is supported for metadata/preflight/self-tests, not the
full stateful lifecycle. Only run that rehearsal as part of authorized release
work with an isolated synthetic setup; it temporarily backs up/restores the
app's uninstall registration and shortcut.

For `PublicRoute`, use **new** evidence/disposable roots and supply
`-LocalFeedReceiptPath` plus `-ApprovedLocalFeedReceiptSha256`. Reuse requires
passed local evidence matching the plan, candidate, harness, fixture and
verification context. The actual public update route, resulting installed
version/payload and personal-data preservation are still checked. Only the
duplicate local fresh-install/repair/stress tail is reused. A changed helper,
runtime context or candidate invalidates that reuse.

This harness exercises the manifest's `velopack-setup`. It does not replace
separate themed-installer/public-download acceptance, UI parity, or the other
release gates. A preflight or tooling fixture pass is never an installed-test
pass. The first real use of this maintained harness must be recorded as such;
this tooling-only change did not execute a new installation.

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

### Reuse unchanged Git content checks after a reviewed cold baseline

`tool/release/verify_git_object_privacy.py` is a new maintained history scanner,
not a byte-for-byte recreation of the earlier ad-hoc command (its source was not
preserved). Historical schema-1 scan reports cannot serve as cache receipts.
Run a new reviewed cold scan first; do not replace an existing acceptance gate
merely because the synthetic tests pass.

```powershell
& '<resolved Python executable>' .\tool\release\verify_git_object_privacy.py `
    --repository 'D:\ReviewedClone' `
    --expected-commit '<reviewed full commit>' `
    --expected-tag 'refs/tags/v<approved version>' `
    --expected-refs 'D:\ApprovedRelease\expected-refs.json' `
    --policy-sha256 '<reviewed verify_production_source.ps1 SHA-256>' `
    --powershell '<resolved PowerShell executable>' `
    --receipt 'D:\ApprovedRelease\history-cold.json'
```

`expected-refs.json` is the reviewed exact JSON map of ref names to Git object
IDs. A local prepublication clone and the final remote clone can legitimately
have different maps; review each one rather than automatically accepting the
observed refs. The script checks the intended HEAD and peeled tag, full object
integrity, and all historical path contexts on every run.

For a subsequent scan, supply `--prior-receipt` and its independently approved
`--prior-receipt-sha256`, and use a new receipt output. Reuse requires matching
scanner, policy, private-marker and runtime identities plus passed complete
per-object/per-mode evidence. New content is scanned; an old blob at a newly
forbidden path still fails. Git integrity and path checks are never skipped.
This saves repeated content-policy decoding, not all disk reads: `git fsck`
still independently validates object integrity.

The policy is extracted as static data from the trusted maintained source
verifier, never executed from the clone. Binary blobs receive its SQLite-header
check, not a newly claimed universal secret scan. Text uses the maintained
secret/machine-path rules; commit/tag metadata is also checked. Unsupported text
encoding and oversized text fail closed. Source, compiled payload, installer,
installed behavior and actual public-route checks remain independent.

Known cold-baseline review item: the previous tooling commit contains a literal
**synthetic** machine path inside the payload-scan test. The current test now
constructs that same fixture at runtime, but history retains the old bytes. Do
not call a historical scan passed or silently waive that finding; resolve any
precise reviewed fixture exception separately before adopting cached history
results for a real release. No history is rewritten by this tool.

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
the approved release plan and actual builder's validators. It performs no downloads, builds
or installations and retains its cache/copies under ignored build output.

```powershell
.\test\tool\measure_release_input_cache.ps1 `
    -ReleasePlanPath 'D:\ApprovedRelease\release-plan.json' `
    -ApprovedReleasePlanSha256 '<reviewed SHA-256>' `
    -PreviousFeedPath 'D:\ApprovedPreviousRelease\releases.win-x64-stable.json' `
    -PreviousPackagePath 'D:\ApprovedPreviousRelease\previous-full.nupkg'
```

Record cold/import and warm measurements separately. `downloadedBytes` counts
bytes written to download files (including partial retries), not HTTP overhead.
Do not equate local import timing with cold network-download timing.

## Adoption status and remaining work

See [validation evidence](release-tooling-validation-2026-09-17.md). Only the
implemented subset above is enabled. The larger playbook still contains work:
validated build/helper/stage reuse, complete publication orchestration, and
patch-churn analysis. Draft asset
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

### Metadata, promotion and lifecycle follow-up — 2026-09-18

The combined **nine** tooling suites passed on Windows PowerShell
5.1.26100.9444 and PowerShell 7.6.5. Each run covered 12 cache scenarios; 39
inventory, 80 preflight/metrics, 81 builder, 140 payload, 63 uploader, 101
promotion and 58 plan/lifecycle assertions; and 25 Python Git-history tests.
Both runs recorded `allTestsPassed=true`, `toolingInputsStable=true` and hashes
for 30 supporting files. Evidence:

- `build/release-tooling-tests/self-tests-1827fe8431d4476e9c2bfe8944a1ca1b`
- `build/release-tooling-tests/self-tests-c47414da48ed4d6ba27a96bbd5be6640`

The release owner also ran all six focused public-candidate foundation tests
successfully with Flutter `--no-pub`. The full current working-tree production
source privacy check passed, as did `git diff --check`. The runtime plan example
was parsed successfully on both shells. An existing synthetic private-path test
literal was changed to construct identical fixture bytes at runtime; all 140
payload assertions still pass and the privacy policy was not weakened.

The guarded promotion inventories dirty/untracked production content, rejects
file/overlay/plan changes during staging, preserves old outputs, and prunes only
explicit reviewed transient paths. Its cross-shell fixture fingerprints match.
No real Beta promotion was performed as part of this tooling validation.

The maintained lifecycle preflight/negative cases pass, including two synthetic
version transitions, identity mismatches, unsafe roots, changed helper evidence,
optimized-Python rejection and malformed archive paths. Actual install/update
execution of the newly parameterized harness remains to be verified on the next
authorized candidate. Public mode retains real installed/personal-data checks;
matching local evidence only avoids its duplicated local-only tail.

Git reuse is implemented and synthetic-tested, but remains conditional on a new
reviewed real-history cold baseline and the fixture-policy issue described
above. In the 100-blob fixture each shell reused 103 checks / 129,485 bytes on the
warm scan, with zero repeated content-policy checks. Fresh integrity/ref/path
checks still ran. These are synthetic measurements, not real-release speedup
claims. No public upload, app build, install, saved-data change or publication
occurred during this follow-up.
