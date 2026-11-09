# Release tools

These tools prepare and check a release; they do not authorize publication. Follow the standing release contract: ship the complete approved Beta, preserve its behaviour and users' saves, and exclude private data. See also the [workflow guide](release-workflow-optimization.md).

## What is reused

Previous feeds/packages are cached by repository, tag, channel, role, filename, size and SHA-256. Every use checks the complete hash and actual identity, then copies the verified input. The feed must name the pinned package.

Transient downloads get three attempts by default, each with its own partial file. Integrity failures stop. Partial or corrupt files stay as evidence and are never consumed. Exclusive locks prevent competing work; a leftover lock filename is not ownership. There is no byte-range resume or automatic cleanup.

Source discovery skips only reviewed generated directories before entering them. It still sees hidden/untracked production files and rejects unreadable paths, links and case collisions. A shared inventory avoids repeated traversal; source, package and installed checks stay separate.

Preflight checks tools, dependencies, scripts, source, privacy and release identity before large downloads. Nonzero verifier exits stop the build. Stage records save atomically at start/end. Missing measurements are null; interrupted stages are not passes. Timing files do not authorize resuming a stage.

## Prepare a release

1. Confirm the current approved Beta and release owner. Do not add unrelated changes.
2. Keep the complete maintained tooling and fixtures.
3. Review a release-plan JSON and pin its SHA-256. Use [the schema example](release-plan.v1.example.json), replacing all dummy identities with reviewed values. Keep the plan outside frozen source.
4. Run `tool/release/prepare_dependencies.ps1` for each required package. It uses `pub get --enforce-lockfile`; changed lockfiles or pubspecs stop preparation. Pass the exact root and Gathering receipts to their consumers. Tests/builds use `--no-pub`.
5. Run tooling tests when tooling, policy, fixtures or runtime changed, or matching baseline evidence is missing. Do not repeat unchanged synthetic suites for every app-only update. Each release still needs its own input checks and application/release verification.

```powershell
# Run from the selected repository root, once in each supported shell.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tool\test_release_tooling.ps1
pwsh.exe -NoProfile -NonInteractive -File .\tool\test_release_tooling.ps1
```

Execution-policy bypass is process-local. Tests retain child exits, logs, input hashes and stability checks. They are not installation tests. Git-history tests need Git and Python 3.9+; use `-PythonPath` or process-local `BSL_RELEASE_PYTHON` if needed.

Prepare a candidate:

```powershell
.\tool\build_public_stable_candidate.ps1 `
    -ReleasePlanPath 'D:\ApprovedRelease\release-plan.json' `
    -ApprovedReleasePlanSha256 '<reviewed SHA-256>' `
    -DependencyReceiptPath 'D:\ApprovedRelease\root-dependencies.json' `
    -ApprovedDependencyReceiptSha256 '<reviewed dependency receipt SHA-256>' `
    -ConfirmPublicCandidateOnly `
    -FlutterPath 'D:\Tools\flutter\bin\flutter.bat'
```

Paths above are placeholders. The builder runs from its actual candidate source. It prepares files only; it never uploads or publishes.

The plan separates target release, previous published version and legacy migration fixture. Do not make those versions identical just to pass a test. `remainingBlockers` lists unfinished checks; it is not proof they passed. Source inventories and reviewed adaptations remain separate evidence.

### Optional inputs

| Parameter | Meaning |
| --- | --- |
| `ReleaseInputCacheRoot` | Absolute ordinary directory; default is this checkout's `build/release-input-cache`. A shared **tool-owned** root preserves reuse between isolated release checkouts. Never choose Beta content, personal-data or protected evidence folders. |
| `PreviousFeedPath` | Read-only existing pinned historical feed to import on a cache miss. |
| `PreviousPackagePath` | Read-only existing pinned historical full package to import on a miss. |
| `OfflinePinnedInputs` | Reject a historical-input cache miss unless a valid local import is provided. This does **not** make Flutter, Velopack-tool acquisition or publication fully offline. |
| `MinimumFreeBytes` | Optional larger reserve for the project volume. Effective minimum is at least three previous-package sizes plus three previous-feed sizes. This conservative staging floor is **not** a guarantee of enough space for a full build; check other output/cache volumes too. |


Every import still needs matching size, hash and content identity. Historical cache reuse does not replace a fresh public-feed check.

## Copy approved source

`promote_source.ps1` inventories the real working tree, including dirty/untracked production files. A schema-1 plan needs `approvalReference` and explicit `pruneDirectories`, `omitFiles`, `replaceFiles` and `addFiles`, each with a path and reason.

