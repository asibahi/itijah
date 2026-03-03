const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const level_mod = @import("level.zig");
const BidiLevel = level_mod.BidiLevel;
const types = @import("types.zig");
const unicode = @import("../data/unicode.zig");
const BidiClass = unicode.BidiClass;
const mirroring = @import("../data/mirroring.zig");

const visual_inplace_threshold: u32 = 2048;
const compact_map_min_len: u32 = 8192;

pub const ReorderScratch = struct {
    map16: std.ArrayListUnmanaged(u16) = .{},
    map32: std.ArrayListUnmanaged(u32) = .{},

    pub fn deinit(self: *ReorderScratch, allocator: Allocator) void {
        self.map16.deinit(allocator);
        self.map32.deinit(allocator);
    }
};

/// Reorder a line of codepoints from logical to visual order.
/// Implements Rules L1 (part 4), L2. L3/L4 are Phase 2.
pub fn reorderLine(
    allocator: Allocator,
    codepoints: []const u21,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) !types.ReorderResult {
    const len: u32 = @intCast(codepoints.len);
    std.debug.assert(codepoints.len == levels.len);

    if (len == 0) {
        const visual = try allocator.alloc(u21, 0);
        errdefer allocator.free(visual);
        const l_to_v = try allocator.alloc(u32, 0);
        errdefer allocator.free(l_to_v);
        const v_to_l = try allocator.alloc(u32, 0);
        return .{
            .visual = visual,
            .l_to_v = l_to_v,
            .v_to_l = v_to_l,
            .max_level = base_level,
            .allocator = allocator,
        };
    }

    // Build index map
    const map = try allocator.alloc(u32, len);
    errdefer allocator.free(map);
    initIdentityMap(map);

    // Find max level
    var max_level: BidiLevel = base_level;
    var min_odd_level: BidiLevel = level_mod.max_resolved_level + 1;
    for (levels) |l| {
        if (l > max_level) max_level = l;
        if (level_mod.isRtl(l) and l < min_odd_level) min_odd_level = l;
    }

    // L2: Reverse subsequences at each level from max down to min odd
    applyL2(map, levels, len, min_odd_level, max_level);

    // Build visual string
    const visual = try allocator.alloc(u21, len);
    errdefer allocator.free(visual);
    for (0..len) |i| {
        visual[i] = codepoints[map[i]];
    }

    // Build reverse map (v_to_l is already `map`, build l_to_v)
    const l_to_v = try allocator.alloc(u32, len);
    errdefer allocator.free(l_to_v);
    for (map, 0..) |logical_idx, visual_idx| {
        l_to_v[logical_idx] = @intCast(visual_idx);
    }

    return .{
        .visual = visual,
        .l_to_v = l_to_v,
        .v_to_l = map,
        .max_level = max_level,
        .allocator = allocator,
    };
}

/// Reorder a line and return only the visual codepoints.
/// Uses less memory than `reorderLine` because it does not build index maps.
pub fn reorderVisualOnly(
    allocator: Allocator,
    codepoints: []const u21,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) ![]u21 {
    const len: u32 = @intCast(codepoints.len);
    std.debug.assert(codepoints.len == levels.len);

    const visual = try allocator.alloc(u21, len);
    errdefer allocator.free(visual);
    if (len == 0) return visual;

    var max_level: BidiLevel = base_level;
    var min_odd_level: BidiLevel = level_mod.max_resolved_level + 1;
    for (levels) |l| {
        if (l > max_level) max_level = l;
        if (level_mod.isRtl(l) and l < min_odd_level) min_odd_level = l;
    }

    if (min_odd_level > max_level) {
        @memcpy(visual, codepoints);
        return visual;
    }

    if (len <= visual_inplace_threshold) {
        @memcpy(visual, codepoints);
        applyL2Visual(visual, levels, len, min_odd_level, max_level);
        return visual;
    }

    if (len >= compact_map_min_len and len <= std.math.maxInt(u16)) {
        const map = try allocator.alloc(u16, len);
        defer allocator.free(map);
        initIdentityMap(map);
        applyL2(map, levels, len, min_odd_level, max_level);
        for (0..len) |i| {
            visual[i] = codepoints[map[i]];
        }
    } else {
        const map = try allocator.alloc(u32, len);
        defer allocator.free(map);
        initIdentityMap(map);
        applyL2(map, levels, len, min_odd_level, max_level);
        for (0..len) |i| {
            visual[i] = codepoints[map[i]];
        }
    }

    return visual;
}

