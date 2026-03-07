# Usage Guide

## Overview

itijah implements the Unicode Bidirectional Algorithm (UAX #9) in Zig. It takes a sequence of Unicode codepoints (`[]const u21`) and resolves their visual display order for correct rendering of mixed left-to-right and right-to-left text.

The core pipeline is:

1. **Analysis** — determine embedding levels for each codepoint (`getParEmbeddingLevels`)
2. **Reorder** — produce visual order from logical order (`reorderLine`, `reorderVisualOnly`)
3. **Maps/Runs** — logical-to-visual index maps and visual run slices (`logToVis`, `getVisualRuns`)

Or use `resolveVisualLayout` to get all of these in a single call.

## Which API should I use?

itijah offers two API styles:

### Owned (one-shot)

```zig
var emb = try itijah.getParEmbeddingLevels(allocator, codepoints, &dir);
defer emb.deinit(allocator);
```

- Allocates fresh buffers per call
- Caller owns the result and frees via `deinit(allocator)`
- Simple, no setup needed
- Best for: tools, scripts, tests, single calls, anywhere allocation cost doesn't matter

### Scratch (zero-alloc hot path)

```zig
var scratch = itijah.EmbeddingScratch{};
defer scratch.deinit(allocator);

const view = try itijah.getParEmbeddingLevelsScratchView(allocator, &scratch, codepoints, &dir);
// view.levels is valid until the next call that mutates scratch
```

- Reuses internal buffers across calls — zero allocations after warmup
- Returns a **view** (borrowed slice) into scratch-owned memory
- View is valid until the next call that mutates the same scratch object
- Best for: render loops, terminals, editors — anything calling bidi per frame or per line
- Functions: `getParEmbeddingLevelsScratchView`, `reorderLineScratch`, `reorderVisualOnlyScratch`, `logToVisScratch`, `getVisualRunsScratch`, `resolveVisualLayoutScratch`

### Decision guide

| Scenario | Use |
|----------|-----|
| Processing one paragraph or document | Owned API |
| Render loop processing lines every frame | Scratch API |
| Testing or prototyping | Owned API |
| Terminal emulator integration | Scratch (`resolveVisualLayoutScratch`) |
| CLI tool that processes a file | Owned API |

## Memory ownership

### Owned results

`EmbeddingResult`, `ReorderResult`, and `VisualLayout` hold heap-allocated slices. The caller frees them by calling `deinit(allocator)` with the same allocator used to create them:

```zig
var result = try itijah.getParEmbeddingLevels(allocator, codepoints, &dir);
defer result.deinit(allocator);
// result.levels is valid until deinit
```

### Scratch views

`EmbeddingScratchView`, `ReorderResultScratchView`, and `VisualLayoutScratchView` are **borrowed views** into scratch-owned memory. They have no `deinit` — the scratch object owns the memory:

```zig
var scratch = itijah.EmbeddingScratch{};
defer scratch.deinit(allocator);  // frees all scratch-owned buffers

const view = try itijah.getParEmbeddingLevelsScratchView(allocator, &scratch, codepoints, &dir);
// view.levels points into scratch internals
// valid until the next call that mutates scratch
```

### Plain slices

`logToVis` and `getVisualRuns` return caller-owned slices (not wrapped in a result struct). Free with `allocator.free(slice)`. Their scratch variants return views into scratch-owned memory.

## Scratch lifecycle

```zig
// 1. Create (zero-cost, no allocation)
var scratch = itijah.VisualLayoutScratch{};

// 2. Use in a loop — buffers grow as needed, then stabilize
for (lines) |line| {
    const view = try itijah.resolveVisualLayoutScratch(allocator, &scratch, line, opts);
    // use view.levels, view.runs, view.l_to_v, view.v_to_l
}

// 3. Free when done
scratch.deinit(allocator);
```

After processing a few lines, scratch buffers are large enough for typical inputs and no further allocations occur. Scratch memory is proportional to the longest line processed — roughly 40 KB per 1,000 codepoints.

## Terminal integration

For terminal emulators, use `resolveVisualLayoutScratch` with a scratch object that persists across frames:

```zig
// Per-terminal state (create once, reuse across frames)
var bidi_scratch = itijah.VisualLayoutScratch{};
defer bidi_scratch.deinit(allocator);

// Per-line in render loop
fn renderLine(scratch: *itijah.VisualLayoutScratch, allocator: Allocator, codepoints: []const u21) !void {
    const layout = try itijah.resolveVisualLayoutScratch(allocator, scratch, codepoints, .{
        .base_dir = .auto_ltr,
    });

    for (layout.runs) |run| {
        // Feed each run to the shaper in logical order
        const logical_start = run.logical_start;
        const logical_end = run.logicalEnd();
        // Shape codepoints[logical_start..logical_end] with run.is_rtl direction
        // Place glyphs at visual positions starting from run.visual_start
    }
}
```

This gives you zero allocations per line after the first few lines warm up the scratch buffers.
