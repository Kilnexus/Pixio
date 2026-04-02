const std = @import("std");
const types = @import("../types.zig");

pub const ImageU8 = types.ImageU8;

pub const PngError = types.ImageError || error{
    InvalidPngSignature,
    InvalidPngChunk,
    InvalidPngPalette,
    UnsupportedPngBitDepth,
    UnsupportedPngColorType,
    UnsupportedPngInterlace,
    MissingPngIhdr,
    MissingPngIdat,
    MissingPngIend,
    MissingPngPalette,
    InvalidPngCrc,
    InvalidPngFilter,
    InvalidPngDimensions,
    InvalidPngData,
};

const PngSignature = "\x89PNG\r\n\x1a\n";

pub fn decodeRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeWithChannels(allocator, bytes, 3);
}

pub fn decodeRgba8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeWithChannels(allocator, bytes, 4);
}

fn decodeWithChannels(allocator: std.mem.Allocator, bytes: []const u8, output_channels: usize) !ImageU8 {
    if (output_channels != 3 and output_channels != 4) return error.InvalidChannelCount;
    if (bytes.len < PngSignature.len or !std.mem.eql(u8, bytes[0..PngSignature.len], PngSignature)) {
        return error.InvalidPngSignature;
    }

    var width: usize = 0;
    var height: usize = 0;
    var bit_depth: u8 = 0;
    var color_type: u8 = 0;
    var compression_method: u8 = 0;
    var filter_method: u8 = 0;
    var interlace_method: u8 = 0;
    var seen_ihdr = false;
    var seen_iend = false;
    var palette: ?[]const u8 = null;
    var transparency: ?[]const u8 = null;

    var idat = std.ArrayListUnmanaged(u8).empty;
    defer if (idat.items.len > 0) idat.deinit(allocator);

    var offset: usize = PngSignature.len;
    while (offset + 12 <= bytes.len) {
        const chunk_len = readU32be(bytes[offset..][0..4]);
        offset += 4;
        const chunk_type = bytes[offset..][0..4];
        offset += 4;
        if (offset + chunk_len + 4 > bytes.len) return error.InvalidPngChunk;
        const chunk_data = bytes[offset .. offset + chunk_len];
        offset += chunk_len;
        const chunk_crc = readU32be(bytes[offset..][0..4]);
        offset += 4;

        var crc = std.hash.Crc32.init();
        crc.update(chunk_type);
        crc.update(chunk_data);
        if (crc.final() != chunk_crc) return error.InvalidPngCrc;

        if (std.mem.eql(u8, chunk_type, "IHDR")) {
            if (chunk_data.len != 13) return error.InvalidPngChunk;
            width = readU32be(chunk_data[0..4]);
            height = readU32be(chunk_data[4..8]);
            if (width == 0 or height == 0) return error.InvalidPngDimensions;
            bit_depth = chunk_data[8];
            color_type = chunk_data[9];
            compression_method = chunk_data[10];
            filter_method = chunk_data[11];
            interlace_method = chunk_data[12];
            seen_ihdr = true;
        } else if (std.mem.eql(u8, chunk_type, "PLTE")) {
            if (chunk_data.len == 0 or chunk_data.len % 3 != 0 or chunk_data.len > 256 * 3) {
                return error.InvalidPngPalette;
            }
            palette = chunk_data;
        } else if (std.mem.eql(u8, chunk_type, "tRNS")) {
            transparency = chunk_data;
        } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
            try idat.appendSlice(allocator, chunk_data);
        } else if (std.mem.eql(u8, chunk_type, "IEND")) {
            seen_iend = true;
            break;
        }
    }

    if (!seen_ihdr) return error.MissingPngIhdr;
    if (idat.items.len == 0) return error.MissingPngIdat;
    if (!seen_iend) return error.MissingPngIend;
    if (compression_method != 0 or filter_method != 0) return error.InvalidPngData;
    if (interlace_method > 1) return error.UnsupportedPngInterlace;

    const layout = switch (color_type) {
        0 => switch (bit_depth) {
            1, 2, 4 => PngLayout{ .src_channels = 1, .raw_stride = 1, .bytes_per_pixel = 1, .packed_samples = true },
            8 => PngLayout{ .src_channels = 1, .raw_stride = 1, .bytes_per_pixel = 1, .packed_samples = false },
            else => return error.UnsupportedPngBitDepth,
        },
        3 => switch (bit_depth) {
            1, 2, 4 => PngLayout{ .src_channels = 1, .raw_stride = 1, .bytes_per_pixel = 1, .packed_samples = true },
            8 => PngLayout{ .src_channels = 1, .raw_stride = 1, .bytes_per_pixel = 1, .packed_samples = false },
            else => return error.UnsupportedPngBitDepth,
        },
        2 => switch (bit_depth) {
            8 => PngLayout{ .src_channels = 3, .raw_stride = 3, .bytes_per_pixel = 3, .packed_samples = false },
            else => return error.UnsupportedPngBitDepth,
        },
        4 => switch (bit_depth) {
            8 => PngLayout{ .src_channels = 2, .raw_stride = 2, .bytes_per_pixel = 2, .packed_samples = false },
            else => return error.UnsupportedPngBitDepth,
        },
        6 => switch (bit_depth) {
            8 => PngLayout{ .src_channels = 4, .raw_stride = 4, .bytes_per_pixel = 4, .packed_samples = false },
            else => return error.UnsupportedPngBitDepth,
        },
        else => return error.UnsupportedPngColorType,
    };
    const scanline_len = pngScanlineLen(width, bit_depth, layout.src_channels, layout.packed_samples);
    if (color_type == 3 and palette == null) return error.MissingPngPalette;
    const expected_unfiltered_len = if (interlace_method == 0)
        height * (1 + scanline_len)
    else
        adam7InflatedLen(width, height, bit_depth, layout.src_channels, layout.packed_samples);

    var in_reader: std.Io.Reader = .fixed(idat.items);
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    var decompress: std.compress.flate.Decompress = .init(&in_reader, .zlib, &.{});
    _ = try decompress.reader.streamRemaining(&out.writer);
    const inflated = out.written();
    if (inflated.len != expected_unfiltered_len) return error.InvalidPngData;

    var raw = try allocator.alloc(u8, height * width * layout.raw_stride);
    defer allocator.free(raw);

    if (interlace_method == 0 and !layout.packed_samples) {
        unfilter(raw, inflated, height, scanline_len, layout.bytes_per_pixel) catch return error.InvalidPngFilter;
    } else if (interlace_method == 0) {
        const packed_rows = try allocator.alloc(u8, height * scanline_len);
        defer allocator.free(packed_rows);
        unfilter(packed_rows, inflated, height, scanline_len, layout.bytes_per_pixel) catch return error.InvalidPngFilter;
        unpackPackedSamples(raw, packed_rows, width, height, bit_depth, color_type);
    } else if (!layout.packed_samples) {
        unfilterAdam7(allocator, raw, inflated, width, height, bit_depth, layout.src_channels, layout.bytes_per_pixel) catch |err| switch (err) {
            error.InvalidPngFilter => return error.InvalidPngFilter,
            else => return error.InvalidPngData,
        };
    } else {
        unpackAdam7PackedSamples(allocator, raw, inflated, width, height, bit_depth, color_type) catch |err| switch (err) {
            error.InvalidPngFilter => return error.InvalidPngFilter,
            else => return error.InvalidPngData,
        };
    }

    var image = try ImageU8.init(allocator, width, height, output_channels);
    errdefer image.deinit();

    for (0..height) |y| {
        for (0..width) |x| {
            const src_index = (y * width + x) * layout.raw_stride;
            const dst_index = image.pixelIndex(x, y, 0);
            switch (color_type) {
                0 => {
                    const g = raw[src_index];
                    image.data[dst_index] = g;
                    image.data[dst_index + 1] = g;
                    image.data[dst_index + 2] = g;
                    if (output_channels == 4) {
                        image.data[dst_index + 3] = grayscaleAlpha(g, transparency, bit_depth);
                    }
                },
                3 => {
                    const palette_entry = raw[src_index];
                    const palette_index = @as(usize, palette_entry) * 3;
                    if (palette_index + 2 >= palette.?.len) return error.InvalidPngPalette;
                    @memcpy(image.data[dst_index .. dst_index + 3], palette.?[palette_index .. palette_index + 3]);
                    if (output_channels == 4) {
                        image.data[dst_index + 3] = paletteAlpha(palette_entry, transparency);
                    }
                },
                2 => {
                    @memcpy(image.data[dst_index .. dst_index + 3], raw[src_index .. src_index + 3]);
                    if (output_channels == 4) {
                        image.data[dst_index + 3] = rgbAlpha(raw[src_index .. src_index + 3], transparency);
                    }
                },
                4 => {
                    const g = raw[src_index];
                    image.data[dst_index] = g;
                    image.data[dst_index + 1] = g;
                    image.data[dst_index + 2] = g;
                    if (output_channels == 4) {
                        image.data[dst_index + 3] = raw[src_index + 1];
                    }
                },
                6 => {
                    @memcpy(image.data[dst_index .. dst_index + 3], raw[src_index .. src_index + 3]);
                    if (output_channels == 4) {
                        image.data[dst_index + 3] = raw[src_index + 3];
                    }
                },
                else => unreachable,
            }
        }
    }
    return image;
}

