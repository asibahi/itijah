//! itijah (اتجاه) — Zig-native Unicode Bidirectional Algorithm (UAX #9)
//!
//! Codepoint-based API inspired by FriBidi's design, implemented idiomatically in Zig.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core modules
pub const level = @import("core/level.zig");
pub const types = @import("core/types.zig");
pub const embedding = @import("core/embedding.zig");
pub const reorder = @import("core/reorder.zig");

// Data modules
pub const unicode = @import("data/unicode.zig");
pub const mirroring = @import("data/mirroring.zig");

// Shaping modules (Phase 2 stubs)
pub const joining = @import("shaping/joining.zig");
pub const shaping = @import("shaping/shaping.zig");

// Re-export primary types
pub const BidiLevel = level.BidiLevel;
pub const ParDirection = types.ParDirection;
pub const EmbeddingResult = types.EmbeddingResult;
pub const ReorderResult = types.ReorderResult;
pub const VisualRun = types.VisualRun;
pub const EmbeddingScratch = embedding.EmbeddingScratch;
pub const ReorderScratch = reorder.ReorderScratch;
pub const ReorderFlags = types.ReorderFlags;
pub const ShapeFlags = types.ShapeFlags;
pub const BidiClass = unicode.BidiClass;

/// Get paragraph embedding levels for a sequence of codepoints.
/// Implements UAX #9 Rules P2-P3, X1-X8, W1-W7, N0-N2, I1-I2, L1.
///
/// `par_dir` is input/output: if auto_ltr or auto_rtl, the resolved direction
/// is written back after paragraph direction detection (P2-P3).
pub fn getParEmbeddingLevels(
    allocator: Allocator,
    codepoints: []const u21,
    par_dir: *ParDirection,
) !EmbeddingResult {
    return embedding.getParEmbeddingLevels(allocator, codepoints, par_dir);
}

/// Get paragraph embedding levels for a sequence of codepoints with reusable scratch buffers.
pub fn getParEmbeddingLevelsScratch(
    allocator: Allocator,
    scratch: *EmbeddingScratch,
    codepoints: []const u21,
    par_dir: *ParDirection,
) !EmbeddingResult {
    return embedding.getParEmbeddingLevelsScratch(allocator, scratch, codepoints, par_dir);
}

/// Reorder a line of codepoints from logical to visual order.
/// Implements Rules L1.4, L2. Returns visual string and index maps.
///
/// L3 (NSM reordering) and L4 (mirroring) are deferred to Phase 2.
pub fn reorderLine(
    allocator: Allocator,
    codepoints: []const u21,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) !ReorderResult {
    return reorder.reorderLine(allocator, codepoints, levels, base_level);
}

/// Reorder a line and return only visual codepoints.
pub fn reorderVisualOnly(
    allocator: Allocator,
    codepoints: []const u21,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) ![]u21 {
    return reorder.reorderVisualOnly(allocator, codepoints, levels, base_level);
}

/// Reorder a line and return only visual codepoints with reusable scratch buffers.
pub fn reorderVisualOnlyScratch(
    allocator: Allocator,
    scratch: *ReorderScratch,
    codepoints: []const u21,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) ![]u21 {
    return reorder.reorderVisualOnlyScratch(allocator, scratch, codepoints, levels, base_level);
}

/// Build a logical-to-visual index map from embedding levels.
pub fn logToVis(
    allocator: Allocator,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) ![]u32 {
    return reorder.logToVisMap(allocator, levels, base_level);
}

/// Derive visual runs in visual order from embedding levels.
pub fn getVisualRuns(
    allocator: Allocator,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) ![]VisualRun {
    return reorder.visualRuns(allocator, levels, base_level);
}

/// Remove bidi control marks (LRM, RLM, ALM, LRE, RLE, PDF, LRO, RLO, LRI, RLI, FSI, PDI)
/// from a codepoint array.
///
/// If `levels` is provided, it is compacted in-place to match the filtered output order.
pub const RemoveBidiMarksResult = types.RemoveBidiMarksResult;

pub fn removeBidiMarks(
    allocator: Allocator,
    codepoints: []const u21,
    levels: ?[]BidiLevel,
) !RemoveBidiMarksResult {
    return reorder.removeBidiMarks(allocator, codepoints, levels);
}

/// Apply Arabic joining algorithm (Rules R1-R7).
/// Phase 2 stub — returns error.NotImplemented.
pub fn joinArabic(
    bidi_types: []const BidiClass,
    embedding_levels: []const BidiLevel,
    ar_props: []joining.ArabicProp,
) !void {
    return joining.joinArabic(bidi_types, embedding_levels, ar_props);
}

