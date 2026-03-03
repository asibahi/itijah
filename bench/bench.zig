const std = @import("std");
const itijah = @import("itijah");

const Allocator = std.mem.Allocator;

const Op = enum {
    embed,
    full,
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
    min_ns: u64 = std.math.maxInt(u64),
    max_ns: u64 = 0,
    total_alloc_count: u128 = 0,
    total_allocated_bytes: u128 = 0,
    total_peak_bytes: u128 = 0,

    fn add(self: *Aggregate, m: Metrics) void {
        self.iterations += 1;
        self.total_ns += m.ns;
        self.total_alloc_count += m.alloc_count;
        self.total_allocated_bytes += m.allocated_bytes;
        self.total_peak_bytes += m.peak_bytes;
        if (m.ns < self.min_ns) self.min_ns = m.ns;
        if (m.ns > self.max_ns) self.max_ns = m.ns;
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
};

fn generateLtrCorpus(comptime n: usize) [n]u21 {
    @setEvalBranchQuota(20_000);
    var buf: [n]u21 = undefined;
    for (0..n) |i| buf[i] = @intCast('A' + (i % 26));
    return buf;
}

fn generateRtlCorpus(comptime n: usize) [n]u21 {
    @setEvalBranchQuota(20_000);
    var buf: [n]u21 = undefined;
    for (0..n) |i| buf[i] = @intCast(0x05D0 + (i % 27));
    return buf;
}

fn generateMixedCorpus(comptime n: usize) [n]u21 {
    @setEvalBranchQuota(20_000);
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

fn runOperation(allocator: Allocator, op: Op, corpus: []const u21) !void {
    switch (op) {
        .embed => {
            var dir: itijah.ParDirection = .auto_ltr;
            var emb = try itijah.getParEmbeddingLevels(allocator, corpus, &dir);
            emb.deinit();
        },
        .full => {
            var dir: itijah.ParDirection = .auto_ltr;
            var emb = try itijah.getParEmbeddingLevels(allocator, corpus, &dir);
            defer emb.deinit();

            var vis = try itijah.reorderLine(allocator, corpus, emb.levels, dir.toLevel());
            vis.deinit();
        },
    }
}

fn measureOnce(op: Op, corpus: []const u21) !Metrics {
    var m = MeasuringAllocator.init(std.heap.c_allocator);
    const alloc = m.allocator();

    var timer = try std.time.Timer.start();
    try runOperation(alloc, op, corpus);
    const ns = timer.read();

    return .{
        .ns = ns,
        .alloc_count = m.allocation_count,
        .allocated_bytes = m.allocated_bytes,
        .peak_bytes = m.peak_bytes,
    };
}

fn iterationsForLen(len: usize) usize {
    if (len <= 16) return 120_000;
    if (len <= 64) return 100_000;
    if (len <= 256) return 40_000;
    return 15_000;
}

fn warmupForLen(len: usize) usize {
    if (len <= 64) return 200;
    if (len <= 256) return 100;
    return 50;
}

fn benchCase(writer: *std.Io.Writer, name: []const u8, op: Op, corpus: []const u21) !void {
    const warmup = warmupForLen(corpus.len);
    for (0..warmup) |_| {
        _ = try measureOnce(op, corpus);
    }

    const iterations = iterationsForLen(corpus.len);
    var agg = Aggregate{};
    for (0..iterations) |_| {
        const m = try measureOnce(op, corpus);
        agg.add(m);
    }

    const mean_ns = agg.meanNs();
    const ns_per_cp = mean_ns / @as(f64, @floatFromInt(corpus.len));

    try writer.print(
        "{s:<18} {s:<6} {d:>8} {d:>10.3} {d:>10.2} {d:>12.2} {d:>12.2} {d:>12.2}\n",
        .{
            name,
            @tagName(op),
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
    var buf: [8192]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&buf);
    const writer = &stdout.interface;

    try writer.writeAll("itijah benchmark report\n");
    try writer.writeAll("columns: case op iterations mean_ns ns_per_cp alloc_count allocated_bytes peak_bytes\n");
    try writer.writeAll("---------------------------------------------------------------------------------------------\n");

    try benchCase(writer, "LTR-16", .embed, &ltr_16);
    try benchCase(writer, "LTR-64", .embed, &ltr_64);
    try benchCase(writer, "LTR-256", .embed, &ltr_256);
    try benchCase(writer, "LTR-1024", .embed, &ltr_1024);
    try benchCase(writer, "RTL-16", .embed, &rtl_16);
    try benchCase(writer, "RTL-64", .embed, &rtl_64);
    try benchCase(writer, "RTL-256", .embed, &rtl_256);
    try benchCase(writer, "RTL-1024", .embed, &rtl_1024);
    try benchCase(writer, "MIXED-16", .embed, &mixed_16);
    try benchCase(writer, "MIXED-64", .embed, &mixed_64);
    try benchCase(writer, "MIXED-256", .embed, &mixed_256);
    try benchCase(writer, "MIXED-1024", .embed, &mixed_1024);

    try benchCase(writer, "LTR-64", .full, &ltr_64);
    try benchCase(writer, "RTL-64", .full, &rtl_64);
    try benchCase(writer, "MIXED-64", .full, &mixed_64);
    try benchCase(writer, "MIXED-256", .full, &mixed_256);
    try benchCase(writer, "MIXED-1024", .full, &mixed_1024);

    try writer.flush();
}
