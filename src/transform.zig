const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;

pub fn pad(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    pad_left: usize,
    pad_top: usize,
    pad_right: usize,
    pad_bottom: usize,
    pad_value: u8,
) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;

    const dst_width = src.width + pad_left + pad_right;
    const dst_height = src.height + pad_top + pad_bottom;
    if (dst_width == 0 or dst_height == 0) return error.InvalidImageDimensions;

    var dst = try ImageU8.init(allocator, dst_width, dst_height, src.channels);
    errdefer dst.deinit();
    dst.fill(pad_value);

    for (0..src.height) |y| {
        const src_offset = y * src.width * src.channels;
        const dst_offset = ((pad_top + y) * dst_width + pad_left) * src.channels;
        const row_len = src.width * src.channels;
        @memcpy(dst.data[dst_offset .. dst_offset + row_len], src.data[src_offset .. src_offset + row_len]);
    }

    return dst;
}

pub fn flipHorizontal(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            const src_x = src.width - 1 - x;
            const src_offset = (y * src.width + src_x) * src.channels;
            const dst_offset = (y * dst.width + x) * dst.channels;
            @memcpy(dst.data[dst_offset .. dst_offset + src.channels], src.data[src_offset .. src_offset + src.channels]);
        }
    }

    return dst;
}

pub fn flipVertical(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    for (0..src.height) |y| {
        const src_y = src.height - 1 - y;
        const src_offset = src_y * src.width * src.channels;
        const dst_offset = y * dst.width * dst.channels;
        const row_len = src.width * src.channels;
        @memcpy(dst.data[dst_offset .. dst_offset + row_len], src.data[src_offset .. src_offset + row_len]);
    }

    return dst;
}

pub fn rotate90Cw(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    return rotate90(allocator, src, true);
}

pub fn rotate90Ccw(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    return rotate90(allocator, src, false);
}

pub fn rotate180(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            const dst_x = src.width - 1 - x;
            const dst_y = src.height - 1 - y;
            const src_offset = (y * src.width + x) * src.channels;
            const dst_offset = (dst_y * dst.width + dst_x) * dst.channels;
            @memcpy(dst.data[dst_offset .. dst_offset + src.channels], src.data[src_offset .. src_offset + src.channels]);
        }
    }

    return dst;
}

pub fn transpose(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    return diagonalTransform(allocator, src, false);
}

pub fn transverse(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    return diagonalTransform(allocator, src, true);
}

pub fn applyExifOrientation(allocator: std.mem.Allocator, src: *const ImageU8, orientation: u8) !ImageU8 {
    return switch (orientation) {
        1 => cloneImage(allocator, src),
        2 => flipHorizontal(allocator, src),
        3 => rotate180(allocator, src),
        4 => flipVertical(allocator, src),
        5 => transpose(allocator, src),
        6 => rotate90Cw(allocator, src),
        7 => transverse(allocator, src),
        8 => rotate90Ccw(allocator, src),
        else => cloneImage(allocator, src),
    };
}

fn rotate90(allocator: std.mem.Allocator, src: *const ImageU8, clockwise: bool) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.height, src.width, src.channels);
    errdefer dst.deinit();

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            const dst_x = if (clockwise) src.height - 1 - y else y;
            const dst_y = if (clockwise) x else src.width - 1 - x;
            const src_offset = (y * src.width + x) * src.channels;
            const dst_offset = (dst_y * dst.width + dst_x) * dst.channels;
            @memcpy(dst.data[dst_offset .. dst_offset + src.channels], src.data[src_offset .. src_offset + src.channels]);
        }
    }

    return dst;
}

fn diagonalTransform(allocator: std.mem.Allocator, src: *const ImageU8, anti_diagonal: bool) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.height, src.width, src.channels);
    errdefer dst.deinit();

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            const dst_x = if (anti_diagonal) src.height - 1 - y else y;
            const dst_y = if (anti_diagonal) src.width - 1 - x else x;
            const src_offset = (y * src.width + x) * src.channels;
            const dst_offset = (dst_y * dst.width + dst_x) * dst.channels;
            @memcpy(dst.data[dst_offset .. dst_offset + src.channels], src.data[src_offset .. src_offset + src.channels]);
        }
    }

    return dst;
}

fn cloneImage(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();
    @memcpy(dst.data, src.data);
    return dst;
}
