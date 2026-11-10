# Kimi 3.1 CompCert 3.17 O2 results

## Implementation

- Model/provider: `kimi-3.1`, Moonshot AI.
- Frozen baseline: `7b1f02b09954b9b916eb2a91d283c9b5355bf172`.
- Accepted implementation: `b530f8da472216fa0246b1c90fc40a3a8dfdec06`.
- Results branch: `results/kimi-3.1-20261108T1707Z`.
- Original campaign: 2026-11-08T17:07:16Z through 2026-11-09T17:07:16Z.
- Crash-gap compensation: 2026-11-10T02:01:58Z through 2026-11-10T09:20:43Z.

The accepted changes extend the existing proved RTL inlining heuristic. Static,
non-address-taken functions with 2–8 direct calls and at most 32 RTL nodes are
eligible for inlining. The final revision additionally tracks direct outgoing
calls and permits leaf functions with at most 16 RTL nodes and 12 direct callers.
Existing called-once and explicit inline/noinline behavior is preserved.

Accepted implementation commits are preserved without squashing:

1. `180e1bdd6c643933544544be6dd99ed601ed64c3` — repeated small-function inlining.
2. `f5ba99863da1201eff3830f00e0b895dade549e7` — 32-node threshold.
3. `b530f8da472216fa0246b1c90fc40a3a8dfdec06` — bounded leaf-function extension.

## Final verification

The crash-gap compensation ended with a fresh verification of the unchanged
accepted implementation:

- All 139 small tests passed in each of three samples.
- All six required SPEC programs passed in each of three samples.
- Every whole-program and individual translation-unit three-sample compilation
  median satisfied its fixed limit.
- Guarded `make check-proof check-admitted` and assumption reporting passed.
- `Nothing admitted.` was reported; proof and assumption output was identical to
  the accepted verification. No axioms or admitted proofs were added.
- All runtime samples and output comparisons passed.
- A five-round same-source control gave geometric-mean ratio 1.000452.

## Fresh direct frozen-baseline runtime

Serial interleaved measurements on CPU 2, five measured rounds plus warmups.
The metric is user+system CPU time from `wait4`. Speedup is baseline time divided
by candidate time; greater than 1 is better.

| Workload | Frozen baseline median (s) | Candidate median (s) | Speedup |
| --- | ---: | ---: | ---: |
| 708.sqlite_r | 0.154258 | 0.143535 | 1.07471 |
| 777.zstd_r | 0.203317 | 0.175461 | 1.15876 |
| 782.lbm_r | 40.405681 | 40.469772 | 0.99842 |
| 811.tealeaf_s | 5.396087 | 5.370731 | 1.00472 |
| 816.nab_s | 0.812815 | 0.811079 | 1.00214 |
| 881.neutron_s | 72.973805 | 72.996991 | 0.99968 |
| **Geometric mean** | | | **1.038098** |

The original campaign's independent five-round direct measurement gave 1.036589
geometric-mean speedup. Both measurements are retained; the fresh compensation
measurement does not replace the historical result.

## Fresh compilation medians

| Program | Candidate median (s) | Fixed limit (s) |
| --- | ---: | ---: |
| 708.sqlite_r | 28.3208 | 44.5224 |
| 777.zstd_r | 16.5865 | 42.7257 |
| 782.lbm_r | 1.02649 | 2.81442 |
| 811.tealeaf_s | 1.58488 | 5.08743 |
| 816.nab_s | 3.67111 | 10.5894 |
| 881.neutron_s | 0.775711 | 2.70275 |

The complete 139-case and per-translation-unit reports are retained in the run
evidence directory described below.

## Compensation experiments

No compensation candidate qualified for acceptance. Rejected direct incremental
geomeans included George threshold 4 (0.999002 final), general biased coloring
(1.000329), float-only biased coloring (1.000898), shorter 64-bit zero encodings
(0.998198), tighter if-conversion (0.999433), 16-caller leaf inlining (0.997686),
a weak-positive combination (0.996891), and 20-node leaf inlining (0.999500).
All rejected source changes were reverted; their patches and measurements remain
in the retained evidence.

## Evidence

The complete local audit evidence is retained at:

`/home/fanl/compcert-3.17-experiments/run-kimi-3.1-20261108T1707Z`

Principal reports are `REPORT.md`, `FINAL_RESULT.json`,
`COMPENSATION_REPORT.md`, `COMPENSATION_RESULT.json`, `CANDIDATES.md`, and the
`comp-final-b530-*` and `runtime-final-comp-b530-*` artifacts. Raw measurements,
compilation reports, proof guards, rejected patches, and provenance are preserved.