fn grayscaleAlpha(value: u8, transparency: ?[]const u8, bit_depth: u8) u8 {
    if (transparency == null or transparency.?.len != 2) return 0xff;
    const transparent_value = readU16be(transparency.?[0..2]);
    const scaled_value = if (bit_depth == 8)
        @as(u8, @intCast(transparent_value >> 8))
    else
        scaleSample(@intCast(transparent_value), bit_depth);
    return if (value == scaled_value) 0 else 0xff;
}

fn rgbAlpha(rgb: []const u8, transparency: ?[]const u8) u8 {
    if (transparency == null or transparency.?.len != 6) return 0xff;
    const red = @as(u8, @intCast(readU16be(transparency.?[0..2]) >> 8));
    const green = @as(u8, @intCast(readU16be(transparency.?[2..4]) >> 8));
    const blue = @as(u8, @intCast(readU16be(transparency.?[4..6]) >> 8));
    return if (rgb[0] == red and rgb[1] == green and rgb[2] == blue) 0 else 0xff;
}

fn paletteAlpha(index: u8, transparency: ?[]const u8) u8 {
    if (transparency == null) return 0xff;
    if (@as(usize, index) >= transparency.?.len) return 0xff;
    return transparency.?[@intCast(index)];
}

fn scaleSample(sample: u8, bit_depth: u8) u8 {
    if (bit_depth == 8) return sample;
    const mask: u16 = (@as(u16, 1) << @intCast(bit_depth)) - 1;
    return @intCast((@as(u16, sample) * 255) / mask);
}

