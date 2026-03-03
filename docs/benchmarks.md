# Benchmarks

Last updated: 2026-03-03.

## Scope

`bench-compare` reports performance and memory KPIs for:

- `itijah`
- `fribidi`
- ICU `ubidi`

for these operations:

- `analysis`
- `reorder_line`

and these corpora sizes:

- `16`, `64`, `256`, `1024`, `2048`, `4096`, `10000`, `20000`

## Environment

- OS: `Darwin 25.2.0 arm64`
- Zig: `0.15.2`
- FriBidi: `1.0.16`
- ICU runtime detected by harness: `ubidi major version 78`

## Commands

```sh
zig build bench
zig build bench-compare
ITIJAH_COMPARE_ONLY_PARITY=1 zig build bench-compare
ITIJAH_COMPARE_ITIJAH_REUSE=1 zig build bench-compare
```

## Selected Results

Source: `zig build bench-compare` on 2026-03-03 (after probe-finish ordering fix in `bench/compare.zig`).

| Case | Op | Impl | mean_ns | ns_per_cp | alloc_count | allocated_bytes | peak_bytes |
|---|---|---:|---:|---:|---:|---:|---:|
| LTR-1024 | analysis | itijah | 812.82 | 0.79 | 2.00 | 2048.00 | 2048.00 |
| LTR-1024 | analysis | fribidi | 3701.16 | 3.61 | 0.00 | 0.00 | 0.00 |
| LTR-1024 | analysis | icu | 4244.73 | 4.15 | 0.00 | 0.00 | 0.00 |
| LTR-1024 | reorder_line | itijah | 1651.01 | 1.61 | 3.00 | 6144.00 | 5120.00 |
| LTR-1024 | reorder_line | fribidi | 5268.20 | 5.14 | 0.00 | 0.00 | 0.00 |
| LTR-1024 | reorder_line | icu | 4564.91 | 4.46 | 0.00 | 0.00 | 0.00 |
| MIXED-1024 | analysis | itijah | 23841.83 | 23.28 | 56.00 | 45652.00 | 38476.00 |
| MIXED-1024 | analysis | fribidi | 47688.56 | 46.57 | 0.00 | 0.00 | 0.00 |
| MIXED-1024 | analysis | icu | 20627.14 | 20.14 | 0.00 | 0.00 | 0.00 |
| MIXED-1024 | reorder_line | itijah | 41598.30 | 40.62 | 57.00 | 49748.00 | 38476.00 |
| MIXED-1024 | reorder_line | fribidi | 68754.37 | 67.14 | 0.00 | 0.00 | 0.00 |
| MIXED-1024 | reorder_line | icu | 33849.80 | 33.06 | 0.00 | 0.00 | 0.00 |
| MIXED-4096 | reorder_line | itijah | 333233.76 | 81.36 | 183.00 | 229328.00 | 175328.00 |
| MIXED-4096 | reorder_line | fribidi | 517775.86 | 126.41 | 0.00 | 0.00 | 0.00 |
| MIXED-4096 | reorder_line | icu | 266238.24 | 65.00 | 0.00 | 0.00 | 0.00 |
| MIXED-20000 | reorder_line | itijah | 2023886.13 | 101.19 | 287.00 | 1047636.00 | 813172.00 |
| MIXED-20000 | reorder_line | fribidi | 3224552.38 | 161.23 | 0.00 | 0.00 | 0.00 |
| MIXED-20000 | reorder_line | icu | 2884537.17 | 144.23 | 0.00 | 0.00 | 0.00 |

## Notes and Disclaimer

- Microbenchmark numbers vary across CPU, compiler, and system load.
- Keep comparisons apples-to-apples by using the same machine and command set.
- `analysis` and `reorder_line` are different workloads. `reorder_line` includes visual output plus map construction.
- If your integration only needs visual output, benchmark `reorderVisualOnlyScratch` usage separately for realistic renderer behavior.
- Memory probe counters are captured after each measured call returns (no deferred-return ordering bug).
- Current runs still show `0.00` memory counters for `fribidi` and ICU on this host because the measured steady-state path does not perform allocator-visible allocations after warmup.
