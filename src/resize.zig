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

pub fn resizeBicubic(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
) !ImageU8 {
    return resizeWithKernel(allocator, src, target_width, target_height, 2.0, bicubicKernel);
}

pub fn resizeLanczos3(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
) !ImageU8 {
    return resizeWithKernel(allocator, src, target_width, target_height, 3.0, lanczos3Kernel);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn resizeWithKernel(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
    support: f32,
    kernel: *const fn (f32) f32,
) !ImageU8 {
    try validateResizeInputs(src, target_width, target_height);

    var dst = try ImageU8.init(allocator, target_width, target_height, src.channels);
    errdefer dst.deinit();

    const radius: isize = @intFromFloat(@ceil(support));

    for (0..target_height) |dy| {
        const src_y = sourceCenter(dy, src.height, target_height);
        const y_center: isize = @intFromFloat(@floor(src_y));
        const y_start = y_center - radius + 1;
        const y_end = y_center + radius;

        for (0..target_width) |dx| {
            const src_x = sourceCenter(dx, src.width, target_width);
            const x_center: isize = @intFromFloat(@floor(src_x));
            const x_start = x_center - radius + 1;
            const x_end = x_center + radius;
            const dst_offset = (dy * target_width + dx) * dst.channels;

            for (0..src.channels) |channel| {
                var weighted_sum: f32 = 0.0;
                var weight_sum: f32 = 0.0;

                var sy_i = y_start;
                while (sy_i <= y_end) : (sy_i += 1) {
                    const sy = clampIndex(sy_i, src.height);
                    const wy = kernel(src_y - @as(f32, @floatFromInt(sy)));
                    if (wy == 0.0) continue;

                    var sx_i = x_start;
                    while (sx_i <= x_end) : (sx_i += 1) {
                        const sx = clampIndex(sx_i, src.width);
                        const wx = kernel(src_x - @as(f32, @floatFromInt(sx)));
                        const weight = wx * wy;
                        if (weight == 0.0) continue;

                        weighted_sum += @as(f32, @floatFromInt(src.get(sx, sy, channel))) * weight;
                        weight_sum += weight;
                    }
                }

                if (weight_sum == 0.0) {
                    const fallback_x = nearestSourceIndex(dx, src.width, target_width);
                    const fallback_y = nearestSourceIndex(dy, src.height, target_height);
                    dst.data[dst_offset + channel] = src.get(fallback_x, fallback_y, channel);
                } else {
                    dst.data[dst_offset + channel] = clampToU8(weighted_sum / weight_sum);
                }
            }
        }
    }

    return dst;
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

fn sourceCenter(dst_index: usize, src_extent: usize, dst_extent: usize) f32 {
    return ((@as(f32, @floatFromInt(dst_index)) + 0.5) * @as(f32, @floatFromInt(src_extent)) / @as(f32, @floatFromInt(dst_extent))) - 0.5;
}

fn overlapLength(a0: f32, a1: f32, b0: f32, b1: f32) f32 {
    const start = @max(a0, b0);
    const end = @min(a1, b1);
    return @max(@as(f32, 0.0), end - start);
}

fn bicubicKernel(x: f32) f32 {
    const a: f32 = -0.5;
    const abs_x = @abs(x);
    if (abs_x < 1.0) {
        return ((a + 2.0) * abs_x - (a + 3.0)) * abs_x * abs_x + 1.0;
    }
    if (abs_x < 2.0) {
        return (((a * abs_x - 5.0 * a) * abs_x + 8.0 * a) * abs_x) - 4.0 * a;
    }
    return 0.0;
}

fn lanczos3Kernel(x: f32) f32 {
    const abs_x = @abs(x);
    if (abs_x >= 3.0) return 0.0;
    return sinc(abs_x) * sinc(abs_x / 3.0);
}

fn sinc(x: f32) f32 {
    if (x == 0.0) return 1.0;
    const pix = std.math.pi * @as(f64, @floatCast(x));
    return @floatCast(std.math.sin(pix) / pix);
}

fn clampToU8(value: f32) u8 {
    if (value <= 0.0) return 0;
    if (value >= 255.0) return 255;
    return @intFromFloat(@round(value));
}

fn clampIndex(value: isize, upper: usize) usize {
    if (value < 0) return 0;
    const upper_index: isize = @intCast(upper - 1);
    if (value > upper_index) return upper - 1;
    return @intCast(value);
}
