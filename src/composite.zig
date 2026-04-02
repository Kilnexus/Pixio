const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;

pub fn premultiplyRgba8(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels != 4) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.width, src.height, 4);
    errdefer dst.deinit();

    for (0..src.width * src.height) |i| {
        const index = i * 4;
        const alpha = src.data[index + 3];
        dst.data[index] = mulAlpha(src.data[index], alpha);
        dst.data[index + 1] = mulAlpha(src.data[index + 1], alpha);
        dst.data[index + 2] = mulAlpha(src.data[index + 2], alpha);
        dst.data[index + 3] = alpha;
    }

    return dst;
}

pub fn unpremultiplyRgba8(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels != 4) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.width, src.height, 4);
    errdefer dst.deinit();

    for (0..src.width * src.height) |i| {
        const index = i * 4;
        const alpha = src.data[index + 3];
        if (alpha == 0) {
            dst.data[index] = 0;
            dst.data[index + 1] = 0;
            dst.data[index + 2] = 0;
            dst.data[index + 3] = 0;
            continue;
        }

        dst.data[index] = divAlpha(src.data[index], alpha);
        dst.data[index + 1] = divAlpha(src.data[index + 1], alpha);
        dst.data[index + 2] = divAlpha(src.data[index + 2], alpha);
        dst.data[index + 3] = alpha;
    }

    return dst;
}

pub fn compositeOver(allocator: std.mem.Allocator, foreground: *const ImageU8, background: *const ImageU8) !ImageU8 {
    if (foreground.width == 0 or foreground.height == 0) return error.InvalidImageDimensions;
    if (background.width == 0 or background.height == 0) return error.InvalidImageDimensions;
    if (foreground.width != background.width or foreground.height != background.height) return error.ShapeMismatch;
    if (foreground.channels != 4) return error.InvalidChannelCount;
    if (background.channels != 3 and background.channels != 4) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, foreground.width, foreground.height, background.channels);
    errdefer dst.deinit();

    const pixel_count = foreground.width * foreground.height;
    for (0..pixel_count) |i| {
        const fg = foreground.data[i * 4 .. i * 4 + 4];
        const bg = background.data[i * background.channels .. i * background.channels + background.channels];

        const fa = @as(u32, fg[3]);
        const inv_fa = @as(u32, 255) - fa;

        const out_r = compositeChannel(fg[0], fa, bg[0], inv_fa);
        const out_g = compositeChannel(fg[1], fa, bg[1], inv_fa);
        const out_b = compositeChannel(fg[2], fa, bg[2], inv_fa);

        const dst_index = i * dst.channels;
        dst.data[dst_index] = out_r;
        dst.data[dst_index + 1] = out_g;
        dst.data[dst_index + 2] = out_b;

        if (dst.channels == 4) {
            const bg_alpha = bg[3];
            dst.data[dst_index + 3] = compositeAlpha(fg[3], bg_alpha);
        }
    }

    return dst;
}

fn mulAlpha(value: u8, alpha: u8) u8 {
    return @intCast((@as(u32, value) * alpha + 127) / 255);
}

fn divAlpha(value: u8, alpha: u8) u8 {
    return @intCast(@min(@as(u32, 255), (@as(u32, value) * 255 + alpha / 2) / alpha));
}

fn compositeChannel(fg: u8, fa: u32, bg: u8, inv_fa: u32) u8 {
    return @intCast((@as(u32, fg) * fa + @as(u32, bg) * inv_fa + 127) / 255);
}

fn compositeAlpha(fg_alpha: u8, bg_alpha: u8) u8 {
    return @intCast(@min(@as(u32, 255), @as(u32, fg_alpha) + (@as(u32, bg_alpha) * (@as(u32, 255) - fg_alpha) + 127) / 255));
}
