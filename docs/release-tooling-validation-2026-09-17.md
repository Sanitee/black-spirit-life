# Tooling checks — September 17, 2026

Historical tests of publisher tools, based on `b0183054ea226acf99507460c5fab48d74b2ebfb`. No app release, build, installation or public upload was performed.

PowerShell 5.1.26100.9444 and 7.6.5 passed 12 cache cases, 39 inventory, 80 preflight/metrics and 81 builder assertions. Six Flutter candidate-foundation tests and the source verifier also passed. A subsequent plugin setup needed Windows symlink support; no system setting was changed or native build claimed.

Logs under `build/release-tooling-tests`:

- PS5: `self-tests-30b1a9a4c4504b799dab35f15e5c96da`
- PS7: `self-tests-08ea3e32f6a14119bfcfd2fdd56835c1`

Tests covered corrupt/wrong inputs, retries, locks, path traversal, hidden files, pruning, native failures, timestamps and real builder callbacks. Source preflight rejected the wrong tag before any download/build; that was a successful rejection, not a prepared release.

## Measured local results

Reviewed v0.1.9 input files, with zero downloaded bytes:

| Input | Size | First verified local import | Verified warm reuse |
| --- | ---: | ---: | ---: |
| Previous feed | 35,166 bytes | 84 ms | 9 ms |
| Previous full package | 724,092,083 bytes | 4,672 ms | 2,182 ms |

Warm reuse avoided downloading 724,127,249 bytes again while still checking hashes and copying outputs. These are local import times, not network timings.

PS7 source discovery:

| Operation | Before | After |
| --- | ---: | ---: |
| Four discovery scans vs one strict inventory | 7.97–8.05 seconds | 1.63–1.91 seconds |
| Complete production source verifier, one run each | 10.76 seconds | 6.49 seconds |

PS5 source discovery:

| Operation | Before | After |
| --- | ---: | ---: |
| Four discovery scans vs one strict inventory | 11.61–11.71 seconds | 0.41–0.58 seconds |
| Complete production source verifier, one run each | 25.22 seconds | 14.99 seconds |

Both kept the same 10,709 paths. The old PS5 scan suppressed 796 errors inside excluded generated trees; its strict failure was retained. The new scan pruned those trees. Earlier small-tree/first-use results were slower, so no universal speedup is claimed.

Measurement files: `input-cache-7caddd81bfb846ecb90ee2c49387166c/measurement.json`, `source-inventory-v3-representative-ps7.json`, `source-inventory-v4-representative-ps5.json` and `source-inventory-v3-representative-ps5-strict-failure.json`, under the same test directory.

This review covered input caching, retries, discovery and early checks. Build reuse, full lifecycle/publication and total release time were not verified by these tests. Later work is described in the [workflow guide](release-workflow-optimization.md).