fn unfilter(
    dst: []u8,
    inflated: []const u8,
    height: usize,
    scanline_len: usize,
    bytes_per_pixel: usize,
) !void {
    var src_offset: usize = 0;
    for (0..height) |row| {
        const filter_type = inflated[src_offset];
        src_offset += 1;
        const filtered = inflated[src_offset .. src_offset + scanline_len];
        src_offset += scanline_len;
        const out_row = dst[row * scanline_len .. (row + 1) * scanline_len];
        const prev_row = if (row == 0) null else dst[(row - 1) * scanline_len .. row * scanline_len];

        switch (filter_type) {
            0 => @memcpy(out_row, filtered),
            1 => for (out_row, filtered, 0..) |*d, f, i| {
                const left: u8 = if (i >= bytes_per_pixel) out_row[i - bytes_per_pixel] else 0;
                d.* = f +% left;
            },
            2 => for (out_row, filtered, 0..) |*d, f, i| {
                const up: u8 = if (prev_row) |p| p[i] else 0;
                d.* = f +% up;
            },
            3 => for (out_row, filtered, 0..) |*d, f, i| {
                const left: u8 = if (i >= bytes_per_pixel) out_row[i - bytes_per_pixel] else 0;
                const up: u8 = if (prev_row) |p| p[i] else 0;
                d.* = f +% @as(u8, @intCast((@as(u16, left) + @as(u16, up)) / 2));
            },
            4 => for (out_row, filtered, 0..) |*d, f, i| {
                const left: u8 = if (i >= bytes_per_pixel) out_row[i - bytes_per_pixel] else 0;
                const up: u8 = if (prev_row) |p| p[i] else 0;
                const up_left: u8 = if (prev_row != null and i >= bytes_per_pixel) prev_row.?[i - bytes_per_pixel] else 0;
                d.* = f +% paeth(left, up, up_left);
            },
            else => return error.InvalidPngFilter,
        }
    }
}

