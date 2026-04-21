const types = @import("../../types.zig");

pub const ImageU8 = types.ImageU8;

pub const JpegError = types.ImageError || error{
    InvalidJpegHeader,
    InvalidJpegMarker,
    InvalidJpegSegment,
    InvalidJpegDimensions,
    InvalidJpegData,
    MissingJpegFrame,
    MissingJpegScan,
    UnsupportedJpegFrame,
    UnsupportedJpegPrecision,
    UnsupportedJpegComponents,
    UnsupportedJpegQuantization,
    UnsupportedJpegHuffmanTable,
    UnsupportedJpegScan,
    UnsupportedJpegSampling,
};

pub const zigzag = [64]u8{
    0,  1,  8,  16, 9,  2,  3,  10,
    17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
};

pub const QuantTable = struct {
    defined: bool = false,
    values: [64]u16 = [_]u16{0} ** 64,
};

pub const HuffmanTable = struct {
    defined: bool = false,
    counts: [16]u8 = [_]u8{0} ** 16,
    symbols: [256]u8 = [_]u8{0} ** 256,
    symbol_count: usize = 0,
    min_code: [17]i32 = [_]i32{-1} ** 17,
    max_code: [17]i32 = [_]i32{-1} ** 17,
    val_ptr: [17]usize = [_]usize{0} ** 17,

    pub fn build(self: *HuffmanTable) void {
        var code: i32 = 0;
        var next_index: usize = 0;
        for (1..17) |len| {
            self.val_ptr[len] = next_index;
            const count = self.counts[len - 1];
            if (count == 0) {
                self.min_code[len] = -1;
                self.max_code[len] = -1;
            } else {
                self.min_code[len] = code;
                self.max_code[len] = code + @as(i32, count) - 1;
                code += count;
                next_index += count;
            }
            code <<= 1;
        }
    }
};

pub const FrameComponent = struct {
    id: u8,
    h: u8,
    v: u8,
    quant_table: u8,
    dc_table: u8 = 0,
    ac_table: u8 = 0,
};

pub const Frame = struct {
    width: usize = 0,
    height: usize = 0,
    components: [3]FrameComponent = undefined,
    component_count: usize = 0,
    max_h: u8 = 0,
    max_v: u8 = 0,
    progressive: bool = false,
};

pub const ScanComponent = struct {
    id: u8,
    dc_table: u8,
    ac_table: u8,
};

pub const ComponentPlane = struct {
    samples: []u8,
    plane_width: usize,
    plane_height: usize,
    actual_width: usize,
    actual_height: usize,
    h: u8,
    v: u8,
    dc_pred: i32 = 0,
};
