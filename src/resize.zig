const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;
pub const ImageError = types.ImageError;

pub fn resizeNearest(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
) !ImageU8 {
    try validateResizeInputs(src, target_width, target_height);

    var dst = try ImageU8.init(allocator, target_width, target_height, src.channels);
    errdefer dst.deinit();

    for (0..target_height) |dy| {
        const src_y = nearestSourceIndex(dy, src.height, target_height);
        for (0..target_width) |dx| {
            const src_x = nearestSourceIndex(dx, src.width, target_width);
            const src_offset = (src_y * src.width + src_x) * src.channels;
            const dst_offset = (dy * target_width + dx) * dst.channels;
            @memcpy(dst.data[dst_offset .. dst_offset + src.channels], src.data[src_offset .. src_offset + src.channels]);
        }
    }

    return dst;
}

pub fn resizeBilinear(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
) !ImageU8 {
    try validateResizeInputs(src, target_width, target_height);

    var dst = try ImageU8.init(allocator, target_width, target_height, src.channels);
    errdefer dst.deinit();

    for (0..target_height) |dy| {
        const src_y = ((@as(f32, @floatFromInt(dy)) + 0.5) * @as(f32, @floatFromInt(src.height)) / @as(f32, @floatFromInt(target_height))) - 0.5;
        const y0 = clampIndex(@as(isize, @intFromFloat(@floor(src_y))), src.height);
        const y1 = if (y0 + 1 < src.height) y0 + 1 else src.height - 1;
        const wy = src_y - @as(f32, @floatFromInt(y0));

        for (0..target_width) |dx| {
            const src_x = ((@as(f32, @floatFromInt(dx)) + 0.5) * @as(f32, @floatFromInt(src.width)) / @as(f32, @floatFromInt(target_width))) - 0.5;
            const x0 = clampIndex(@as(isize, @intFromFloat(@floor(src_x))), src.width);
            const x1 = if (x0 + 1 < src.width) x0 + 1 else src.width - 1;
            const wx = src_x - @as(f32, @floatFromInt(x0));

            for (0..src.channels) |channel| {
                const p00 = @as(f32, @floatFromInt(src.get(x0, y0, channel)));
                const p10 = @as(f32, @floatFromInt(src.get(x1, y0, channel)));
                const p01 = @as(f32, @floatFromInt(src.get(x0, y1, channel)));
                const p11 = @as(f32, @floatFromInt(src.get(x1, y1, channel)));

                const top = lerp(p00, p10, wx);
                const bottom = lerp(p01, p11, wx);
                const value = lerp(top, bottom, wy);
                dst.set(dx, dy, channel, @intFromFloat(@round(value)));
            }
        }
    }

    return dst;
}

pub fn resizeArea(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
) !ImageU8 {
    try validateResizeInputs(src, target_width, target_height);

    var dst = try ImageU8.init(allocator, target_width, target_height, src.channels);
    errdefer dst.deinit();

    const scale_x = @as(f32, @floatFromInt(src.width)) / @as(f32, @floatFromInt(target_width));
    const scale_y = @as(f32, @floatFromInt(src.height)) / @as(f32, @floatFromInt(target_height));

    for (0..target_height) |dy| {
        const src_y0 = @as(f32, @floatFromInt(dy)) * scale_y;
        const src_y1 = @as(f32, @floatFromInt(dy + 1)) * scale_y;
        const y_start = @max(@as(usize, @intFromFloat(@floor(src_y0))), @as(usize, 0));
        const y_end = @min(src.height, @as(usize, @intFromFloat(@ceil(src_y1))));

        for (0..target_width) |dx| {
            const src_x0 = @as(f32, @floatFromInt(dx)) * scale_x;
            const src_x1 = @as(f32, @floatFromInt(dx + 1)) * scale_x;
            const x_start = @max(@as(usize, @intFromFloat(@floor(src_x0))), @as(usize, 0));
            const x_end = @min(src.width, @as(usize, @intFromFloat(@ceil(src_x1))));
            const dst_offset = (dy * target_width + dx) * dst.channels;
            const area = (src_x1 - src_x0) * (src_y1 - src_y0);

            for (0..src.channels) |channel| {
                var sum: f32 = 0.0;
                for (y_start..y_end) |sy| {
                    const y_overlap = overlapLength(src_y0, src_y1, @floatFromInt(sy), @floatFromInt(sy + 1));
                    if (y_overlap <= 0.0) continue;

                    for (x_start..x_end) |sx| {
                        const x_overlap = overlapLength(src_x0, src_x1, @floatFromInt(sx), @floatFromInt(sx + 1));
                        if (x_overlap <= 0.0) continue;

                        const weight = x_overlap * y_overlap;
                        sum += @as(f32, @floatFromInt(src.get(sx, sy, channel))) * weight;
                    }
                }

                dst.data[dst_offset + channel] = @intFromFloat(@round(sum / area));
            }
        }
    }

    return dst;
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn validateResizeInputs(src: *const ImageU8, target_width: usize, target_height: usize) !void {
    if (src.width == 0 or src.height == 0 or target_width == 0 or target_height == 0) {
        return error.InvalidImageDimensions;
    }
    if (src.channels == 0) return error.InvalidChannelCount;
}

fn nearestSourceIndex(dst_index: usize, src_extent: usize, dst_extent: usize) usize {
    return @min(src_extent - 1, (dst_index * 2 + 1) * src_extent / (dst_extent * 2));
}

fn overlapLength(a0: f32, a1: f32, b0: f32, b1: f32) f32 {
    const start = @max(a0, b0);
    const end = @min(a1, b1);
    return @max(@as(f32, 0.0), end - start);
}

fn clampIndex(value: isize, upper: usize) usize {
    if (value < 0) return 0;
    const upper_index: isize = @intCast(upper - 1);
    if (value > upper_index) return upper - 1;
    return @intCast(value);
}
