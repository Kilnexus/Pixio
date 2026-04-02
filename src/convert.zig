const std = @import("std");
const pixel = @import("pixel.zig");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;
pub const PixelFormat = pixel.PixelFormat;

pub fn toPixelFormat(allocator: std.mem.Allocator, src: *const ImageU8, dst_format: PixelFormat) !ImageU8 {
    const dst_channels = dst_format.channelCount();
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;

    const src_format = try pixel.descriptorForChannels(src.channels);
    if (src_format.pixel_format == dst_format) {
        var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
        errdefer dst.deinit();
        @memcpy(dst.data, src.data);
        return dst;
    }

    var dst = try ImageU8.init(allocator, src.width, src.height, dst_channels);
    errdefer dst.deinit();

    for (0..src.width * src.height) |i| {
        const src_index = i * src.channels;
        const rgba = expandToRgba(src.data[src_index .. src_index + src.channels]);
        const dst_index = i * dst_channels;
        writeFromRgba(dst.data[dst_index .. dst_index + dst_channels], dst_format, rgba);
    }

    return dst;
}

pub fn toGray8(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    return toPixelFormat(allocator, src, .gray8);
}

pub fn toRgb8(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    return toPixelFormat(allocator, src, .rgb8);
}

pub fn toRgba8(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    return toPixelFormat(allocator, src, .rgba8);
}

fn expandToRgba(pixel_bytes: []const u8) [4]u8 {
    return switch (pixel_bytes.len) {
        1 => .{ pixel_bytes[0], pixel_bytes[0], pixel_bytes[0], 0xff },
        3 => .{ pixel_bytes[0], pixel_bytes[1], pixel_bytes[2], 0xff },
        4 => .{ pixel_bytes[0], pixel_bytes[1], pixel_bytes[2], pixel_bytes[3] },
        else => unreachable,
    };
}

fn writeFromRgba(dst: []u8, dst_format: PixelFormat, rgba: [4]u8) void {
    switch (dst_format) {
        .gray8 => dst[0] = rgbToGray(rgba[0], rgba[1], rgba[2]),
        .rgb8 => {
            dst[0] = rgba[0];
            dst[1] = rgba[1];
            dst[2] = rgba[2];
        },
        .rgba8 => {
            dst[0] = rgba[0];
            dst[1] = rgba[1];
            dst[2] = rgba[2];
            dst[3] = rgba[3];
        },
    }
}

fn rgbToGray(r: u8, g: u8, b: u8) u8 {
    const weighted = @as(u32, 77) * r + @as(u32, 150) * g + @as(u32, 29) * b + 128;
    return @intCast(weighted >> 8);
}