/// Reorder a line and return only the visual codepoints using reusable scratch memory.
pub fn reorderVisualOnlyScratch(
    allocator: Allocator,
    scratch: *ReorderScratch,
    codepoints: []const u21,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) ![]u21 {
    const len: u32 = @intCast(codepoints.len);
    std.debug.assert(codepoints.len == levels.len);

    const visual = try allocator.alloc(u21, len);
    errdefer allocator.free(visual);
    if (len == 0) return visual;

    var max_level: BidiLevel = base_level;
    var min_odd_level: BidiLevel = level_mod.max_resolved_level + 1;
    for (levels) |l| {
        if (l > max_level) max_level = l;
        if (level_mod.isRtl(l) and l < min_odd_level) min_odd_level = l;
    }

    if (min_odd_level > max_level) {
        @memcpy(visual, codepoints);
        return visual;
    }

    // For medium sizes, reverse visual output in-place to avoid map setup/allocation.
    // For very large lines, map+gather is typically faster despite higher memory writes.
    if (len <= visual_inplace_threshold) {
        @memcpy(visual, codepoints);
        applyL2Visual(visual, levels, len, min_odd_level, max_level);
        return visual;
    }

    if (len >= compact_map_min_len and len <= std.math.maxInt(u16)) {
        try scratch.map16.ensureTotalCapacity(allocator, len);
        scratch.map16.items.len = len;
        const map = scratch.map16.items;
        initIdentityMap(map);
        applyL2(map, levels, len, min_odd_level, max_level);
        for (0..len) |i| {
            visual[i] = codepoints[map[i]];
        }
    } else {
        try scratch.map32.ensureTotalCapacity(allocator, len);
        scratch.map32.items.len = len;
        const map = scratch.map32.items;
        initIdentityMap(map);
        applyL2(map, levels, len, min_odd_level, max_level);
        for (0..len) |i| {
            visual[i] = codepoints[map[i]];
        }
    }
    return visual;
}

/// Build logical-to-visual index map from embedding levels.
pub fn logToVisMap(
    allocator: Allocator,
    levels: []const BidiLevel,
    base_level: BidiLevel,
) ![]u32 {
    const len: u32 = @intCast(levels.len);
    if (len == 0) return try allocator.alloc(u32, 0);

    const map = try allocator.alloc(u32, len);
    errdefer allocator.free(map);
    initIdentityMap(map);

    var max_level: BidiLevel = base_level;
    var min_odd: BidiLevel = level_mod.max_resolved_level + 1;
    for (levels) |l| {
        if (l > max_level) max_level = l;
        if (level_mod.isRtl(l) and l < min_odd) min_odd = l;
    }

    applyL2(map, levels, len, min_odd, max_level);

    // Convert v_to_l to l_to_v
    const l_to_v = try allocator.alloc(u32, len);
    for (map, 0..) |logical, visual| {
        l_to_v[logical] = @intCast(visual);
    }
    allocator.free(map);

    return l_to_v;
}

/// Remove bidi control marks from a codepoint array.
///
/// If `levels` is provided, this function compacts it in-place so `levels[0..new_len]`
/// stays aligned with the returned codepoint order.
pub fn removeBidiMarks(
    allocator: Allocator,
    codepoints: []const u21,
    levels: ?[]BidiLevel,
) !types.RemoveBidiMarksResult {
    const out = try allocator.alloc(u21, codepoints.len);
    errdefer allocator.free(out);

    var j: u32 = 0;
    for (codepoints, 0..) |cp, i| {
        if (!unicode.isBidiControl(cp)) {
            out[j] = cp;
            if (levels) |lvls| {
                lvls[j] = lvls[i];
            }
            j += 1;
        }
    }

    return .{ .result = out, .new_len = j };
}

fn initIdentityMap(map: anytype) void {
    const T = std.meta.Elem(@TypeOf(map));
    for (0..map.len) |i| {
        map[i] = @as(T, @intCast(i));
    }
}

fn applyL2(
    map: anytype,
    levels: []const BidiLevel,
    len: u32,
    min_odd_level: BidiLevel,
    max_level: BidiLevel,
) void {
    const T = std.meta.Elem(@TypeOf(map));
    if (min_odd_level > max_level) return;

    var lev: BidiLevel = max_level;
    while (lev >= min_odd_level) : (lev -= 1) {
        var i: u32 = 0;
        while (i < len) {
            if (levels[i] >= lev) {
                var end = i + 1;
                while (end < len and levels[end] >= lev) end += 1;
                reverseSlice(T, map[i..end]);
                i = end;
            } else {
                i += 1;
            }
        }
        if (lev == 0) break;
    }
}

fn applyL2Visual(
    visual: []u21,
    levels: []const BidiLevel,
    len: u32,
    min_odd_level: BidiLevel,
    max_level: BidiLevel,
) void {
    var lev: BidiLevel = max_level;
    while (lev >= min_odd_level) : (lev -= 1) {
        var i: u32 = 0;
        while (i < len) {
            if (levels[i] >= lev) {
                var end = i + 1;
                while (end < len and levels[end] >= lev) end += 1;
                reverseSlice(u21, visual[i..end]);
                i = end;
            } else {
                i += 1;
            }
        }
        if (lev == 0) break;
    }
}