fn unfilterAdam7(
    allocator: std.mem.Allocator,
    dst: []u8,
    inflated: []const u8,
    width: usize,
    height: usize,
    bit_depth: u8,
    src_channels: usize,
    bytes_per_pixel: usize,
) !void {
    @memset(dst, 0);

    var src_offset: usize = 0;
    for (adam7_passes) |pass| {
        const pass_width = adam7PassExtent(width, pass.start_x, pass.step_x);
        const pass_height = adam7PassExtent(height, pass.start_y, pass.step_y);
        if (pass_width == 0 or pass_height == 0) continue;

        const scanline_len = pngScanlineLen(pass_width, bit_depth, src_channels, false);
        const pass_inflated_len = pass_height * (1 + scanline_len);
        if (src_offset + pass_inflated_len > inflated.len) return error.InvalidPngData;

        const pass_inflated = inflated[src_offset .. src_offset + pass_inflated_len];
        src_offset += pass_inflated_len;

        const pass_raw = try allocator.alloc(u8, pass_height * scanline_len);
        defer allocator.free(pass_raw);
        try unfilter(pass_raw, pass_inflated, pass_height, scanline_len, bytes_per_pixel);

        for (0..pass_height) |pass_y| {
            const dst_y = pass.start_y + pass_y * pass.step_y;
            for (0..pass_width) |pass_x| {
                const dst_x = pass.start_x + pass_x * pass.step_x;
                const src_index = (pass_y * pass_width + pass_x) * src_channels;
                const dst_index = (dst_y * width + dst_x) * src_channels;
                @memcpy(dst[dst_index .. dst_index + src_channels], pass_raw[src_index .. src_index + src_channels]);
            }
        }
    }

    if (src_offset != inflated.len) return error.InvalidPngData;
}

fn unpackAdam7PackedSamples(
    allocator: std.mem.Allocator,
    dst: []u8,
    inflated: []const u8,
    width: usize,
    height: usize,
    bit_depth: u8,
    color_type: u8,
) !void {
    @memset(dst, 0);

    var src_offset: usize = 0;
    for (adam7_passes) |pass| {
        const pass_width = adam7PassExtent(width, pass.start_x, pass.step_x);
        const pass_height = adam7PassExtent(height, pass.start_y, pass.step_y);
        if (pass_width == 0 or pass_height == 0) continue;

        const scanline_len = pngScanlineLen(pass_width, bit_depth, 1, true);
        const pass_inflated_len = pass_height * (1 + scanline_len);
        if (src_offset + pass_inflated_len > inflated.len) return error.InvalidPngData;

        const pass_inflated = inflated[src_offset .. src_offset + pass_inflated_len];
        src_offset += pass_inflated_len;

        const pass_raw = try allocator.alloc(u8, pass_height * scanline_len);
        defer allocator.free(pass_raw);
        try unfilter(pass_raw, pass_inflated, pass_height, scanline_len, 1);

        for (0..pass_height) |pass_y| {
            const row = pass_raw[pass_y * scanline_len .. (pass_y + 1) * scanline_len];
            const dst_y = pass.start_y + pass_y * pass.step_y;
            for (0..pass_width) |pass_x| {
                const dst_x = pass.start_x + pass_x * pass.step_x;
                dst[dst_y * width + dst_x] = decodePackedSample(row, pass_x, bit_depth, color_type == 0);
            }
        }
    }

    if (src_offset != inflated.len) return error.InvalidPngData;
}

