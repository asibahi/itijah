# Compatibility

Last updated: 2026-03-03.

## Reference Engines

`itijah` is checked against:

- FriBidi
- ICU `ubidi`

## Commands

```sh
ITIJAH_COMPARE_ONLY_PARITY=1 zig build bench-compare
ITIJAH_DIFF_CASES_PER_PROFILE=2 ITIJAH_DIFF_MAX_REPORTED=12 zig build test-diff
ITIJAH_CONFORMANCE_MODE=full zig build test
```

## Current Status

- FriBidi parity guardrail (`bench-compare`, parity-only): `11/12 PASS`
- Known parity delta: `MIXED-1024`, `kind=levels`, `idx=434`, `expected=15`, `actual=16`
- Differential harness summary:
  - `summary: total=61 | icu pass=57 fail=0 warn=4 | fribidi pass=36 fail=24 warn=1 | reported=12`
  - this is from smoke-mode (`ITIJAH_DIFF_CASES_PER_PROFILE=2`), not a max-size run
- `bench-compare` parity and `test-diff` totals are not directly comparable:
  - parity uses a fixed 12-case benchmark corpus
  - differential runs curated + generated cases and tracks pass/fail/warn per oracle
- Full Unicode conformance:
  - `BidiTest (full): failed=0`
  - `BidiCharacterTest (full): failed=0`

## Interpretation

- Unicode conformance test files (`BidiTest.txt`, `BidiCharacterTest.txt`) are the normative correctness gate.
- FriBidi/ICU comparisons are compatibility signals and help track implementation differences.
- Some differences are intentional when strict UAX #9 behavior is prioritized.

## Strict Differential Modes

```sh
# fail on ICU mismatches
ITIJAH_DIFF_REQUIRE_ICU=1 zig build test-diff

# fail on FriBidi mismatches
ITIJAH_DIFF_REQUIRE_FRIBIDI=1 zig build test-diff
```
