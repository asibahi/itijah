const level = @import("level.zig");

pub const BidiLevel = level.BidiLevel;

pub const ParDirection = enum {
    ltr,
    rtl,
    auto_ltr,
    auto_rtl,

    pub fn toLevel(self: ParDirection) BidiLevel {
        return switch (self) {
            .ltr, .auto_ltr => level.ltr_level,
            .rtl, .auto_rtl => level.rtl_level,
        };
    }

    pub fn isAuto(self: ParDirection) bool {
        return self == .auto_ltr or self == .auto_rtl;
    }
};

pub const ReorderFlags = packed struct {
    reorder_nsm: bool = false, // L3 (Phase 2)
    _padding: u31 = 0,
};

pub const ShapeFlags = packed struct {
    mirror: bool = false, // L4
    arab_pres: bool = false,
    arab_liga: bool = false,
    arab_console: bool = false,
    _padding: u28 = 0,
};

pub const EmbeddingResult = struct {
    levels: []BidiLevel,
    resolved_par_dir: ParDirection,
    allocator: @import("std").mem.Allocator,

    pub fn deinit(self: *EmbeddingResult) void {
        self.allocator.free(self.levels);
        self.* = undefined;
    }
};

pub const ReorderResult = struct {
    visual: []u21,
    l_to_v: []u32,
    v_to_l: []u32,
    max_level: BidiLevel,
    allocator: @import("std").mem.Allocator,

    pub fn deinit(self: *ReorderResult) void {
        self.allocator.free(self.visual);
        self.allocator.free(self.l_to_v);
        self.allocator.free(self.v_to_l);
        self.* = undefined;
    }
};

pub const RemoveBidiMarksResult = struct {
    result: []u21,
    new_len: u32,
};
