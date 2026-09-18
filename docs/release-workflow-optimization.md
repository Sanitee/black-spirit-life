# Workflow, prepared inputs and measured scans

Publisher tooling only. The approved Beta remains the application; nothing in
this document authorizes publication or a change to user data. Read the standing
release contract and playbook before use. Keep the full maintained helper set.

## Default improvements

- Prepare dependencies once per required package using
  `tool/release/prepare_dependencies.ps1 -PackageRoot <candidate package>
  -FlutterPath <approved flutter.bat> -ReceiptPath <new external receipt>`.
  This runs lock-enforced resolution. The builder and lifecycle revalidate the
  exact receipt and use `--no-pub`; a stale receipt stops early. This is not a
  complete compilation-cache key or proof that tests passed.
- Native prerequisite checks mirror the current helper producers: both selected
  .NET SDKs, Visual C++/Windows SDK/C++ WinRT and installer artwork. Producer
  changes invalidate the mirrored contract instead of silently using old rules.
- Stage metrics persist atomically at stage start and completion. An exclusive
  candidate lock prevents competing builds; no stale PID is killed and no old
  evidence is deleted.
- Streaming privacy scans preserve the previous marker and encoding rules,
  including chunk boundaries and narrow reviewed exceptions. Checks still run
  at their distinct bundle/installer boundaries.
- Lifecycle performs exhaustive immutable installed-payload comparison before
  its disposable installation is removed. Upgrade, fresh install and repair
  remain distinct local cases; public-route verification still checks the actual
  public update. Hash-bound nested reports preserve this evidence afterward.

## One maintained release status and gate list

Use `tool/release/run_release_workflow.ps1`, starting from
`docs/release-workflow.v1.example.json`. The example is deliberately not a
release approval. Resolve the actual current source, source-promotion evidence,
plan, tools, dependency receipts and complete application test roots/lists.
Here "review/approve/pin" means the release owner's evidence checks within an
already authorized release, not asking the user for permission at every step.
Ask the user only when scope, authority or a material product difference changes.
Pin every runtime/helper needed later in the initial context, not just the
build tools. Include each package's required tests as its own complete gate.

The candidate builder derives its source root from its script location. Invoke
the maintained builder copied into the actual promoted source, not a builder
in a different tools checkout with only its working directory changed.

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

`RunNext` runs only the first unmet reviewed gate. It saves a unique attempt,
literal command, process identity, logs and validated evidence. A failed full
test gate cannot be replaced by a later narrow success. Completed evidence and
the complete source/context are rechecked before advancing. An interrupted
command requires explicit safe recovery after its recorded process has stopped;
it is never presumed successful or automatically killed.

The initial `prepare-build` manifest covers promotion, source privacy, complete
application tests and build. It cannot claim release completion. After the
builder seals actual artifacts, approve an `acceptance` manifest with those
hashes, preserving the exact original gates and context. Use `ContinueManifest`
with the new manifest/hash plus `PriorManifestPath` and
`ApprovedPriorManifestSha256`. Append the distinct artifact privacy, package
integrity, lifecycle, installed parity, UI, themed installer, upload,
publication and public-verification obligations. This is the one artifact
sealing boundary, not another investigation or full rebuild.

Automatic gates validate actual reports, not exit code alone. Flutter machine
results must match the complete resolved suite list, with no unreviewed failed
or skipped tests. Builder reports rehash the sealed original manifest and each
artifact. Lifecycle reports bind candidate, plan, harness and nested installed
parity. UI/themed-installer and publication use explicitly reviewed evidence;
the workflow never publishes automatically. Status distinguishes built, locally
verified, uploaded, published and publicly verified.

Keep status/evidence outside the frozen source. A changed source, context,
manifest or successful evidence file blocks reuse. Never edit hashes merely to
make a stale pass look current. The workflow is a local acceptance index, not a
security boundary against an operator deliberately fabricating evidence.

## Optional same-candidate packaging retry

The ordinary route still builds cleanly. No general incremental compilation or
native-helper cache is enabled. A packaging-only failure can optionally reuse a
verified retained bundle **only** when a complete reviewed input profile was
supplied before the first build.

Profile schema 1 requires `purpose: "same-candidate-build-retry"`, a nonempty
`approvalReference`, `completeExternalInputsReviewed: true`, `inputTrees` and
`inputFiles` arrays. Every tree has an absolute `path` and `role`. Required roles
are `flutter-sdk`, `native-toolchain`, `windows-sdk`, `dotnet-sdk` and
`package-cache`; include all applicable roots, not a token empty directory.
Selected complete SDK/tool roots and all external package roots must be covered.
Trees have no exclusion option. Broad personal/drive roots, overlap and reparse
paths fail. The owner must review any additional producer-specific inputs.

Supply `BuildRetryProfilePath` and `ApprovedBuildRetryProfileSha256` to the
builder. It fingerprints production source (including new/untracked assets),
prepared configuration, whole external input trees, tools, flags, release plan,
OS/shell and a hash of the process environment. It verifies stability after
compilation and payload checks, retaining a separately copied, verified bundle
before packaging. Raw environment values are not written to its receipt.

For an unchanged retry, also supply `ResumeBundleReceiptPath` and
`ApprovedResumeBundleReceiptSha256`. The exact inputs and every retained output
are revalidated and copied into new staging; compilation alone is skipped.
Payload, packaging, installer, installed-state and public checks are not waived.
Changed/incomplete keys or tampered output stop before reuse. Retained bundle
and failed staging are not deleted or overwritten.

This is opt-in because hashing entire external toolchains has a cost. Measure
its first real failure/retry against a clean build before enabling it routinely.
No real application compile/retry was performed during tooling development;
synthetic fixtures test the actual builder branches and rejection paths.

## Measured choices

On the same retained 729,668,096-byte published installer, serial fresh-process
tests with before/after SHA-256 checks measured:

| Shell | Previous scan | Streaming scan | Peak working set, previous → streaming |
| --- | ---: | ---: | ---: |
| PowerShell 7.6.5 | 79.334 s | 6.308 s | 12.24 GB → 207 MB |
| Windows PowerShell 5.1 | 81.458 s | 24.565 s | 2.97 GB → 162 MB |

The final scanner passes 1,332 independent reference-equivalence assertions per
shell. These are single measured local scan runs, not a promised total release
duration. A first PS5 streaming version regressed to 98.383 s; it was corrected
and remeasured before adoption. The final candidate uses the unchanged regex
on bounded candidate spans, preserving its culture-sensitive verdicts.

Pinned Velopack extraction alone took 0.589 s into a new directory (446 files,
347,155,526 output bytes, warm source). A second extraction cache was therefore
not added. The previous 110 s tool stage included other work; new download,
hash and extraction timings identify where any remaining delay actually lies.

Retain earlier verified tooling for rollback. These optimizations do not require
an app release merely to adopt them. Final real candidate lifecycle/workflow and
end-to-end turnaround evidence belong to the next authorized release.
