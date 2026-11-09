# Release workflow

This is publisher tooling. It does not authorize publication or changes to saves. Follow the standing release contract and keep the complete helper set.

## Inputs and status

Prepare each package with `tool/release/prepare_dependencies.ps1`, using `PackageRoot`, the approved `FlutterPath` and a new external `ReceiptPath`. Consumers recheck the receipt and use `--no-pub`. A receipt proves matching dependencies, not a successful build or test.

Native checks cover both selected .NET SDKs, Visual C++/Windows SDK/C++ WinRT and installer artwork. Producer changes invalidate those checks. Stage records save atomically; an exclusive source lock prevents competing builds. No old process is killed or evidence deleted automatically.

Use `run_release_workflow.ps1` with [the example schema](release-workflow.v1.example.json). Replace dummy values with reviewed source, promotion evidence, tools, plans, receipts and complete test lists. “Reviewed” means evidence checked within an authorized release, not another user permission request at every step. Ask only if scope, authority or product behaviour changes.

Run the builder inside the actual promoted source; changing only its working directory is not enough.

```powershell
$workflow = @{
    ManifestPath = 'D:\ApprovedRelease\workflow-prepare.json'
    ApprovedManifestSha256 = '<reviewed workflow SHA-256>'
}
.\tool\release\run_release_workflow.ps1 @workflow -Mode Preflight
.\tool\release\run_release_workflow.ps1 @workflow -Mode Initialize
.\tool\release\run_release_workflow.ps1 @workflow -Mode RunNext
.\tool\release\run_release_workflow.ps1 @workflow -Mode Status
```

`RunNext` runs the first unfinished gate and saves its command, process, logs and proof. Before advancing it rechecks earlier evidence and the source/context. A narrow test pass cannot replace a failed full suite. Interrupted work requires safe recovery after its process stops; it is never assumed successful.

## Build versus release acceptance

The initial `prepare-build` manifest covers promotion, privacy, complete application tests and build. Once artifacts are sealed, use `ContinueManifest` with a reviewed `acceptance` manifest and both old/new hashes. Preserve the original gates and context; add artifact, package, installed lifecycle, UI, upload, publication and public-route checks. Do not rebuild just to make this transition.

Reports need actual proof, not exit code alone: complete Flutter suite results, unchanged artifact hashes, matching lifecycle inputs and installed files. Unreviewed failures/skips block acceptance. External UI and publication evidence must be explicitly reviewed. Status distinguishes built, locally checked, uploaded, published and publicly checked.

Keep evidence outside frozen source. Changed inputs or evidence block reuse. Never edit a hash to make an old pass look current. This workflow is an acceptance record, not protection against deliberately forged evidence.

## Optional packaging retry

Clean builds remain the default. A packaging failure may reuse its verified bundle only if a complete input profile was supplied **before** the first build.

Schema 1 requires `purpose: "same-candidate-build-retry"`, `approvalReference`, `completeExternalInputsReviewed: true`, `inputTrees` and `inputFiles`. Each tree has an absolute path and role. Cover all selected `flutter-sdk`, `native-toolchain`, `windows-sdk`, `dotnet-sdk` and `package-cache` roots, plus producer-specific inputs. No exclusions, broad personal/drive roots, overlapping roots or reparse paths.

Pass `BuildRetryProfilePath` and its approved hash. The builder fingerprints source including untracked assets, prepared config, full tools/packages, flags, plan, OS/shell and a hash of the environment. It stores no raw environment values. After build and payload checks, it verifies stability and retains an independent bundle copy.

A retry also needs `ResumeBundleReceiptPath` and its approved hash. Recheck all inputs and outputs, then copy into new staging. Only compilation is skipped; payload, packaging, installer, installed and public checks remain. Invalid inputs stop reuse. Old bundles and failed staging remain intact.

This is opt-in: measure the full-toolchain hashing cost and a real failure/retry before routine use. Development tests used synthetic compiler/package fixtures, not an actual app compile retry.

## Scan measurements — September 18, 2026

The same 729,668,096-byte installer was checked in fresh serial processes, with hashes before/after:

| Shell | Previous scan | Streaming scan | Peak working set, previous → streaming |
| --- | ---: | ---: | ---: |
| PowerShell 7.6.5 | 79.334 s | 6.308 s | 12.24 GB → 207 MB |
| Windows PowerShell 5.1 | 81.458 s | 24.565 s | 2.97 GB → 162 MB |


The scanner passed 1,332 equivalence assertions per shell. These are single local, filesystem-warm scans, not promised release times. An initially slower PS5 implementation was retained as evidence, corrected and remeasured.

Velopack extraction took 0.589 seconds, so a second extraction cache was not added. Keep separate download/hash/extraction timings. These tools do not require an app release merely to adopt them.
