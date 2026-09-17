# Release-tooling validation — 2026-09-17

Scope: publisher-side scripts/fixtures/documentation on
`codex/release-tooling-optimization`, based on
`b0183054ea226acf99507460c5fab48d74b2ebfb`. No application, asset, installer,
updater, Beta, installed-state, personal-data or public-release change.

## Verification scope

Both Windows PowerShell 5.1.26100.9444 and PowerShell 7.6.5 execute the maintained
tooling test list through `tool/test_release_tooling.ps1`. Logs and the exact
test-file hashes are retained in each ignored unique test run. The tests cover:

- Verified cache imports/hits; zero-network offline reuse; repository/tag/
  channel/role/filename key separation; same-size corruption; wrong content
  despite a matching hash; truncated downloads; bounded transient retries;
  permanent failures; competing ownership; partial files; path traversal and
  junction rejection; preserving an existing wrong destination.
- Source traversal, hidden/untracked files, generated-tree pruning, stable
  ordinal paths, real privacy rejection, tracked generated output, missing
  required content, reparse/collision/access failures and cross-shell helper
  producer/consumer fingerprint agreement.
- Missing tools/dependencies/required files, malformed versions/scripts,
  CMake/.NET/Dart compatibility, explicit disk reserve, native command failure,
  stage outcomes and atomic timing-record saves.
- Actual builder package/feed callback code: wrong package identity, missing
  required helpers, wrong pinned feed relationship, and changed validation on
  warm cache hits. Actual verifier-call code proves child exit 23 prevents
  downstream execution. Extracted source-ordered preflight/acquisition code
  proves missing dependencies prevent input acquisition.

Final combined runs pass in both shells: 12 cache cases, 39 source-inventory
assertions, 80 preflight/metrics assertions and 81 builder-integration assertions.
Evidence folders below `build/release-tooling-tests`:

- PowerShell 5.1: `self-tests-30b1a9a4c4504b799dab35f15e5c96da`
- PowerShell 7: `self-tests-08ea3e32f6a14119bfcfd2fdd56835c1`

These executable fixtures do not simulate a successful full release or bypass
production provenance checks. The AST extracts are trusted local builder code,
executed against synthetic inputs solely for bounded integration testing.

The existing six `public_stable_candidate_foundation_test.dart` tests pass with
`flutter test --no-pub`. The actual production source verifier also passes on
the optimization checkout. Offline dependency resolution retained the pinned
lock; Flutter's subsequent fresh plugin setup reported missing Windows symlink
support. No Windows setting was changed. The focused tests run without a native
application build.

## Real historical-input measurement

The actual reviewed v0.1.9 feed and full package were read from existing retained
artifacts, without altering them. The actual builder validators and pinned
SHA-256/size values were used by `measure_release_input_cache.ps1`.

| Input | Size | First verified local import | Verified warm reuse |
| --- | ---: | ---: | ---: |
| Previous feed | 35,166 bytes | 84 ms | 9 ms |
| Previous full package | 724,092,083 bytes | 4,672 ms | 2,182 ms |

Both phases downloaded zero bytes. Warm reuse avoids a repeated **724,127,249
bytes** of historical downloads while retaining complete hash/content checks
and independent destination copies. The first phase is a **local cache import**,
not a measured cold network download. Network-time savings depend on the
connection; no total release-time percentage is claimed.

Local measurement evidence:
`build/release-tooling-tests/input-cache-7caddd81bfb846ecb90ee2c49387166c/measurement.json`.
The evidence binds the producing builder hash. The later source-exclusion fix
does not alter the measured cache code or feed/package validators.

## Early failure evidence

Invoking the real wrapper on the tooling-only checkout (valid installed tools,
offline pinned inputs) exits nonzero at the unchanged exact-source-tag gate.
No download or build starts. Its source-preflight stage measured about 321 ms
and recorded `Failed`, not a prepared/published success.

Evidence:
`build/public-stable-candidate/runs/20260917T145404222Z-21352-6313f29ab85e/stage-metrics.json`.

## Source-discovery measurements

Measurements compare four old source-discovery traversals with one strict
inventory, using identical normalized file lists and the same exclusion scope.
They do not remove content/SQLite checks or combine source and payload scans.
The representative retained build checkout is read-only; measurement output is
written only to the isolated tooling checkout.

Final PowerShell 7 representative results (three alternating-order samples):

