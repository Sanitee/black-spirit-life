# Workflow checks — September 18, 2026

Historical tooling tests based on `f08b2730c2073bfc191464a96fb1f676a6776b74`. These are not application-release acceptance.

All 16 suites passed on PowerShell 7.6.5 and Windows PowerShell 5.1.26100.9444, with 46 input files unchanged. Final logs under `build/release-tooling-tests`:

| Shell | Run | Manifest SHA-256 |
|---|---|---|
| PS7 | `self-tests-61de7a629a1245618a51e35d131691fd` | `D8D29A72B9DF321CE0E42C4E829CA09D9325D339BA1B6E33EBFC1BAB76213840` |
| PS5 | `self-tests-4690cfa6556c4a6eb335a2904440df10` | `2BAD0D9B3DD6DE3244B3BEBEED139F8B769EEE950B3635578B8E442C5D7E5B31` |

Final summed stage times were 89.99 and 76.18 seconds. These are tooling-test times, not release estimates. Earlier failures and passing runs remain in the audit; the source verifier and diff checks passed without weakening policy.

Tests covered caching, source inventory, preflight, builder, payload, uploader, promotion, lifecycle metadata, checkpoints, metrics, dependencies, streaming scans, workflow, Git privacy and installed-file comparison. Checkpoint tests reached 45 assertions and workflow tests 91.

## Additional checks

- Read-only comparison of the retained v0.1.11 installation found all 9,215 files identical to its package.
- Streaming scans used the same installer and preserved results while reducing time/memory; see the [measurements](release-workflow-optimization.md#scan-measurements--september-18-2026).
- Velopack extraction took 0.589 seconds; no extra cache was added.
- Review fixed overly broad exclusions, incomplete toolchain coverage, conflicting source locks and acceptance of damaged workflow evidence.

Compiler/packager fixtures used mocks. They proved the retry branches and rejection rules, not a real compiled-app retry. At this review, actual workflow/lifecycle use, UI checks, real-history baseline, retry cost and end-to-end timing still needed an authorized release. No real pub resolution, app build, installation or upload ran here.

Do not repeat unchanged tooling suites for every app-only update. Revalidate when their inputs, policy or runtime change.
