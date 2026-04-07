const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;
pub const ImageError = types.ImageError;

pub const ResizeKernel = enum {
    nearest,
    bilinear,
    area,
    bicubic,
    lanczos3,
};

pub fn resizeWithKernel(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
    kernel: ResizeKernel,
) !ImageU8 {
    return switch (kernel) {
        .nearest => resizeNearest(allocator, src, target_width, target_height),
        .bilinear => resizeBilinear(allocator, src, target_width, target_height),
        .area => resizeArea(allocator, src, target_width, target_height),
        .bicubic => resizeBicubic(allocator, src, target_width, target_height),
        .lanczos3 => resizeLanczos3(allocator, src, target_width, target_height),
    };
}

pub fn resizeNearest(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
) !ImageU8 {
    try validateResizeInputs(src, target_width, target_height);
    if (src.width == target_width and src.height == target_height) return cloneImage(allocator, src);

    var dst = try ImageU8.init(allocator, target_width, target_height, src.channels);
    errdefer dst.deinit();
    const x_map = try buildNearestMap(allocator, src.width, target_width);
    defer allocator.free(x_map);
    const src_stride = src.width * src.channels;
    const dst_stride = dst.width * dst.channels;

    for (0..target_height) |dy| {
        const src_y = nearestSourceIndex(dy, src.height, target_height);
        const src_row = src.data[src_y * src_stride ..][0..src_stride];
        const dst_row = dst.data[dy * dst_stride ..][0..dst_stride];
        for (0..target_width) |dx| {
            copyPixel(
                dst_row[dx * dst.channels ..][0..dst.channels],
                src_row[x_map[dx] * src.channels ..][0..src.channels],
            );
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
    if (src.width == target_width and src.height == target_height) return cloneImage(allocator, src);

    var dst = try ImageU8.init(allocator, target_width, target_height, src.channels);
    errdefer dst.deinit();
    const x_samples = try buildLinearAxisSamples(allocator, src.width, target_width);
    defer allocator.free(x_samples);
    const y_samples = try buildLinearAxisSamples(allocator, src.height, target_height);
    defer allocator.free(y_samples);
    const src_stride = src.width * src.channels;
    const dst_stride = dst.width * dst.channels;

    for (0..target_height) |dy| {
        const y_sample = y_samples[dy];
        const row0 = src.data[y_sample.left * src_stride ..][0..src_stride];
        const row1 = src.data[y_sample.right * src_stride ..][0..src_stride];
        const dst_row = dst.data[dy * dst_stride ..][0..dst_stride];

        for (0..target_width) |dx| {
            const x_sample = x_samples[dx];
            const src_offset_00 = x_sample.left * src.channels;
            const src_offset_10 = x_sample.right * src.channels;
            const dst_offset = dx * dst.channels;
            bilinearPixel(
                dst_row[dst_offset ..][0..dst.channels],
                row0[src_offset_00 ..][0..src.channels],
                row0[src_offset_10 ..][0..src.channels],
                row1[src_offset_00 ..][0..src.channels],
                row1[src_offset_10 ..][0..src.channels],
                x_sample.weight,
                y_sample.weight,
            );
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
    if (src.width == target_width and src.height == target_height) return cloneImage(allocator, src);

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
    return resizeWithKernelFn(allocator, src, target_width, target_height, 2.0, bicubicKernel);
}

pub fn resizeLanczos3(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
) !ImageU8 {
    return resizeWithKernelFn(allocator, src, target_width, target_height, 3.0, lanczos3Kernel);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn resizeWithKernelFn(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
    support: f32,
    kernel: *const fn (f32) f32,
) !ImageU8 {
    try validateResizeInputs(src, target_width, target_height);
    if (src.width == target_width and src.height == target_height) return cloneImage(allocator, src);

    const x_table = try buildKernelAxisTable(allocator, src.width, target_width, support, kernel);
    defer freeKernelAxisTable(allocator, x_table);
    const y_table = try buildKernelAxisTable(allocator, src.height, target_height, support, kernel);
    defer freeKernelAxisTable(allocator, y_table);

    var dst = try ImageU8.init(allocator, target_width, target_height, src.channels);
    errdefer dst.deinit();
    const dst_stride = dst.width * dst.channels;

    for (0..target_height) |dy| {
        const y_offset = dy * y_table.sample_len;
        const y_indices = y_table.indices[y_offset .. y_offset + y_table.sample_len];
        const y_weights = y_table.weights[y_offset .. y_offset + y_table.sample_len];
        const dst_row = dst.data[dy * dst_stride ..][0..dst_stride];

        for (0..target_width) |dx| {
            const x_offset = dx * x_table.sample_len;
            const x_indices = x_table.indices[x_offset .. x_offset + x_table.sample_len];
            const x_weights = x_table.weights[x_offset .. x_offset + x_table.sample_len];
            const dst_offset = dx * dst.channels;

            for (0..src.channels) |channel| {
                var weighted_sum: f32 = 0.0;
                var weight_sum: f32 = 0.0;

                for (y_indices, y_weights) |sy, wy| {
                    if (wy == 0.0) continue;
                    const row = src.data[sy * src.width * src.channels ..][0 .. src.width * src.channels];
                    for (x_indices, x_weights) |sx, wx| {
                        const weight = wx * wy;
                        if (weight == 0.0) continue;
                        weighted_sum += @as(f32, @floatFromInt(row[sx * src.channels + channel])) * weight;
                        weight_sum += weight;
                    }
                }

                if (weight_sum == 0.0) {
                    const fallback_x = nearestSourceIndex(dx, src.width, target_width);
                    const fallback_y = nearestSourceIndex(dy, src.height, target_height);
                    dst_row[dst_offset + channel] = src.data[(fallback_y * src.width + fallback_x) * src.channels + channel];
                } else {
                    dst_row[dst_offset + channel] = clampToU8(weighted_sum / weight_sum);
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

const LinearAxisSample = struct {
    left: usize,
    right: usize,
    weight: f32,
};

const KernelAxisTable = struct {
    sample_len: usize,
    indices: []usize,
    weights: []f32,
};

fn buildNearestMap(
    allocator: std.mem.Allocator,
    src_extent: usize,
    dst_extent: usize,
) ![]usize {
    const map = try allocator.alloc(usize, dst_extent);
    errdefer allocator.free(map);
    for (map, 0..) |*entry, i| {
        entry.* = nearestSourceIndex(i, src_extent, dst_extent);
    }
    return map;
}

fn buildLinearAxisSamples(
    allocator: std.mem.Allocator,
    src_extent: usize,
    dst_extent: usize,
) ![]LinearAxisSample {
    const samples = try allocator.alloc(LinearAxisSample, dst_extent);
    errdefer allocator.free(samples);
    for (samples, 0..) |*sample, i| {
        const src_coord = sourceCenter(i, src_extent, dst_extent);
        const left = clampIndex(@as(isize, @intFromFloat(@floor(src_coord))), src_extent);
        sample.* = .{
            .left = left,
            .right = if (left + 1 < src_extent) left + 1 else src_extent - 1,
            .weight = src_coord - @as(f32, @floatFromInt(left)),
        };
    }
    return samples;
}

fn buildKernelAxisTable(
    allocator: std.mem.Allocator,
    src_extent: usize,
    dst_extent: usize,
    support: f32,
    kernel: *const fn (f32) f32,
) !KernelAxisTable {
    const radius: isize = @intFromFloat(@ceil(support));
    const sample_len: usize = @intCast(radius * 2);
    const total_len = dst_extent * sample_len;
    const indices = try allocator.alloc(usize, total_len);
    errdefer allocator.free(indices);
    const weights = try allocator.alloc(f32, total_len);
    errdefer allocator.free(weights);

    for (0..dst_extent) |i| {
        const src_coord = sourceCenter(i, src_extent, dst_extent);
        const center: isize = @intFromFloat(@floor(src_coord));
        const start = center - radius + 1;
        const base = i * sample_len;

        for (0..sample_len) |offset| {
            const sample_index = start + @as(isize, @intCast(offset));
            const clamped = clampIndex(sample_index, src_extent);
            indices[base + offset] = clamped;
            weights[base + offset] = kernel(src_coord - @as(f32, @floatFromInt(clamped)));
        }
    }

    return .{
        .sample_len = sample_len,
        .indices = indices,
        .weights = weights,
    };
}

fn freeKernelAxisTable(allocator: std.mem.Allocator, table: KernelAxisTable) void {
    allocator.free(table.indices);
    allocator.free(table.weights);
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

fn cloneImage(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();
    @memcpy(dst.data, src.data);
    return dst;
}

fn copyPixel(dst: []u8, src: []const u8) void {
    switch (src.len) {
        1 => dst[0] = src[0],
        3 => {
            dst[0] = src[0];
            dst[1] = src[1];
            dst[2] = src[2];
        },
        4 => {
            dst[0] = src[0];
            dst[1] = src[1];
            dst[2] = src[2];
            dst[3] = src[3];
        },
        else => @memcpy(dst, src),
    }
}

fn bilinearPixel(
    dst: []u8,
    p00: []const u8,
    p10: []const u8,
    p01: []const u8,
    p11: []const u8,
    wx: f32,
    wy: f32,
) void {
    switch (dst.len) {
        1 => dst[0] = bilinearChannel(p00[0], p10[0], p01[0], p11[0], wx, wy),
        3 => {
            dst[0] = bilinearChannel(p00[0], p10[0], p01[0], p11[0], wx, wy);
            dst[1] = bilinearChannel(p00[1], p10[1], p01[1], p11[1], wx, wy);
            dst[2] = bilinearChannel(p00[2], p10[2], p01[2], p11[2], wx, wy);
        },
        4 => {
            dst[0] = bilinearChannel(p00[0], p10[0], p01[0], p11[0], wx, wy);
            dst[1] = bilinearChannel(p00[1], p10[1], p01[1], p11[1], wx, wy);
            dst[2] = bilinearChannel(p00[2], p10[2], p01[2], p11[2], wx, wy);
            dst[3] = bilinearChannel(p00[3], p10[3], p01[3], p11[3], wx, wy);
        },
        else => {
            for (0..dst.len) |channel| {
                dst[channel] = bilinearChannel(p00[channel], p10[channel], p01[channel], p11[channel], wx, wy);
            }
        },
    }
}

fn bilinearChannel(p00: u8, p10: u8, p01: u8, p11: u8, wx: f32, wy: f32) u8 {
    const top = lerp(@floatFromInt(p00), @floatFromInt(p10), wx);
    const bottom = lerp(@floatFromInt(p01), @floatFromInt(p11), wx);
    return @intFromFloat(@round(lerp(top, bottom, wy)));
}