- Pruning applies to exact reviewed directories, never an implicit whole-module exclusion.
- Omissions require the original `expectedSha256`.
- Replacements require original and overlay hashes plus `overlayPath`.
- Additions require overlay path/hash and an absent destination.

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

The overlay is read-only; use an empty ordinary folder if unused. Inventory writes nothing. Promote needs a new non-overlapping destination and exposes it only after hash and input-stability checks. Failed staging, previous builds, source and saves remain intact. A promotion report is not release acceptance.

## Install and update checks

`run_lifecycle_rehearsal.ps1` uses maintained synthetic fixtures, not old copied scripts. Supply the exact plan, candidate, previous setup, source, tools and dependency receipts. Evidence and disposable roots must be new and separate from source, builds and personal saves. The disposable leaf starts with `bsl-lifecycle-`.

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
    GatheringDependencyReceiptPath = 'D:\ApprovedRelease\gathering-dependencies.json'
    ApprovedGatheringDependencyReceiptSha256 = '<reviewed Gathering receipt SHA-256>'
    EdgePath = '<resolved Edge executable>'
}
.\tool\release\run_lifecycle_rehearsal.ps1 @lifecycleInputs -Mode LocalFeed -PreflightOnly
```

Preflight installs nothing and changes no registration. A real rehearsal requires PowerShell 7 and `-ConfirmDisposableLifecycle` in an isolated synthetic setup. It temporarily backs up/restores app registration and shortcuts. PowerShell 5.1 supports preflight and tooling tests only.

PublicRoute needs new roots and matching `LocalFeedReceiptPath`/`ApprovedLocalFeedReceiptSha256`. It still tests actual public downloads, installed files and save preservation. Matching local evidence avoids only duplicate local fresh/repair/stress checks. Changed helpers, runtime or candidate invalidate reuse.

This tests the manifest's `velopack-setup`; themed-installer downloads and UI checks remain separate. Preflight is never an installed-test pass.

## Upload verified files

`publish_verified_release.ps1` uploads the four manifest entries to an **existing draft**. It cannot build, create, publish, delete or overwrite conflicting files. Review all non-upload evidence first; the generated manifest alone is not acceptance.

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

Provide credentials through `GITHUB_TOKEN`, never command text or logs. Retry the same immutable candidate after checking remote state. Matching remote digests allow reuse; missing digests, identity changes, unexpected assets or byte conflicts stop. Do not rebuild or overwrite to bypass them.

Defaults: three attempts, two-second retry delay, 60-second JSON timeout and 300-second upload timeout. Authentication or invalid requests stop immediately. Sanitized records go to `draft-upload-receipts.jsonl` or `ReceiptPath`; resumed work still rechecks remote hashes. Upload completion is not publication completion.

## Git-history checks

Use `verify_git_object_privacy.py` with a reviewed cold baseline. Old schema-1 reports cannot authorize reuse.

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

The expected refs file is an exact reviewed name-to-object map. Review local and final remote maps separately. Every run checks HEAD/tag, object integrity and historical paths.

Warm reuse needs `--prior-receipt` plus its approved hash and matching scanner, policy, markers and runtime. New blobs are scanned; an old blob at a forbidden path still fails. `git fsck` and path checks always run.

Policy is read as data from the trusted verifier, never executed from the scanned clone. Text/commit/tag checks cover the maintained secret/path rules; binaries receive the SQLite-header check, not a universal secret scan. Unsupported encodings or oversized text stop. Precisely approved historical exceptions must be recorded; never silently waive findings or rewrite history.

## Measure and recover

Optional local-input measurement:

```powershell
.\test\tool\measure_release_input_cache.ps1 `
    -ReleasePlanPath 'D:\ApprovedRelease\release-plan.json' `
    -ApprovedReleasePlanSha256 '<reviewed SHA-256>' `
    -PreviousFeedPath 'D:\ApprovedPreviousRelease\releases.win-x64-stable.json' `
    -PreviousPackagePath 'D:\ApprovedPreviousRelease\previous-full.nupkg'
```

Record import and warm-cache times separately. Local copying is not a cold network benchmark. Downloaded bytes include partial retries, not HTTP overhead.

On a rejected cache entry, investigate or use a new tool-owned cache; never weaken hashes. Recheck inventories after inputs change. Keep previous tooling for rollback and do not reset the working Beta or overwrite accepted evidence.

See [September 17 validation](release-tooling-validation-2026-09-17.md) and [September 18 validation](release-workflow-validation-2026-09-18.md). Those are dated tooling results, not acceptance of a later application release.
