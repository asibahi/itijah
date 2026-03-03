# Contributing

## Branching

- `main` is always releasable.
- Open PRs from short-lived feature/fix branches.
- Keep changes small and measurable.

## Required checks (PR gate)

CI execution on PRs is label-gated:
- add `ci-approved` label to run `.github/workflows/ci.yml`
- without the label, the CI job is skipped for that PR event

Run these before merge:

```sh
zig build
zig build test
ITIJAH_DIFF_CASES_PER_PROFILE=2 ITIJAH_DIFF_MAX_REPORTED=12 zig build test-diff
```

Notes:
- `zig build test` runs filtered conformance by default.
- `test-diff` is signal-oriented by default; mismatches are reported but not gate-failing.

## Full validation (release gate)

Run before release or when changing core bidi logic:

```sh
ITIJAH_CONFORMANCE_MODE=full zig build test
ITIJAH_COMPARE_ONLY_PARITY=1 zig build bench-compare
```

Optional stricter differential gate:

```sh
ITIJAH_DIFF_REQUIRE_ICU=1 ITIJAH_DIFF_CASES_PER_PROFILE=6 zig build test-diff
```

## Performance workflow

Use this sequence when optimizing:

```sh
zig build bench
zig build bench-compare
ITIJAH_COMPARE_ITIJAH_REUSE=1 zig build bench-compare
```

Track:
- `mean_ns`
- `ns_per_cp`
- `alloc_count`
- `allocated_bytes`
- `peak_bytes`

## Profiling workflow

1. Reproduce slowdown with a concrete corpus/case.
2. Capture baseline (`bench` + `bench-compare`).
3. Profile hot path (embedding or reorder) using platform tools.
4. Apply one targeted change.
5. Re-run PR gate + full conformance (for core changes).

## Policy

- Correctness and conformance come first.
- Parity vs FriBidi is a compatibility signal, not the normative source of truth.
- Keep allocator-explicit API and `u21` indexing behavior stable.