| Operation | Before | After |
| --- | ---: | ---: |
| Four discovery scans vs one strict inventory | 7.97–8.05 seconds | 1.63–1.91 seconds |
| Complete production source verifier, one run each | 10.76 seconds | 6.49 seconds |

All 10,709 normalized file paths match exactly. Each old file traversal visited
170,950 files including generated output; the strict inventory visits 10,709
in-scope files and prunes 18 generated directories. Both complete verifiers
exit 0. Evidence: `build/release-tooling-tests/source-inventory-v3-representative-ps7.json`.

Final Windows PowerShell 5.1 representative results:

| Operation | Before | After |
| --- | ---: | ---: |
| Four discovery scans vs one strict inventory | 11.61–11.71 seconds | 0.41–0.58 seconds |
| Complete production source verifier, one run each | 25.22 seconds | 14.99 seconds |

The same 10,709 paths match the PowerShell 7 path-list SHA-256 exactly. The
historical four scans encounter 796 suppressed traversal errors, all classified
inside excluded generated trees. A strict old traversal fails there; its
failure evidence is retained rather than reported as a passing baseline. The
timings above reproduce the historical suppressed-error behavior with captured
diagnostics and reject any error outside the excluded scope. The new traversal
does not descend into those trees. Evidence:
`build/release-tooling-tests/source-inventory-v4-representative-ps5.json` and
`source-inventory-v3-representative-ps5-strict-failure.json` in the same directory.

Both final shell benchmarks bind source-inventory helper SHA-256
`E5E69CE0EDA4EF606F428F94C490B2D22DDAFFF395FEFC89AE480ECEC727CE4E`.

These are local filesystem-cache-warm measurements, not a cold boot or complete
release benchmark. Initial smaller-checkout PowerShell 7 discovery was slower
with strict per-file validation, and an earlier representative first-use sample
took 29.4 seconds. Those diagnostic samples are retained; no universal speedup
is claimed. The benefit is avoiding repeated descent through the substantial
generated trees present in a real build checkout. A native ordinal ordering
change removed the slow PowerShell comparison callback without removing checks.

A regression fixture also preserves the builder's narrower policy: ordinary
files named `build`, `bin`, `obj` or `ephemeral` remain inspectable, while their
generated-directory counterparts can be pruned. SQLite content in such a file
must not become invisible merely because its name resembles a generated folder.

## Playbook accounting

- **O01: partial.** Candidate build stages have progress/timing/outcome records;
  upload/lifecycle timing and crash-safe progressive receipts are not implemented.
- **O02: implemented for pinned historical feed/full inputs.** Includes local
  import, warm reuse, fresh hash/content validation and pinned feed relationship.
- **O03: implemented for those inputs.** Unique partials and bounded transient
  retries; no byte-range resume. Existing Velopack-tool download behavior remains.
- **O04: implemented.** Pruned strict discovery with policy/parity fixtures and
  measured representative traversal; not a promise every small tree gets faster.
- **O05: partial.** One inventory serves four builder boundary classifications;
  verifier shares the discovery code. No cross-phase inventory or new universal
  producer-fingerprint schema/cache is introduced.
- **O06: partial.** Early local/tool/version/source checks and a conservative
  staging-space floor. No publication authorization probe, full capacity model,
  centrally reviewed plan or complete artifact/lifecycle preflight is introduced.
- **O07: partial.** Release-tooling and builder-boundary tests are maintained.
  The broader installed lifecycle/process/health-response harness remains separate.
- **O08: preserved.** Existing lockfiles and pinned Velopack cache are unchanged;
  no dependency/tool upgrade is performed.
- **O09–O32: not claimed complete.** No central release plan/metadata migration,
  build/helper/output-cache reuse, safe stage resume, upload resume, release-wide
  lock, streaming privacy scan, patch-churn analysis or reusable installed
  lifecycle replacement is implemented by this patch. Relevant existing
  safeguards remain in place.

## Handoff and limits

Adoption is a Live Release review/merge decision; no push, tag or app version is
created here. See [operator and rollback instructions](release-tooling-optimization.md).
No full Windows compilation, packaging, installer/update lifecycle, cold network
download, interrupted-publication or public-delivery test was performed for this
tooling-only change. The next approved application release must pass all those
unchanged applicable acceptance gates using its final immutable artifacts.
