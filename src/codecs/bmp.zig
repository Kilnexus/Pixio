const std = @import("std");
const types = @import("../types.zig");

pub const ImageU8 = types.ImageU8;

pub const BmpError = types.ImageError || error{
    InvalidBmpHeader,
    UnsupportedBmpCompression,
    UnsupportedBmpBitDepth,
    UnsupportedBmpDibHeader,
    InvalidBmpDimensions,
    InvalidBmpData,
};

pub fn decodeRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    if (bytes.len < 54 or bytes[0] != 'B' or bytes[1] != 'M') return error.InvalidBmpHeader;

    const pixel_offset = readU32le(bytes[10..14]);
    const dib_size = readU32le(bytes[14..18]);
    if (dib_size < 40) return error.UnsupportedBmpDibHeader;

    const width_i = readI32le(bytes[18..22]);
    const height_i = readI32le(bytes[22..26]);
    const planes = readU16le(bytes[26..28]);
    const bit_count = readU16le(bytes[28..30]);
    const compression = readU32le(bytes[30..34]);
    const colors_used = readU32le(bytes[46..50]);
    if (planes != 1) return error.InvalidBmpHeader;
    if (compression != 0) return error.UnsupportedBmpCompression;
    if (bit_count != 8 and bit_count != 24 and bit_count != 32) return error.UnsupportedBmpBitDepth;

    const width = @abs(width_i);
    const height = @abs(height_i);
    if (width == 0 or height == 0) return error.InvalidBmpDimensions;

    const bottom_up = height_i > 0;
    const src_channels: usize = switch (bit_count) {
        8 => 1,
        24 => 3,
        32 => 4,
        else => unreachable,
    };
    const palette_entries = if (bit_count == 8)
        if (colors_used == 0) @as(usize, 256) else colors_used
    else
        @as(usize, 0);
    const palette_offset = 14 + dib_size;
    const palette_end = palette_offset + palette_entries * 4;
    if (palette_end > bytes.len or pixel_offset < palette_end) return error.InvalidBmpData;

    const row_stride = ((@as(usize, @intCast(bit_count)) * @as(usize, @intCast(width)) + 31) / 32) * 4;
    if (pixel_offset + row_stride * @as(usize, @intCast(height)) > bytes.len) return error.InvalidBmpData;

    var image = try ImageU8.init(allocator, @intCast(width), @intCast(height), 3);
    errdefer image.deinit();

    for (0..image.height) |y| {
        const src_y = if (bottom_up) image.height - 1 - y else y;
        const row = bytes[pixel_offset + src_y * row_stride .. pixel_offset + (src_y + 1) * row_stride];
        for (0..image.width) |x| {
            const dst_index = image.pixelIndex(x, y, 0);
            if (bit_count == 8) {
                const palette_index = @as(usize, row[x]) * 4;
                if (palette_index + 3 >= palette_end - palette_offset) return error.InvalidBmpData;
                const entry = bytes[palette_offset + palette_index .. palette_offset + palette_index + 4];
                image.data[dst_index] = entry[2];
                image.data[dst_index + 1] = entry[1];
                image.data[dst_index + 2] = entry[0];
            } else {
                const src_index = x * src_channels;
                image.data[dst_index] = row[src_index + 2];
                image.data[dst_index + 1] = row[src_index + 1];
                image.data[dst_index + 2] = row[src_index];
            }
        }
    }

    return image;
}

fn readU16le(bytes: []const u8) u16 {
    return std.mem.readInt(u16, bytes[0..2], .little);
}

fn readU32le(bytes: []const u8) usize {
    return @intCast(std.mem.readInt(u32, bytes[0..4], .little));
}

fn readI32le(bytes: []const u8) i32 {
    return std.mem.readInt(i32, bytes[0..4], .little);
}
