const std = @import("std");
const itijah = @import("itijah");

const c = @cImport({
    @cInclude("fribidi/fribidi.h");
});

extern fn itijah_fribidi_probe_available() c_int;
extern fn itijah_fribidi_probe_begin() void;
extern fn itijah_fribidi_probe_finish(alloc_count: *u64, allocated_bytes: *u64, peak_bytes: *u64) void;

const Allocator = std.mem.Allocator;

const Op = enum {
    analysis,
    reorder_line,
};

const Impl = enum {
    itijah,
    fribidi,
    icu,
};

const Metrics = struct {
    ns: u64,
    alloc_count: usize,
    allocated_bytes: usize,
    peak_bytes: usize,
};

const Aggregate = struct {
    iterations: usize = 0,
    total_ns: u128 = 0,
    total_alloc_count: u128 = 0,
    total_allocated_bytes: u128 = 0,
    total_peak_bytes: u128 = 0,

    fn add(self: *Aggregate, m: Metrics) void {
        self.iterations += 1;
        self.total_ns += m.ns;
        self.total_alloc_count += m.alloc_count;
        self.total_allocated_bytes += m.allocated_bytes;
        self.total_peak_bytes += m.peak_bytes;
    }

    fn meanNs(self: Aggregate) f64 {
        return @as(f64, @floatFromInt(self.total_ns)) / @as(f64, @floatFromInt(self.iterations));
    }

    fn meanAllocCount(self: Aggregate) f64 {
        return @as(f64, @floatFromInt(self.total_alloc_count)) / @as(f64, @floatFromInt(self.iterations));
    }

    fn meanAllocatedBytes(self: Aggregate) f64 {
        return @as(f64, @floatFromInt(self.total_allocated_bytes)) / @as(f64, @floatFromInt(self.iterations));
    }

    fn meanPeakBytes(self: Aggregate) f64 {
        return @as(f64, @floatFromInt(self.total_peak_bytes)) / @as(f64, @floatFromInt(self.iterations));
    }
};

