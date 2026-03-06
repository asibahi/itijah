# Benchmarks

Last updated: 2026-03-06.

`bench-compare` currently measures only the shared bidi operations:

- `analysis` — embedding level resolution
- `reorder_line` — visual reorder plus logical/visual maps

Scope of this page:

- synthetic LTR / RTL / MIXED corpora at `16`, `64`, `256`, `512`, `1024`
- huge LTR / RTL / MIXED corpora at `262144`, `524288`, `1048576`
- all four implementations when available locally: `itijah`, `zabadi`, `fribidi`, `icu`

Fastest time in each row is bolded.

## Environment

- OS: `Darwin 25.3.0 arm64`
- Zig: `0.15.2`
- FriBidi: `1.0.16`
- ICU runtime detected by harness: `ubidi major version 78`

## Command

```sh
ITIJAH_COMPARE_INCLUDE_HUGE=1 zig build bench-compare
```

## Synthetic

| Size | Kind | Op | itijah | zabadi | fribidi | icu |
|---:|---|---|---|---|---|---|
| 16 | LTR | `analysis` | **0.022 µs** | 0.326 µs | 0.335 µs | 0.206 µs |
| 16 | LTR | `reorder_line` | **0.034 µs** | 0.232 µs | 0.262 µs | 0.179 µs |
| 16 | RTL | `analysis` | **0.081 µs** | 0.668 µs | 0.237 µs | 0.169 µs |
| 16 | RTL | `reorder_line` | **0.104 µs** | 0.921 µs | 0.261 µs | 0.177 µs |
| 16 | MIXED | `analysis` | **0.353 µs** | 1.117 µs | 0.774 µs | 0.372 µs |
| 16 | MIXED | `reorder_line` | **0.408 µs** | 1.065 µs | 0.828 µs | 0.450 µs |
| 64 | LTR | `analysis` | **0.062 µs** | 0.397 µs | 0.425 µs | 0.368 µs |
| 64 | LTR | `reorder_line` | **0.105 µs** | 0.418 µs | 0.513 µs | 0.387 µs |
| 64 | RTL | `analysis` | **0.217 µs** | 1.885 µs | 0.419 µs | 0.371 µs |
| 64 | RTL | `reorder_line` | **0.308 µs** | 2.476 µs | 0.565 µs | 0.394 µs |
| 64 | MIXED | `analysis` | 1.226 µs | 2.229 µs | 2.818 µs | **1.176 µs** |
| 64 | MIXED | `reorder_line` | 1.431 µs | 2.837 µs | 3.073 µs | **1.399 µs** |
| 256 | LTR | `analysis` | **0.210 µs** | 1.272 µs | 1.101 µs | 1.177 µs |
| 256 | LTR | `reorder_line` | **0.391 µs** | 1.362 µs | 1.469 µs | 1.237 µs |
| 256 | RTL | `analysis` | **1.069 µs** | 6.805 µs | 1.070 µs | 1.151 µs |
| 256 | RTL | `reorder_line` | 1.407 µs | 8.824 µs | 1.693 µs | **1.263 µs** |
| 256 | MIXED | `analysis` | 4.951 µs | 8.156 µs | 11.02 µs | **4.563 µs** |
| 256 | MIXED | `reorder_line` | 6.477 µs | 10.43 µs | 13.07 µs | **5.898 µs** |
| 512 | LTR | `analysis` | **0.412 µs** | 2.391 µs | 1.988 µs | 2.218 µs |
| 512 | LTR | `reorder_line` | **0.755 µs** | 2.618 µs | 2.731 µs | 2.422 µs |
| 512 | RTL | `analysis` | 2.076 µs | 13.17 µs | **1.963 µs** | 2.235 µs |
| 512 | RTL | `reorder_line` | 2.728 µs | 17.16 µs | 3.188 µs | **2.433 µs** |
| 512 | MIXED | `analysis` | 9.812 µs | 16.43 µs | 22.24 µs | **9.736 µs** |
| 512 | MIXED | `reorder_line` | 16.25 µs | 24.08 µs | 29.64 µs | **14.51 µs** |
| 1024 | LTR | `analysis` | **0.770 µs** | 4.552 µs | 3.762 µs | 4.344 µs |
| 1024 | LTR | `reorder_line` | **1.431 µs** | 4.953 µs | 5.304 µs | 4.696 µs |
| 1024 | RTL | `analysis` | 4.085 µs | 26.23 µs | **3.798 µs** | 4.413 µs |
| 1024 | RTL | `reorder_line` | 5.625 µs | 33.69 µs | 6.130 µs | **4.755 µs** |
| 1024 | MIXED | `analysis` | 22.31 µs | 34.37 µs | 47.73 µs | **20.45 µs** |
| 1024 | MIXED | `reorder_line` | 40.54 µs | 51.75 µs | 68.73 µs | **33.92 µs** |

## Huge

| Size | Kind | Op | itijah | zabadi | fribidi | icu |
|---:|---|---|---|---|---|---|
| 262144 | LTR | `analysis` | **191.9 µs** | 1.15 ms | 907.8 µs | 1.08 ms |
| 262144 | LTR | `reorder_line` | **356.2 µs** | 1.22 ms | 1.29 ms | 1.15 ms |
| 262144 | RTL | `analysis` | 1.05 ms | 6.60 ms | **927.2 µs** | 1.09 ms |
| 262144 | RTL | `reorder_line` | 1.43 ms | 8.49 ms | 1.51 ms | **1.13 ms** |
| 262144 | MIXED | `analysis` | **8.00 ms** | 8.79 ms | 13.73 ms | 311.43 ms |
| 262144 | MIXED | `reorder_line` | 25.66 ms | **22.84 ms** | 41.16 ms | 334.56 ms |
| 524288 | LTR | `analysis` | **393.3 µs** | 2.24 ms | 1.88 ms | 2.20 ms |
| 524288 | LTR | `reorder_line` | **735.6 µs** | 2.47 ms | 2.66 ms | 2.30 ms |
| 524288 | RTL | `analysis` | 2.06 ms | 13.23 ms | **1.86 ms** | 2.18 ms |
| 524288 | RTL | `reorder_line` | 2.89 ms | 16.98 ms | 3.07 ms | **2.37 ms** |
| 524288 | MIXED | `analysis` | **15.81 ms** | 17.40 ms | 27.76 ms | 1405.38 ms |
| 524288 | MIXED | `reorder_line` | 51.22 ms | **45.71 ms** | 81.13 ms | 1445.50 ms |
| 1048576 | LTR | `analysis` | **779.5 µs** | 4.63 ms | 3.75 ms | 4.39 ms |
| 1048576 | LTR | `reorder_line` | **1.48 ms** | 4.86 ms | 5.45 ms | 4.72 ms |
| 1048576 | RTL | `analysis` | 4.04 ms | 26.55 ms | **3.74 ms** | 4.40 ms |
| 1048576 | RTL | `reorder_line` | 5.78 ms | 34.63 ms | 6.28 ms | **4.79 ms** |
| 1048576 | MIXED | `analysis` | **31.48 ms** | 35.18 ms | 57.81 ms | 5771.60 ms |
| 1048576 | MIXED | `reorder_line` | 103.86 ms | **93.86 ms** | 166.08 ms | 5883.18 ms |

## Notes

- `bench-compare` includes a FriBidi parity precheck before printing benchmark rows. On this run it reported `11/12 PASS`; the tables above contain only benchmark measurements.
- `zabadi` rows require `../zabadi` to be present at benchmark time.
