# itijah (اتجاه)

Zig-native implementation of the Unicode Bidirectional Algorithm ([UAX #9](https://unicode.org/reports/tr9/)).

Codepoint-based API inspired by FriBidi's design, implemented idiomatically in Zig with no global state and explicit allocator passing.

## Status: Phase 1

### Implemented (Phase 1)

| Rule | Description | Status |
|------|------------|--------|
| P2-P3 | Paragraph direction detection | Done |
| X1-X8 | Explicit embeddings, overrides, isolates | Done |
| X9 | Remove explicit codes (marked BN) | Done |
| W1-W7 | Weak type resolution | Done |
| N0 | Bracket pair resolution | Done (per-IRS pairing per UAX #9 BD16) |
| N1-N2 | Neutral type resolution | Done |
| I1-I2 | Implicit level resolution | Done |
| L1 | Reset segment/paragraph separators | Done (parts 1-3) |
| L2 | Reorder by level | Done |

### Not Yet Implemented (Phase 2)

| Rule | Description |
|------|------------|
| L3 | Combining mark (NSM) reordering |
| L4 | Mirroring (data table ready, application pending) |
| Arabic joining | Rules R1-R7 (stub returns `error.NotImplemented`) |
| Arabic shaping | Presentation forms (stub returns `error.NotImplemented`) |

## Current Validation Snapshot

- `zig build` passes
- `zig build test` passes (filtered mode by default)
- Full conformance passes:
  - `BidiTest (full) failed=0`
  - `BidiCharacterTest (full) failed=0`
- FriBidi parity guardrail in `bench-compare`:
  - `ITIJAH_COMPARE_ONLY_PARITY=1 zig build bench-compare`
  - current summary after strict per-IRS N0: `11/12 PASS`
  - known delta: `MIXED-1024` levels at `idx=434` (`expected=15 actual=16`)
- `bench-compare` parity and `test-diff` totals are not directly comparable:
  - `bench-compare` parity checks a fixed 12-case corpus
  - `test-diff` runs curated + generated corpora and reports pass/fail/warn counts

## Reports

- Benchmarks and KPI tables: [docs/benchmarks.md](docs/benchmarks.md)
- Compatibility and mismatch status: [docs/compatibility.md](docs/compatibility.md)

## N0 Overflow Behavior Note

`itijah` follows UAX #9 BD16 with per-IRS bracket pairing and overflow semantics.

- Bracket pairing is collected independently per Isolating Run Sequence (IRS), so pairs cannot bleed across disjoint IRS segments at the same isolate depth.
- On BD16 stack overflow, only the current IRS pairing is discarded, matching UAX #9 intent.
- This behavior is validated by dedicated regression tests and full Unicode conformance.

FriBidi parity can differ on rare synthetic isolate/bracket mixes because this implementation now prioritizes strict UAX #9 IRS-local pairing semantics.

This is covered by dedicated regression tests plus full Unicode conformance runs.

## API

```zig
const itijah = @import("itijah");

// Get embedding levels
var dir: itijah.ParDirection = .auto_ltr;
var emb = try itijah.getParEmbeddingLevels(allocator, codepoints, &dir);
defer emb.deinit();

// Reorder to visual order
var vis = try itijah.reorderLine(allocator, codepoints, emb.levels, dir.toLevel());
defer vis.deinit();

// Logical-to-visual index map
const l2v = try itijah.logToVis(allocator, emb.levels, dir.toLevel());
defer allocator.free(l2v);

// Visual runs in visual order (contiguous logical slices + direction)
const runs = try itijah.getVisualRuns(allocator, emb.levels, dir.toLevel());
defer allocator.free(runs);

// Remove bidi control marks
const cleaned = try itijah.removeBidiMarks(allocator, codepoints, null);
defer allocator.free(cleaned.result);
```

Scratch/reuse APIs are available for high-throughput render loops:

```zig
var emb_scratch = itijah.EmbeddingScratch{};
defer emb_scratch.deinit(allocator);
var re_scratch = itijah.ReorderScratch{};
defer re_scratch.deinit(allocator);

var dir: itijah.ParDirection = .auto_ltr;
var emb = try itijah.getParEmbeddingLevelsScratch(allocator, &emb_scratch, codepoints, &dir);
defer emb.deinit();

const visual = try itijah.reorderVisualOnlyScratch(
    allocator,
    &re_scratch,
    codepoints,
    emb.levels,
    dir.toLevel(),
);
defer allocator.free(visual);
```

## API / ABI Stability

`itijah` is currently a Zig source package API (not a stable C ABI).

- Public Zig APIs are intended to be maintainable and allocator-explicit.
- A stable binary ABI across Zig compiler versions is not guaranteed.
- If you need a stable C ABI boundary, expose a dedicated C wrapper layer and version it explicitly.

For now, keep API usage pinned to a tagged release and the documented minimum Zig version.

## Building

```sh
zig build        # build library
zig build test   # run tests
zig build bench  # run itijah benchmark report
zig build bench-compare  # compare itijah vs fribidi vs ICU
zig build test-diff  # differential harness vs fribidi + ICU (deterministic generator)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch policy, required checks, release gate, and performance workflow.

Requires Zig 0.15.2+.

## Dependencies

- [uucode](https://github.com/jacobsandlund/uucode) v0.2.0 — Unicode property lookups
- [UCD](https://www.unicode.org/Public/zipped/16.0.0/UCD.zip) — conformance test data (lazy, test-only)
- For `bench-compare`:
  - system FriBidi headers + library
  - ICU runtime library (`icuuc`) available on host (loaded dynamically)
- For `test-diff`:
  - system FriBidi headers + library
  - ICU runtime library (`icuuc`) available on host (loaded dynamically)

### Shared `uucode` integration

If a host app already creates a `uucode` module (for example to avoid duplicate module instances in a mono-build), depend on `itijah` with:

```zig
const itijah_dep = b.dependency("itijah", .{
    .target = target,
    .optimize = optimize,
    .shared_uucode = true,
});
const itijah_mod = itijah_dep.module("itijah");
itijah_mod.addImport("uucode", shared_uucode_mod);
```

When `shared_uucode = true`, `itijah` exports the library module without creating its own `uucode` import, so the caller can inject a shared one.
For standalone development in this repository, run build/test commands without that flag.

### `bench-compare` setup

macOS (Homebrew):

```sh
brew install fribidi icu4c
```

## Benchmarks

Detailed benchmark tables and run context live in [docs/benchmarks.md](docs/benchmarks.md).

```sh
zig build bench
```

`bench` reports:
- mean `ns` and `ns/codepoint`
- mean allocation count
- mean allocated bytes
- mean peak bytes

for LTR / RTL / mixed corpora at 16/64/256/1024 codepoints.

```sh
zig build bench-compare
```

`bench-compare` runs the same corpus against:
- `itijah`
- `fribidi`
- ICU `ubidi`

and prints:
- feature parity summary vs FriBidi (exact levels + visual map for shared cases)
- aligned KPIs for `analysis` and `reorder_line`.

`bench-compare` corpora include:
- LTR/RTL/MIXED at lengths:
  - `16`, `64`, `256`, `1024`, `2048`, `4096`, `10000`, `20000`

Useful compare modes:

```sh
# parity-only quick guardrail (no full perf run)
ITIJAH_COMPARE_ONLY_PARITY=1 zig build bench-compare

# run compare with itijah scratch reuse mode enabled
ITIJAH_COMPARE_ITIJAH_REUSE=1 zig build bench-compare
```

Interpretation notes:
- `analysis` and `reorder_line` measure different work. `reorder_line` includes visual output plus index-map construction.
- On LTR-heavy inputs, `itijah` typically has lower allocation count and lower bytes for `analysis` due fast-path behavior.
- On some medium/large cases, `reorder_line` byte footprint can be higher than visual-only paths because `itijah` returns both maps (`l_to_v` and `v_to_l`) plus visual output.
- For terminal render loops that only need visual codepoints, prefer `reorderVisualOnlyScratch` to reduce allocation pressure while keeping speed.
- `bench-compare` now reports numeric memory counters for all implementations (itijah, fribidi, ICU).
- Probe counters are finalized before metric return in the harness (no deferred-return sampling bug).
- Memory probe support for C backends is currently implemented for macOS and glibc Linux. `bench-compare` fails fast on unsupported targets to avoid partial (`n/a`) reporting.

Note: benchmark sources (`bench/`) are intentionally not exported in package `.paths`.
Run benchmark steps from a source checkout of this repository.

## Differential Harness

```sh
zig build test-diff
```

`test-diff` runs deterministic differential checks against:
- `fribidi`
- ICU `ubidi`

Input sources:
- curated in-repo corpus (targeted edge cases)
- deterministic generated corpus (fixed seeds, weighted profile mix)

Generated profiles cover:
- pure LTR
- pure RTL (Arabic/Hebrew/Persian letters)
- mixed LTR/RTL
- controls-heavy (isolates)
- brackets-heavy
- whitespace-heavy (space + tab)

The generator includes:
- European digits (`0-9`)
- Arabic-Indic digits (`U+0660..U+0669`)
- Eastern Arabic/Persian digits (`U+06F0..U+06F9`)
- Arabic tashkeel marks (`U+064B..U+0652`)
- neutrals, brackets, spaces, tabs, isolate controls

By default, `test-diff` reports mismatches but does not fail the build.
Enable strict gates:

```sh
# fail if ICU mismatches are found
ITIJAH_DIFF_REQUIRE_ICU=1 zig build test-diff

# fail if FriBidi mismatches are found
ITIJAH_DIFF_REQUIRE_FRIBIDI=1 zig build test-diff

# control run size/report verbosity
ITIJAH_DIFF_CASES_PER_PROFILE=12 ITIJAH_DIFF_MAX_LEN=2048 ITIJAH_DIFF_MAX_REPORTED=50 zig build test-diff
```

## Conformance Harness

`src/test/conformance.zig` parses and executes real Unicode conformance data:
- `BidiTest.txt`
- `BidiCharacterTest.txt`

Default mode is filtered (fast CI/PR mode). Full mode is available:

```sh
ITIJAH_CONFORMANCE_MODE=full zig build test
```

or

```sh
ITIJAH_CONFORMANCE_FULL=1 zig build test
```

Release-fast full conformance (useful when you want faster turnaround):

```sh
ITIJAH_CONFORMANCE_MODE=full zig build test -Doptimize=ReleaseFast
```

## Project Structure

```
src/
  lib.zig              — Public API
  core/
    level.zig          — BidiLevel type, helpers
    types.zig          — ParDirection, flags, result types
    embedding.zig      — Rules P2-P3, X1-X8, W1-W7, N0-N2, I1-I2
    reorder.zig        — Rules L1, L2
  data/
    unicode.zig        — uucode wrappers for bidi class, brackets, joining type
    mirroring.zig      — BidiMirroring.txt pairs, binary search
  shaping/
    joining.zig        — Arabic joining (Phase 2 stub)
    shaping.zig        — Arabic shaping + mirroring application (Phase 2 stub)
  test/
    conformance.zig    — BidiTest.txt / BidiCharacterTest.txt harness
    parity.zig         — External parity workflow placeholder (no hard dependency)
    invariants.zig     — Property/fuzz tests
    diff_oracle.zig    — Differential harness vs FriBidi + ICU (deterministic corpus)
bench/
  bench.zig            — itijah benchmark harness with timing+memory KPIs
  compare.zig          — itijah vs fribidi vs ICU comparison harness
docs/
  benchmarks.md        — benchmark commands, environment, KPI tables
  compatibility.md     — parity/diff/conformance compatibility snapshot
```

## License

MIT
