const std = @import("std");

pub const HuffmanCode = struct {
    code: u16 = 0,
    len: u8 = 0,
    valid: bool = false,
};

pub const HuffmanSpec = struct {
    counts: [16]u8,
    symbols: []const u8,
};

pub const QuantTables = struct {
    luma: [64]u8,
    chroma: [64]u8,
};

pub const dc_spec = HuffmanSpec{
    .counts = .{ 0, 0, 0, 16 } ++ ([_]u8{0} ** 12),
    .symbols = &dc_symbols,
};

pub const ac_spec = HuffmanSpec{
    .counts = .{ 0, 0, 0, 0, 0, 0, 32, 128, 82 } ++ ([_]u8{0} ** 7),
    .symbols = &ac_symbols,
};

const base_luma_quant = [64]u8{
    16, 11, 10, 16, 24, 40, 51, 61,
    12, 12, 14, 19, 26, 58, 60, 55,
    14, 13, 16, 24, 40, 57, 69, 56,
    14, 17, 22, 29, 51, 87, 80, 62,
    18, 22, 37, 56, 68, 109, 103, 77,
    24, 35, 55, 64, 81, 104, 113, 92,
    49, 64, 78, 87, 103, 121, 120, 101,
    72, 92, 95, 98, 112, 100, 103, 99,
};

const base_chroma_quant = [64]u8{
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
};

const dc_symbols = buildDcSymbols();
const ac_symbols = buildAcSymbols();

pub fn buildScaledQuantTables(quality: u8) !QuantTables {
    if (quality == 0 or quality > 100) return error.InvalidJpegQuality;

    const scale = if (quality < 50)
        @divFloor(@as(usize, 5000), quality)
    else
        200 - @as(usize, quality) * 2;

    return .{
        .luma = scaleQuantTable(base_luma_quant, scale),
        .chroma = scaleQuantTable(base_chroma_quant, scale),
    };
}

pub fn buildCanonicalCodes(spec: HuffmanSpec) [256]HuffmanCode {
    var codes = [_]HuffmanCode{.{}} ** 256;
    var code: u16 = 0;
    var symbol_index: usize = 0;

    for (spec.counts, 1..) |count, len| {
        for (0..count) |_| {
            const symbol = spec.symbols[symbol_index];
            codes[symbol] = .{
                .code = code,
                .len = @intCast(len),
                .valid = true,
            };
            code += 1;
            symbol_index += 1;
        }
        code <<= 1;
    }

    return codes;
}

fn scaleQuantTable(base: [64]u8, scale: usize) [64]u8 {
    var scaled: [64]u8 = undefined;
    for (base, 0..) |value, i| {
        const quant = @max(@as(usize, 1), @min(@as(usize, 255), @divFloor(@as(usize, value) * scale + 50, 100)));
        scaled[i] = @intCast(quant);
    }
    return scaled;
}

fn buildDcSymbols() [16]u8 {
    var symbols: [16]u8 = undefined;
    for (0..symbols.len) |i| symbols[i] = @intCast(i);
    return symbols;
}

fn buildAcSymbols() [242]u8 {
    var symbols: [242]u8 = undefined;
    var index: usize = 0;

    symbols[index] = 0x00;
    index += 1;

    for (0..16) |run| {
        for (1..16) |size| {
            symbols[index] = (@as(u8, @intCast(run)) << 4) | @as(u8, @intCast(size));
            index += 1;
        }
    }

    symbols[index] = 0xF0;
    index += 1;
    std.debug.assert(index == symbols.len);
    return symbols;
}