fn reverseSlice(comptime T: type, slice: []T) void {
    std.mem.reverse(T, slice);
}

fn reorderLineEmptyAllocProbe(allocator: Allocator) !void {
    const cps = [_]u21{};
    const levels = [_]BidiLevel{};
    var result = try reorderLine(allocator, &cps, &levels, 0);
    defer result.deinit();
}

test "allocation failure safety: reorderLine empty input" {
    const testing = std.testing;
    try testing.checkAllAllocationFailures(testing.allocator, reorderLineEmptyAllocProbe, .{});
}

test "reorder pure LTR" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const cps = [_]u21{ 'H', 'e', 'l', 'l', 'o' };
    const levels = [_]BidiLevel{ 0, 0, 0, 0, 0 };
    var result = try reorderLine(gpa, &cps, &levels, 0);
    defer result.deinit();

    try testing.expectEqualSlices(u21, &cps, result.visual);
}

test "reorder pure RTL" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const cps = [_]u21{ 0x05D0, 0x05D1, 0x05D2 };
    const levels = [_]BidiLevel{ 1, 1, 1 };
    var result = try reorderLine(gpa, &cps, &levels, 1);
    defer result.deinit();

    // RTL should reverse
    try testing.expectEqual(@as(u21, 0x05D2), result.visual[0]);
    try testing.expectEqual(@as(u21, 0x05D1), result.visual[1]);
    try testing.expectEqual(@as(u21, 0x05D0), result.visual[2]);
}

test "reorder mixed LTR-RTL" {
    const testing = std.testing;
    const gpa = testing.allocator;

    // "Hello אבג"
    const cps = [_]u21{ 'H', 'e', 'l', 'l', 'o', ' ', 0x05D0, 0x05D1, 0x05D2 };
    const levels = [_]BidiLevel{ 0, 0, 0, 0, 0, 0, 1, 1, 1 };
    var result = try reorderLine(gpa, &cps, &levels, 0);
    defer result.deinit();

    // LTR part stays, RTL part reverses
    try testing.expectEqual(@as(u21, 'H'), result.visual[0]);
    try testing.expectEqual(@as(u21, 'o'), result.visual[4]);
    try testing.expectEqual(@as(u21, 0x05D2), result.visual[6]);
    try testing.expectEqual(@as(u21, 0x05D0), result.visual[8]);
}

test "reorder visual only" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const cps = [_]u21{ 'H', 'i', ' ', 0x05D0, 0x05D1 };
    const levels = [_]BidiLevel{ 0, 0, 0, 1, 1 };
    const visual = try reorderVisualOnly(gpa, &cps, &levels, 0);
    defer gpa.free(visual);

    try testing.expectEqual(@as(u21, 'H'), visual[0]);
    try testing.expectEqual(@as(u21, 0x05D1), visual[3]);
    try testing.expectEqual(@as(u21, 0x05D0), visual[4]);
}

test "reorder visual only scratch reuse" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var scratch = ReorderScratch{};
    defer scratch.deinit(gpa);

    const cps1 = [_]u21{ 'A', ' ', 0x05D0, 0x05D1 };
    const lv1 = [_]BidiLevel{ 0, 0, 1, 1 };
    const vis1 = try reorderVisualOnlyScratch(gpa, &scratch, &cps1, &lv1, 0);
    defer gpa.free(vis1);
    try testing.expectEqual(@as(u21, 0x05D1), vis1[2]);
    try testing.expectEqual(@as(u21, 0x05D0), vis1[3]);

    const cps2 = [_]u21{ 'X', 'Y', 'Z' };
    const lv2 = [_]BidiLevel{ 0, 0, 0 };
    const vis2 = try reorderVisualOnlyScratch(gpa, &scratch, &cps2, &lv2, 0);
    defer gpa.free(vis2);
    try testing.expectEqualSlices(u21, &cps2, vis2);
}

test "remove bidi marks" {
    const testing = std.testing;
    const gpa = testing.allocator;

    const cps = [_]u21{ 'A', 0x200E, 'B', 0x200F, 'C' };
    const result = try removeBidiMarks(gpa, &cps, null);
    defer gpa.free(result.result);

    try testing.expectEqual(@as(u32, 3), result.new_len);
    try testing.expectEqual(@as(u21, 'A'), result.result[0]);
    try testing.expectEqual(@as(u21, 'B'), result.result[1]);
    try testing.expectEqual(@as(u21, 'C'), result.result[2]);
}