/// Apply shaping: mirroring (L4) and Arabic presentation forms.
/// Phase 2 stub — returns error.NotImplemented.
pub fn shape(
    codepoints: []u21,
    embedding_levels: []const BidiLevel,
    arabic_props: ?[]const joining.ArabicProp,
    flags: ShapeFlags,
) !void {
    return shaping.shape(codepoints, embedding_levels, arabic_props, flags);
}

// Tests
test {
    _ = level;
    _ = types;
    _ = embedding;
    _ = reorder;
    _ = unicode;
    _ = mirroring;
    _ = @import("test/conformance.zig");
    _ = @import("test/parity.zig");
    _ = @import("test/invariants.zig");
}

test "end-to-end: pure LTR" {
    const gpa = std.testing.allocator;
    var dir: ParDirection = .auto_ltr;
    const input = [_]u21{ 'H', 'e', 'l', 'l', 'o' };

    var emb = try getParEmbeddingLevels(gpa, &input, &dir);
    defer emb.deinit();

    try std.testing.expectEqual(ParDirection.ltr, emb.resolved_par_dir);

    var vis = try reorderLine(gpa, &input, emb.levels, 0);
    defer vis.deinit();

    try std.testing.expectEqualSlices(u21, &input, vis.visual);
}

test "end-to-end: pure RTL" {
    const gpa = std.testing.allocator;
    var dir: ParDirection = .auto_ltr;
    const input = [_]u21{ 0x05D0, 0x05D1, 0x05D2 };

    var emb = try getParEmbeddingLevels(gpa, &input, &dir);
    defer emb.deinit();

    try std.testing.expectEqual(ParDirection.rtl, emb.resolved_par_dir);

    var vis = try reorderLine(gpa, &input, emb.levels, 1);
    defer vis.deinit();

    try std.testing.expectEqual(@as(u21, 0x05D2), vis.visual[0]);
    try std.testing.expectEqual(@as(u21, 0x05D0), vis.visual[2]);
}

test "end-to-end: mixed LTR + RTL" {
    const gpa = std.testing.allocator;
    var dir: ParDirection = .auto_ltr;
    // "AB אב CD"
    const input = [_]u21{ 'A', 'B', ' ', 0x05D0, 0x05D1, ' ', 'C', 'D' };

    var emb = try getParEmbeddingLevels(gpa, &input, &dir);
    defer emb.deinit();

    try std.testing.expectEqual(ParDirection.ltr, emb.resolved_par_dir);
    try std.testing.expectEqual(@as(BidiLevel, 0), emb.levels[0]); // A
    try std.testing.expectEqual(@as(BidiLevel, 1), emb.levels[3]); // Alef
    try std.testing.expectEqual(@as(BidiLevel, 1), emb.levels[4]); // Bet
    try std.testing.expectEqual(@as(BidiLevel, 0), emb.levels[6]); // C

    var vis = try reorderLine(gpa, &input, emb.levels, 0);
    defer vis.deinit();

    // "AB " stays, "אב" reverses to "בא", " CD" stays
    try std.testing.expectEqual(@as(u21, 'A'), vis.visual[0]);
    try std.testing.expectEqual(@as(u21, 'B'), vis.visual[1]);
    try std.testing.expectEqual(@as(u21, 0x05D1), vis.visual[3]);
    try std.testing.expectEqual(@as(u21, 0x05D0), vis.visual[4]);
    try std.testing.expectEqual(@as(u21, 'D'), vis.visual[7]);
}

test "removeBidiMarks" {
    const gpa = std.testing.allocator;
    const input = [_]u21{ 'A', 0x200E, 'B', 0x202A, 'C' };
    const result = try removeBidiMarks(gpa, &input, null);
    defer gpa.free(result.result);

    try std.testing.expectEqual(@as(u32, 3), result.new_len);
    try std.testing.expectEqual(@as(u21, 'A'), result.result[0]);
    try std.testing.expectEqual(@as(u21, 'B'), result.result[1]);
    try std.testing.expectEqual(@as(u21, 'C'), result.result[2]);
}

test "stubs return NotImplemented" {
    var props = [_]joining.ArabicProp{0};
    try std.testing.expectError(error.NotImplemented, joinArabic(&.{}, &.{}, &props));

    var cps = [_]u21{'A'};
    try std.testing.expectError(error.NotImplemented, shape(&cps, &.{}, null, .{}));
}