fn adam7InflatedLen(width: usize, height: usize, bit_depth: u8, src_channels: usize, packed_samples: bool) usize {
    var total: usize = 0;
    for (adam7_passes) |pass| {
        const pass_width = adam7PassExtent(width, pass.start_x, pass.step_x);
        const pass_height = adam7PassExtent(height, pass.start_y, pass.step_y);
        if (pass_width == 0 or pass_height == 0) continue;
        total += pass_height * (1 + pngScanlineLen(pass_width, bit_depth, src_channels, packed_samples));
    }
    return total;
}

fn unpackPackedSamples(
    dst: []u8,
    packed_rows: []const u8,
    width: usize,
    height: usize,
    bit_depth: u8,
    color_type: u8,
) void {
    const scanline_len = pngScanlineLen(width, bit_depth, 1, true);
    for (0..height) |y| {
        const row = packed_rows[y * scanline_len .. (y + 1) * scanline_len];
        for (0..width) |x| {
            dst[y * width + x] = decodePackedSample(row, x, bit_depth, color_type == 0);
        }
    }
}

fn decodePackedSample(row: []const u8, x: usize, bit_depth: u8, scale_grayscale: bool) u8 {
    const samples_per_byte = 8 / bit_depth;
    const byte = row[x / samples_per_byte];
    const shift = @as(u3, @intCast((samples_per_byte - 1 - (x % samples_per_byte)) * bit_depth));
    const mask: u8 = (@as(u8, 1) << @intCast(bit_depth)) - 1;
    const sample = (byte >> shift) & mask;
    if (!scale_grayscale or bit_depth == 8) return sample;
    return scaleSample(sample, bit_depth);
}

fn pngScanlineLen(width: usize, bit_depth: u8, src_channels: usize, packed_samples: bool) usize {
    if (!packed_samples) return width * src_channels;
    return std.math.divCeil(usize, width * bit_depth, 8) catch unreachable;
}

const PngLayout = struct {
    src_channels: usize,
    raw_stride: usize,
    bytes_per_pixel: usize,
    packed_samples: bool,
};

fn adam7PassExtent(full: usize, start: usize, step: usize) usize {
    if (full <= start) return 0;
    return 1 + (full - 1 - start) / step;
}

const Adam7Pass = struct {
    start_x: usize,
    start_y: usize,
    step_x: usize,
    step_y: usize,
};

const adam7_passes = [_]Adam7Pass{
    .{ .start_x = 0, .start_y = 0, .step_x = 8, .step_y = 8 },
    .{ .start_x = 4, .start_y = 0, .step_x = 8, .step_y = 8 },
    .{ .start_x = 0, .start_y = 4, .step_x = 4, .step_y = 8 },
    .{ .start_x = 2, .start_y = 0, .step_x = 4, .step_y = 4 },
    .{ .start_x = 0, .start_y = 2, .step_x = 2, .step_y = 4 },
    .{ .start_x = 1, .start_y = 0, .step_x = 2, .step_y = 2 },
    .{ .start_x = 0, .start_y = 1, .step_x = 1, .step_y = 2 },
};

fn paeth(a: u8, b: u8, c: u8) u8 {
    const p = @as(i32, a) + @as(i32, b) - @as(i32, c);
    const pa = @abs(p - @as(i32, a));
    const pb = @abs(p - @as(i32, b));
    const pc = @abs(p - @as(i32, c));
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

fn readU32be(bytes: []const u8) usize {
    return @intCast(std.mem.readInt(u32, bytes[0..4], .big));
}

fn readU16be(bytes: []const u8) u16 {
    return std.mem.readInt(u16, bytes[0..2], .big);
}