const MeasuringAllocator = struct {
    parent: Allocator,
    current_bytes: usize = 0,
    peak_bytes: usize = 0,
    allocation_count: usize = 0,
    allocated_bytes: usize = 0,

    fn init(parent: Allocator) MeasuringAllocator {
        return .{ .parent = parent };
    }

    fn allocator(self: *MeasuringAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn onGrow(self: *MeasuringAllocator, amount: usize) void {
        self.current_bytes += amount;
        self.allocated_bytes += amount;
        if (self.current_bytes > self.peak_bytes) self.peak_bytes = self.current_bytes;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *MeasuringAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.parent.rawAlloc(len, alignment, ret_addr);
        if (ptr != null) {
            self.allocation_count += 1;
            self.onGrow(len);
        }
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *MeasuringAllocator = @ptrCast(@alignCast(ctx));
        const ok = self.parent.rawResize(buf, alignment, new_len, ret_addr);
        if (ok) {
            self.allocation_count += 1;
            if (new_len > buf.len) {
                self.onGrow(new_len - buf.len);
            } else {
                self.current_bytes -= (buf.len - new_len);
            }
        }
        return ok;
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *MeasuringAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.parent.rawRemap(buf, alignment, new_len, ret_addr);
        if (ptr != null) {
            self.allocation_count += 1;
            if (new_len > buf.len) {
                self.onGrow(new_len - buf.len);
            } else {
                self.current_bytes -= (buf.len - new_len);
            }
        }
        return ptr;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *MeasuringAllocator = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(buf, alignment, ret_addr);
        self.current_bytes -= buf.len;
    }

    const IterationState = struct {
        start_current_bytes: usize,
    };

    fn beginIteration(self: *MeasuringAllocator) IterationState {
        const state = IterationState{ .start_current_bytes = self.current_bytes };
        self.allocation_count = 0;
        self.allocated_bytes = 0;
        self.peak_bytes = self.current_bytes;
        return state;
    }

    fn endIteration(self: *MeasuringAllocator, state: IterationState, ns: u64) Metrics {
        return .{
            .ns = ns,
            .alloc_count = self.allocation_count,
            .allocated_bytes = self.allocated_bytes,
            .peak_bytes = self.peak_bytes -| state.start_current_bytes,
        };
    }
};

const ItijahScratchContext = struct {
    embedding: itijah.EmbeddingScratch = .{},
    reorder: itijah.ReorderScratch = .{},

    fn deinit(self: *ItijahScratchContext, allocator: Allocator) void {
        self.embedding.deinit(allocator);
        self.reorder.deinit(allocator);
    }
};

const Case = struct {
    name: []const u8,
    cps: []const u21,
};

const FribidiResult = struct {
    len: usize,
    levels: [1024]c.FriBidiLevel,
    v_to_l: [1024]u32,
};

const Mismatch = struct {
    kind: enum { levels, v_to_l },
    index: usize,
    expected: u32,
    actual: u32,
};

const UBiDi = opaque {};
const UChar = u16;
const UBiDiLevel = u8;
const UErrorCode = c_int;
const U_ZERO_ERROR: UErrorCode = 0;
const UBIDI_DEFAULT_LTR: UBiDiLevel = 0xFE;

const IcuApi = struct {
    lib: std.DynLib,
    major: u8,
    openSized: *const fn (c_int, c_int, *UErrorCode) callconv(.c) ?*UBiDi,
    close: *const fn (*UBiDi) callconv(.c) void,
    setPara: *const fn (*UBiDi, [*]const UChar, c_int, UBiDiLevel, ?[*]UBiDiLevel, *UErrorCode) callconv(.c) void,
    getLevels: *const fn (*UBiDi, *UErrorCode) callconv(.c) [*]const UBiDiLevel,
    getVisualMap: *const fn (*UBiDi, [*]c_int, *UErrorCode) callconv(.c) void,

    fn deinit(self: *IcuApi) void {
        self.lib.close();
    }
};

const max_bench_case_len = 20_000;

fn generateLtrCorpus(comptime n: usize) [n]u21 {
    @setEvalBranchQuota(500_000);
    var buf: [n]u21 = undefined;
    for (0..n) |i| buf[i] = @intCast('A' + (i % 26));
    return buf;
}

fn generateRtlCorpus(comptime n: usize) [n]u21 {
    @setEvalBranchQuota(500_000);
    var buf: [n]u21 = undefined;
    for (0..n) |i| buf[i] = @intCast(0x05D0 + (i % 27));
    return buf;
}

fn generateMixedCorpus(comptime n: usize) [n]u21 {
    @setEvalBranchQuota(500_000);
    var buf: [n]u21 = undefined;
    for (0..n) |i| {
        if (i % 4 == 0) {
            buf[i] = @intCast(0x05D0 + (i % 27));
        } else if (i % 5 == 0) {
            buf[i] = @intCast('0' + (i % 10));
        } else if (i % 7 == 0) {
            buf[i] = '(';
        } else if (i % 9 == 0) {
            buf[i] = ')';
        } else if (i % 11 == 0) {
            buf[i] = 0x2067;
        } else if (i % 13 == 0) {
            buf[i] = 0x2069;
        } else if (i % 17 == 0) {
            buf[i] = ' ';
        } else {
            buf[i] = @intCast('a' + (i % 26));
        }
    }
    return buf;
}

const ltr_16 = generateLtrCorpus(16);
const ltr_64 = generateLtrCorpus(64);
const ltr_256 = generateLtrCorpus(256);
const ltr_1024 = generateLtrCorpus(1024);
const rtl_16 = generateRtlCorpus(16);
const rtl_64 = generateRtlCorpus(64);
const rtl_256 = generateRtlCorpus(256);
const rtl_1024 = generateRtlCorpus(1024);
const mixed_16 = generateMixedCorpus(16);
const mixed_64 = generateMixedCorpus(64);
const mixed_256 = generateMixedCorpus(256);
const mixed_1024 = generateMixedCorpus(1024);
const ltr_2048 = generateLtrCorpus(2048);
const ltr_4096 = generateLtrCorpus(4096);
const ltr_10000 = generateLtrCorpus(10_000);
const ltr_20000 = generateLtrCorpus(20_000);
const rtl_2048 = generateRtlCorpus(2048);
const rtl_4096 = generateRtlCorpus(4096);
const rtl_10000 = generateRtlCorpus(10_000);
const rtl_20000 = generateRtlCorpus(20_000);
const mixed_2048 = generateMixedCorpus(2048);
const mixed_4096 = generateMixedCorpus(4096);
const mixed_10000 = generateMixedCorpus(10_000);
const mixed_20000 = generateMixedCorpus(20_000);

const parity_cases = [_]Case{
    .{ .name = "LTR-16", .cps = &ltr_16 },
    .{ .name = "LTR-64", .cps = &ltr_64 },
    .{ .name = "LTR-256", .cps = &ltr_256 },
    .{ .name = "LTR-1024", .cps = &ltr_1024 },
    .{ .name = "RTL-16", .cps = &rtl_16 },
    .{ .name = "RTL-64", .cps = &rtl_64 },
    .{ .name = "RTL-256", .cps = &rtl_256 },
    .{ .name = "RTL-1024", .cps = &rtl_1024 },
    .{ .name = "MIXED-16", .cps = &mixed_16 },
    .{ .name = "MIXED-64", .cps = &mixed_64 },
    .{ .name = "MIXED-256", .cps = &mixed_256 },
    .{ .name = "MIXED-1024", .cps = &mixed_1024 },
};

const bench_cases = [_]Case{
    .{ .name = "LTR-16", .cps = &ltr_16 },
    .{ .name = "LTR-64", .cps = &ltr_64 },
    .{ .name = "LTR-256", .cps = &ltr_256 },
    .{ .name = "LTR-1024", .cps = &ltr_1024 },
    .{ .name = "LTR-2048", .cps = &ltr_2048 },
    .{ .name = "LTR-4096", .cps = &ltr_4096 },
    .{ .name = "LTR-10000", .cps = &ltr_10000 },
    .{ .name = "LTR-20000", .cps = &ltr_20000 },

    .{ .name = "RTL-16", .cps = &rtl_16 },
    .{ .name = "RTL-64", .cps = &rtl_64 },
    .{ .name = "RTL-256", .cps = &rtl_256 },
    .{ .name = "RTL-1024", .cps = &rtl_1024 },
    .{ .name = "RTL-2048", .cps = &rtl_2048 },
    .{ .name = "RTL-4096", .cps = &rtl_4096 },
    .{ .name = "RTL-10000", .cps = &rtl_10000 },
    .{ .name = "RTL-20000", .cps = &rtl_20000 },

    .{ .name = "MIXED-16", .cps = &mixed_16 },
    .{ .name = "MIXED-64", .cps = &mixed_64 },
    .{ .name = "MIXED-256", .cps = &mixed_256 },
    .{ .name = "MIXED-1024", .cps = &mixed_1024 },
    .{ .name = "MIXED-2048", .cps = &mixed_2048 },
    .{ .name = "MIXED-4096", .cps = &mixed_4096 },
    .{ .name = "MIXED-10000", .cps = &mixed_10000 },
    .{ .name = "MIXED-20000", .cps = &mixed_20000 },
};

fn encodeUtf16(allocator: Allocator, cps: []const u21) ![]u16 {
    var out = std.ArrayListUnmanaged(u16){};
    errdefer out.deinit(allocator);

    for (cps) |cp| {
        if (cp <= 0xFFFF) {
            try out.append(allocator, @intCast(cp));
        } else {
            const x = cp - 0x10000;
            try out.append(allocator, @intCast(0xD800 + (x >> 10)));
            try out.append(allocator, @intCast(0xDC00 + (x & 0x3FF)));
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn iterationsForLen(len: usize) usize {
    if (len <= 16) return 60_000;
    if (len <= 64) return 40_000;
    if (len <= 256) return 12_000;
    if (len <= 1024) return 3_000;
    if (len <= 2048) return 1_500;
    if (len <= 4096) return 800;
    if (len <= 10_000) return 250;
    if (len <= 20_000) return 120;
    return 60;
}

fn warmupForLen(len: usize) usize {
    if (len <= 64) return 100;
    if (len <= 256) return 60;
    if (len <= 1024) return 30;
    if (len <= 4096) return 15;
    if (len <= 10_000) return 8;
    if (len <= 20_000) return 5;
    return 3;
}

fn lookupVersioned(lib: *std.DynLib, comptime T: type, base: []const u8, major: u8) ?T {
    var symbol_buf: [64]u8 = undefined;
    const symbol = std.fmt.bufPrintZ(&symbol_buf, "{s}_{d}", .{ base, major }) catch return null;
    return lib.lookup(T, symbol);
}

fn detectIcuMajor(lib: *std.DynLib) ?u8 {
    var major: usize = 50;
    while (major < 100) : (major += 1) {
        if (lookupVersioned(lib, *const fn (c_int, c_int, *UErrorCode) callconv(.c) ?*UBiDi, "ubidi_openSized", @intCast(major)) != null) {
            return @intCast(major);
        }
    }
    return null;
}

fn loadIcuApi() !IcuApi {
    const candidates = [_][]const u8{
        "/opt/homebrew/opt/icu4c/lib/libicuuc.dylib",
        "libicuuc.dylib",
        "libicuuc.so",
        "libicuuc.so.78",
        "libicuuc.so.77",
        "libicuuc.so.76",
        "icuuc.dll",
    };

    for (candidates) |candidate| {
        var lib = std.DynLib.open(candidate) catch continue;
        errdefer lib.close();

        const major = detectIcuMajor(&lib) orelse continue;

        const openSized = lookupVersioned(&lib, *const fn (c_int, c_int, *UErrorCode) callconv(.c) ?*UBiDi, "ubidi_openSized", major) orelse continue;
        const close = lookupVersioned(&lib, *const fn (*UBiDi) callconv(.c) void, "ubidi_close", major) orelse continue;
        const setPara = lookupVersioned(&lib, *const fn (*UBiDi, [*]const UChar, c_int, UBiDiLevel, ?[*]UBiDiLevel, *UErrorCode) callconv(.c) void, "ubidi_setPara", major) orelse continue;
        const getLevels = lookupVersioned(&lib, *const fn (*UBiDi, *UErrorCode) callconv(.c) [*]const UBiDiLevel, "ubidi_getLevels", major) orelse continue;
        const getVisualMap = lookupVersioned(&lib, *const fn (*UBiDi, [*]c_int, *UErrorCode) callconv(.c) void, "ubidi_getVisualMap", major) orelse continue;

        return .{
            .lib = lib,
            .major = major,
            .openSized = openSized,
            .close = close,
            .setPara = setPara,
            .getLevels = getLevels,
            .getVisualMap = getVisualMap,
        };
    }

    return error.IcuLibraryNotFound;
}

fn runItijah(allocator: Allocator, op: Op, cps: []const u21) !void {
    var dir: itijah.ParDirection = .auto_ltr;
    var emb = try itijah.getParEmbeddingLevels(allocator, cps, &dir);
    defer emb.deinit();

    if (op == .reorder_line) {
        const visual = try itijah.reorderVisualOnly(allocator, cps, emb.levels, dir.toLevel());
        allocator.free(visual);
    }
}

fn runItijahScratch(
    allocator: Allocator,
    ctx: *ItijahScratchContext,
    op: Op,
    cps: []const u21,
) !void {
    var dir: itijah.ParDirection = .auto_ltr;
    var emb = try itijah.getParEmbeddingLevelsScratch(allocator, &ctx.embedding, cps, &dir);
    defer emb.deinit();

    if (op == .reorder_line) {
        const visual = try itijah.reorderVisualOnlyScratch(allocator, &ctx.reorder, cps, emb.levels, dir.toLevel());
        allocator.free(visual);
    }
}

fn runFribidi(op: Op, cps: []const u21) !void {
    if (cps.len > max_bench_case_len) return error.InputTooLong;

    const len: c.FriBidiStrIndex = @intCast(cps.len);
    var chars: [max_bench_case_len]c.FriBidiChar = undefined;
    var types: [max_bench_case_len]c.FriBidiCharType = undefined;
    var brackets: [max_bench_case_len]c.FriBidiBracketType = undefined;
    var levels: [max_bench_case_len]c.FriBidiLevel = undefined;
    var visual: [max_bench_case_len]c.FriBidiChar = undefined;
    var map: [max_bench_case_len]c.FriBidiStrIndex = undefined;

    for (cps, 0..) |cp, i| {
        chars[i] = @intCast(cp);
        map[i] = @intCast(i);
    }

    c.fribidi_get_bidi_types(&chars, len, &types);
    c.fribidi_get_bracket_types(&chars, len, &types, &brackets);

    var par_dir: c.FriBidiParType = c.FRIBIDI_PAR_ON;
    const max_level = c.fribidi_get_par_embedding_levels_ex(&types, &brackets, len, &par_dir, &levels);
    if (max_level == 0) return error.FribidiFailed;

    if (op == .reorder_line) {
        for (cps, 0..) |cp, i| visual[i] = @intCast(cp);
        const reordered_level = c.fribidi_reorder_line(
            c.FRIBIDI_FLAGS_DEFAULT,
            &types,
            len,
            0,
            par_dir,
            &levels,
            &visual,
            &map,
        );
        if (reordered_level == 0) return error.FribidiFailed;
    }
}

fn runIcu(icu: *const IcuApi, op: Op, utf16: []const u16) !void {
    if (utf16.len > max_bench_case_len) return error.InputTooLong;

    var status: UErrorCode = U_ZERO_ERROR;
    const bidi = icu.openSized(@intCast(utf16.len), 0, &status) orelse return error.IcuFailed;
    defer icu.close(bidi);
    if (status != U_ZERO_ERROR) return error.IcuFailed;

    status = U_ZERO_ERROR;
    icu.setPara(bidi, utf16.ptr, @intCast(utf16.len), UBIDI_DEFAULT_LTR, null, &status);
    if (status != U_ZERO_ERROR) return error.IcuFailed;

    status = U_ZERO_ERROR;
    _ = icu.getLevels(bidi, &status);
    if (status != U_ZERO_ERROR) return error.IcuFailed;

    if (op == .reorder_line) {
        var map: [max_bench_case_len]c_int = undefined;
        status = U_ZERO_ERROR;
        icu.getVisualMap(bidi, &map, &status);
        if (status != U_ZERO_ERROR) return error.IcuFailed;
    }
}

fn computeFribidi(cps: []const u21) !FribidiResult {
    if (cps.len > 1024) return error.InputTooLong;

    const len: c.FriBidiStrIndex = @intCast(cps.len);
    var chars: [1024]c.FriBidiChar = undefined;
    var types: [1024]c.FriBidiCharType = undefined;
    var brackets: [1024]c.FriBidiBracketType = undefined;
    var levels: [1024]c.FriBidiLevel = undefined;
    var levels_before_reorder: [1024]c.FriBidiLevel = undefined;
    var visual: [1024]c.FriBidiChar = undefined;
    var map: [1024]c.FriBidiStrIndex = undefined;
    var v_to_l: [1024]u32 = undefined;

    for (cps, 0..) |cp, i| {
        chars[i] = @intCast(cp);
        visual[i] = @intCast(cp);
        map[i] = @intCast(i);
        v_to_l[i] = @intCast(i);
    }

    c.fribidi_get_bidi_types(&chars, len, &types);
    c.fribidi_get_bracket_types(&chars, len, &types, &brackets);

    var par_dir: c.FriBidiParType = c.FRIBIDI_PAR_ON;
    const max_level = c.fribidi_get_par_embedding_levels_ex(&types, &brackets, len, &par_dir, &levels);
    if (max_level == 0) return error.FribidiFailed;
    @memcpy(levels_before_reorder[0..cps.len], levels[0..cps.len]);

    var reorder_levels: [1024]c.FriBidiLevel = undefined;
    @memcpy(reorder_levels[0..cps.len], levels_before_reorder[0..cps.len]);

    const reordered_level = c.fribidi_reorder_line(
        c.FRIBIDI_FLAGS_DEFAULT,
        &types,
        len,
        0,
        par_dir,
        &reorder_levels,
        &visual,
        &map,
    );
    if (reordered_level == 0) return error.FribidiFailed;

    for (0..cps.len) |i| {
        v_to_l[i] = @intCast(map[i]);
    }

    return .{
        .len = cps.len,
        .levels = levels_before_reorder,
        .v_to_l = v_to_l,
    };
}

fn fribidiParityCase(allocator: Allocator, case: Case) !?Mismatch {
    const fri = try computeFribidi(case.cps);

    var dir: itijah.ParDirection = .auto_ltr;
    var emb = try itijah.getParEmbeddingLevels(allocator, case.cps, &dir);
    defer emb.deinit();

    if (emb.levels.len != fri.len) return .{
        .kind = .levels,
        .index = 0,
        .expected = @intCast(fri.len),
        .actual = @intCast(emb.levels.len),
    };
    for (emb.levels, 0..) |lvl, i| {
        const expected: u32 = @intCast(fri.levels[i]);
        const actual: u32 = lvl;
        if (actual != expected) {
            return .{
                .kind = .levels,
                .index = i,
                .expected = expected,
                .actual = actual,
            };
        }
    }

    var vis = try itijah.reorderLine(allocator, case.cps, emb.levels, dir.toLevel());
    defer vis.deinit();
    if (vis.v_to_l.len != fri.len) return .{
        .kind = .v_to_l,
        .index = 0,
        .expected = @intCast(fri.len),
        .actual = @intCast(vis.v_to_l.len),
    };
    for (vis.v_to_l, 0..) |idx, i| {
        const expected = fri.v_to_l[i];
        const actual = idx;
        if (actual != expected) {
            return .{
                .kind = .v_to_l,
                .index = i,
                .expected = expected,
                .actual = actual,
            };
        }
    }

    return null;
}

fn parityOnlyMode() bool {
    const flag = std.process.getEnvVarOwned(std.heap.page_allocator, "ITIJAH_COMPARE_ONLY_PARITY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return false,
        else => return false,
    };
    defer std.heap.page_allocator.free(flag);
    return std.mem.eql(u8, flag, "1") or std.ascii.eqlIgnoreCase(flag, "true");
}

fn itijahScratchMode() bool {
    const flag = std.process.getEnvVarOwned(std.heap.page_allocator, "ITIJAH_COMPARE_ITIJAH_REUSE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return false,
        else => return false,
    };
    defer std.heap.page_allocator.free(flag);
    return std.mem.eql(u8, flag, "1") or std.ascii.eqlIgnoreCase(flag, "true");
}

fn printCaseCps(writer: *std.Io.Writer, cps: []const u21) !void {
    for (cps, 0..) |cp, i| {
        try writer.print("{X:0>4}", .{cp});
        if (i + 1 != cps.len) try writer.writeAll(" ");
    }
    try writer.writeAll("\n");
}

fn printLevelMismatchContext(
    writer: *std.Io.Writer,
    allocator: Allocator,
    case: Case,
    mismatch_idx: usize,
) !void {
    const fri = try computeFribidi(case.cps);

    var dir: itijah.ParDirection = .auto_ltr;
    var emb = try itijah.getParEmbeddingLevels(allocator, case.cps, &dir);
    defer emb.deinit();

    const start = mismatch_idx -| 8;
    const end = @min(mismatch_idx + 9, case.cps.len);
    try writer.writeAll("    level-context (idx cp expected actual):\n");
    for (start..end) |i| {
        try writer.print(
            "      {d:>4} U+{X:0>4} {d:>3} {d:>3}\n",
            .{ i, case.cps[i], @as(u32, @intCast(fri.levels[i])), @as(u32, emb.levels[i]) },
        );
    }
}

fn measureOne(impl: Impl, op: Op, cps: []const u21, utf16: []const u16, icu: *const IcuApi) !Metrics {
    switch (impl) {
        .itijah => {
            var m = MeasuringAllocator.init(std.heap.c_allocator);
            const alloc = m.allocator();

            var timer = try std.time.Timer.start();
            try runItijah(alloc, op, cps);
            return .{
                .ns = timer.read(),
                .alloc_count = m.allocation_count,
                .allocated_bytes = m.allocated_bytes,
                .peak_bytes = m.peak_bytes,
            };
        },
        .fribidi, .icu => {
            if (itijah_fribidi_probe_available() == 0) return error.MemoryProbeUnavailable;

            var alloc_count: u64 = 0;
            var allocated_bytes: u64 = 0;
            var peak_bytes: u64 = 0;

            itijah_fribidi_probe_begin();
            errdefer itijah_fribidi_probe_finish(&alloc_count, &allocated_bytes, &peak_bytes);

            var timer = try std.time.Timer.start();
            switch (impl) {
                .fribidi => try runFribidi(op, cps),
                .icu => try runIcu(icu, op, utf16),
                .itijah => unreachable,
            }
            const ns = timer.read();
            itijah_fribidi_probe_finish(&alloc_count, &allocated_bytes, &peak_bytes);

            return .{
                .ns = ns,
                .alloc_count = @intCast(alloc_count),
                .allocated_bytes = @intCast(allocated_bytes),
                .peak_bytes = @intCast(peak_bytes),
            };
        },
    }
}

fn benchItijahScratch(writer: *std.Io.Writer, case: Case, op: Op) !void {
    const warmup = warmupForLen(case.cps.len);
    var m = MeasuringAllocator.init(std.heap.c_allocator);
    const alloc = m.allocator();
    var scratch_ctx = ItijahScratchContext{};
    defer scratch_ctx.deinit(alloc);

    for (0..warmup) |_| {
        try runItijahScratch(alloc, &scratch_ctx, op, case.cps);
    }

    const iterations = iterationsForLen(case.cps.len);
    var agg = Aggregate{};
    for (0..iterations) |_| {
        const iter_state = m.beginIteration();
        var timer = try std.time.Timer.start();
        try runItijahScratch(alloc, &scratch_ctx, op, case.cps);
        agg.add(m.endIteration(iter_state, timer.read()));
    }

    const mean_ns = agg.meanNs();
    const ns_per_cp = mean_ns / @as(f64, @floatFromInt(case.cps.len));
    try writer.print(
        "{s:<10} {s:<12} {s:<8} {d:>8} {d:>10.2} {d:>10.2} {d:>12.2} {d:>12.2} {d:>12.2}\n",
        .{
            case.name,
            @tagName(op),
            @tagName(Impl.itijah),
            iterations,
            mean_ns,
            ns_per_cp,
            agg.meanAllocCount(),
            agg.meanAllocatedBytes(),
            agg.meanPeakBytes(),
        },
    );
}

fn bench(
    writer: *std.Io.Writer,
    case: Case,
    impl: Impl,
    op: Op,
    utf16: []const u16,
    icu: *const IcuApi,
    itijah_reuse: bool,
) !void {
    if (impl == .itijah and itijah_reuse) {
        return benchItijahScratch(writer, case, op);
    }

    const warmup = warmupForLen(case.cps.len);
    for (0..warmup) |_| {
        _ = try measureOne(impl, op, case.cps, utf16, icu);
    }

    const iterations = iterationsForLen(case.cps.len);
    var agg = Aggregate{};
    for (0..iterations) |_| {
        const m = try measureOne(impl, op, case.cps, utf16, icu);
        agg.add(m);
    }

    const mean_ns = agg.meanNs();
    const ns_per_cp = mean_ns / @as(f64, @floatFromInt(case.cps.len));

    try writer.print(
        "{s:<10} {s:<12} {s:<8} {d:>8} {d:>10.2} {d:>10.2} {d:>12.2} {d:>12.2} {d:>12.2}\n",
        .{
            case.name,
            @tagName(op),
            @tagName(impl),
            iterations,
            mean_ns,
            ns_per_cp,
            agg.meanAllocCount(),
            agg.meanAllocatedBytes(),
            agg.meanPeakBytes(),
        },
    );
}

pub fn main() !void {
    if (itijah_fribidi_probe_available() == 0) {
        return error.MemoryProbeUnavailable;
    }

    var icu = try loadIcuApi();
    defer icu.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var buf: [16384]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&buf);
    const writer = &stdout.interface;

    try writer.writeAll("comparison benchmark (itijah vs fribidi vs icu)\n");
    try writer.writeAll("feature parity check vs fribidi (exact levels + visual map):\n");
    var parity_ok: usize = 0;
    for (parity_cases) |case| {
        const mismatch = try fribidiParityCase(alloc, case);
        if (mismatch) |m| {
            try writer.print(
                "  {s:<10} FAIL kind={s} idx={d} expected={d} actual={d}\n",
                .{ case.name, @tagName(m.kind), m.index, m.expected, m.actual },
            );
            if (m.kind == .levels) {
                try printLevelMismatchContext(writer, alloc, case, m.index);
            }
            try writer.writeAll("    cps: ");
            try printCaseCps(writer, case.cps);
        } else {
            parity_ok += 1;
            try writer.print("  {s:<10} PASS\n", .{case.name});
        }
    }
    try writer.print("  summary: {d}/{d} PASS\n", .{ parity_ok, parity_cases.len });

    if (parityOnlyMode()) {
        try writer.flush();
        return;
    }

    const itijah_reuse = itijahScratchMode();
    if (itijah_reuse) {
        try writer.writeAll("mode: itijah scratch reuse enabled (ITIJAH_COMPARE_ITIJAH_REUSE=1)\n");
    }

    try writer.writeAll("columns: case op impl iterations mean_ns ns_per_cp alloc_count allocated_bytes peak_bytes\n");
    try writer.writeAll("-----------------------------------------------------------------------------------------------\n");

    for (bench_cases) |case| {
        const utf16 = try encodeUtf16(alloc, case.cps);
        try bench(writer, case, .itijah, .analysis, utf16, &icu, itijah_reuse);
        try bench(writer, case, .fribidi, .analysis, utf16, &icu, itijah_reuse);
        try bench(writer, case, .icu, .analysis, utf16, &icu, itijah_reuse);

        try bench(writer, case, .itijah, .reorder_line, utf16, &icu, itijah_reuse);
        try bench(writer, case, .fribidi, .reorder_line, utf16, &icu, itijah_reuse);
        try bench(writer, case, .icu, .reorder_line, utf16, &icu, itijah_reuse);
    }

    try writer.flush();
}
