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

const BmpHeader = struct {
    pixel_offset: usize,
    width: usize,
    height: usize,
    bottom_up: bool,
    bit_count: u16,
    src_channels: usize,
    palette_offset: usize,
    palette_entries: usize,
    row_stride: usize,
};

pub fn decodeRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeBytesWithChannels(allocator, bytes, 3);
}

pub fn decodeRgba8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeBytesWithChannels(allocator, bytes, 4);
}

pub fn decodeFileRgb8(allocator: std.mem.Allocator, file: std.fs.File) !ImageU8 {
    return decodeFileWithChannels(allocator, file, 3);
}

pub fn decodeFileRgba8(allocator: std.mem.Allocator, file: std.fs.File) !ImageU8 {
    return decodeFileWithChannels(allocator, file, 4);
}

fn decodeBytesWithChannels(allocator: std.mem.Allocator, bytes: []const u8, output_channels: usize) !ImageU8 {
    if (output_channels != 3 and output_channels != 4) return error.InvalidChannelCount;

    const header = try parseHeader(bytes);
    const palette_end = header.palette_offset + header.palette_entries * 4;
    if (palette_end > bytes.len or header.pixel_offset < palette_end) return error.InvalidBmpData;
    if (header.pixel_offset + header.row_stride * header.height > bytes.len) return error.InvalidBmpData;

    const palette = if (header.palette_entries == 0) null else bytes[header.palette_offset..palette_end];
    var image = try ImageU8.init(allocator, header.width, header.height, output_channels);
    errdefer image.deinit();

    for (0..image.height) |y| {
        const src_y = if (header.bottom_up) image.height - 1 - y else y;
        const row_start = header.pixel_offset + src_y * header.row_stride;
        const row = bytes[row_start .. row_start + header.row_stride];
        try decodeRow(&image, row, palette, header, y);
    }

    return image;
}

fn decodeFileWithChannels(allocator: std.mem.Allocator, file: std.fs.File, output_channels: usize) !ImageU8 {
    if (output_channels != 3 and output_channels != 4) return error.InvalidChannelCount;

    var header_bytes: [54]u8 = undefined;
    if (try file.preadAll(&header_bytes, 0) < header_bytes.len) return error.InvalidBmpHeader;
    const header = try parseHeader(&header_bytes);

    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) return error.InvalidBmpData;
    const file_size: usize = @intCast(stat.size);

    const palette_end = header.palette_offset + header.palette_entries * 4;
    if (palette_end > file_size or header.pixel_offset < palette_end) return error.InvalidBmpData;
    if (header.pixel_offset + header.row_stride * header.height > file_size) return error.InvalidBmpData;

    const palette = if (header.palette_entries == 0)
        null
    else blk: {
        const table = try allocator.alloc(u8, header.palette_entries * 4);
        errdefer allocator.free(table);
        if (try file.preadAll(table, header.palette_offset) < table.len) return error.InvalidBmpData;
        break :blk table;
    };
    defer if (palette) |table| allocator.free(table);

    const row = try allocator.alloc(u8, header.row_stride);
    defer allocator.free(row);

    var image = try ImageU8.init(allocator, header.width, header.height, output_channels);
    errdefer image.deinit();

    for (0..image.height) |y| {
        const src_y = if (header.bottom_up) image.height - 1 - y else y;
        const row_offset = header.pixel_offset + src_y * header.row_stride;
        if (try file.preadAll(row, row_offset) < row.len) return error.InvalidBmpData;
        try decodeRow(&image, row, palette, header, y);
    }

    return image;
}

fn decodeRow(
    image: *ImageU8,
    row: []const u8,
    palette: ?[]const u8,
    header: BmpHeader,
    dst_y: usize,
) !void {
    for (0..image.width) |x| {
        const dst_index = image.pixelIndex(x, dst_y, 0);
        if (header.bit_count == 8) {
            const palette_index = @as(usize, row[x]) * 4;
            if (palette == null or palette_index + 3 >= palette.?.len) return error.InvalidBmpData;
            const entry = palette.?[palette_index .. palette_index + 4];
            image.data[dst_index] = entry[2];
            image.data[dst_index + 1] = entry[1];
            image.data[dst_index + 2] = entry[0];
            if (image.channels == 4) image.data[dst_index + 3] = 0xff;
            continue;
        }

        const src_index = x * header.src_channels;
        image.data[dst_index] = row[src_index + 2];
        image.data[dst_index + 1] = row[src_index + 1];
        image.data[dst_index + 2] = row[src_index];
        if (image.channels == 4) {
            image.data[dst_index + 3] = if (header.bit_count == 32) row[src_index + 3] else 0xff;
        }
    }
}

fn parseHeader(bytes: []const u8) !BmpHeader {
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

    return .{
        .pixel_offset = pixel_offset,
        .width = @intCast(width),
        .height = @intCast(height),
        .bottom_up = height_i > 0,
        .bit_count = bit_count,
        .src_channels = switch (bit_count) {
            8 => 1,
            24 => 3,
            32 => 4,
            else => unreachable,
        },
        .palette_offset = 14 + dib_size,
        .palette_entries = if (bit_count == 8)
            if (colors_used == 0) 256 else colors_used
        else
            0,
        .row_stride = ((@as(usize, bit_count) * @as(usize, @intCast(width)) + 31) / 32) * 4,
    };
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
