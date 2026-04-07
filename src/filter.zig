const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;

pub fn boxBlur(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    radius: usize,
) !ImageU8 {
    try validateFilterInputs(src);
    if (radius == 0) return cloneImage(allocator, src);

    var horizontal = try ImageU8.init(allocator, src.width, src.height, src.channels);
    defer horizontal.deinit();
    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    try boxBlurHorizontal(src, &horizontal, radius);
    try boxBlurVertical(&horizontal, &dst, radius);
    return dst;
}

pub fn gaussianBlur(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    sigma: f32,
) !ImageU8 {
    try validateFilterInputs(src);
    if (sigma <= 0.0) return error.InvalidFilterParameter;

    const kernel = try buildGaussianKernelFixed(allocator, sigma);
    defer allocator.free(kernel.weights);

    var horizontal = try ImageU8.init(allocator, src.width, src.height, src.channels);
    defer horizontal.deinit();
    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    convolveHorizontalFixed(src, &horizontal, kernel);
    convolveVerticalFixed(&horizontal, &dst, kernel);
    return dst;
}

pub fn sharpen(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    sigma: f32,
    amount: f32,
) !ImageU8 {
    try validateFilterInputs(src);
    if (sigma <= 0.0 or amount < 0.0) return error.InvalidFilterParameter;
    if (amount == 0.0) return cloneImage(allocator, src);

    var blurred = try gaussianBlur(allocator, src, sigma);
    defer blurred.deinit();

    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    for (src.data, blurred.data, 0..) |original, blurred_value, i| {
        const value = @as(f32, @floatFromInt(original)) + amount * (@as(f32, @floatFromInt(original)) - @as(f32, @floatFromInt(blurred_value)));
        dst.data[i] = clampToU8(value);
    }

    return dst;
}

pub fn medianFilter(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    radius: usize,
) !ImageU8 {
    try validateFilterInputs(src);
    if (radius == 0) return cloneImage(allocator, src);

    const window_len = (radius * 2 + 1) * (radius * 2 + 1);
    var values = try allocator.alloc(u8, window_len);
    defer allocator.free(values);

    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            for (0..src.channels) |channel| {
                var count: usize = 0;
                var sy_i: isize = @intCast(y);
                sy_i -= @intCast(radius);
                while (sy_i <= @as(isize, @intCast(y + radius))) : (sy_i += 1) {
                    const sy = clampSignedIndex(sy_i, src.height);
                    var sx_i: isize = @intCast(x);
                    sx_i -= @intCast(radius);
                    while (sx_i <= @as(isize, @intCast(x + radius))) : (sx_i += 1) {
                        const sx = clampSignedIndex(sx_i, src.width);
                        values[count] = src.get(sx, sy, channel);
                        count += 1;
                    }
                }

                std.mem.sort(u8, values[0..count], {}, comptime std.sort.asc(u8));
                dst.set(x, y, channel, values[count / 2]);
            }
        }
    }

    return dst;
}

pub fn edgeDetect(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
) !ImageU8 {
    try validateFilterInputs(src);

    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    const gx_kernel = [3][3]i32{
        .{ -1, 0, 1 },
        .{ -2, 0, 2 },
        .{ -1, 0, 1 },
    };
    const gy_kernel = [3][3]i32{
        .{ -1, -2, -1 },
        .{ 0, 0, 0 },
        .{ 1, 2, 1 },
    };

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            for (0..src.channels) |channel| {
                var gx: f32 = 0.0;
                var gy: f32 = 0.0;
                for (0..3) |ky| {
                    const sy = clampSignedIndex(@as(isize, @intCast(y)) + @as(isize, @intCast(ky)) - 1, src.height);
                    for (0..3) |kx| {
                        const sx = clampSignedIndex(@as(isize, @intCast(x)) + @as(isize, @intCast(kx)) - 1, src.width);
                        const sample = @as(f32, @floatFromInt(src.get(sx, sy, channel)));
                        gx += sample * @as(f32, @floatFromInt(gx_kernel[ky][kx]));
                        gy += sample * @as(f32, @floatFromInt(gy_kernel[ky][kx]));
                    }
                }
                dst.set(x, y, channel, clampToU8(@sqrt(gx * gx + gy * gy)));
            }
        }
    }

    return dst;
}

pub fn emboss(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
) !ImageU8 {
    try validateFilterInputs(src);

    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    const kernel = [3][3]i32{
        .{ -2, -1, 0 },
        .{ -1, 1, 1 },
        .{ 0, 1, 2 },
    };

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            for (0..src.channels) |channel| {
                var sum: f32 = 128.0;
                for (0..3) |ky| {
                    const sy = clampSignedIndex(@as(isize, @intCast(y)) + @as(isize, @intCast(ky)) - 1, src.height);
                    for (0..3) |kx| {
                        const sx = clampSignedIndex(@as(isize, @intCast(x)) + @as(isize, @intCast(kx)) - 1, src.width);
                        sum += @as(f32, @floatFromInt(src.get(sx, sy, channel))) * @as(f32, @floatFromInt(kernel[ky][kx]));
                    }
                }
                dst.set(x, y, channel, clampToU8(sum));
            }
        }
    }

    return dst;
}

fn validateFilterInputs(src: *const ImageU8) !void {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;
}

fn cloneImage(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();
    @memcpy(dst.data, src.data);
    return dst;
}

fn boxBlurHorizontal(src: *const ImageU8, dst: *ImageU8, radius: usize) !void {
    const window = radius * 2 + 1;
    const max_window_sum = window * 255;
    const row_stride = src.width * src.channels;

    for (0..src.height) |y| {
        const src_row = src.data[y * row_stride ..][0..row_stride];
        const dst_row = dst.data[y * row_stride ..][0..row_stride];
        switch (src.channels) {
            1 => boxBlurHorizontalC1(src_row, dst_row, src.width, radius, window, max_window_sum),
            3 => boxBlurHorizontalC3(src_row, dst_row, src.width, radius, window, max_window_sum),
            4 => boxBlurHorizontalC4(src_row, dst_row, src.width, radius, window, max_window_sum),
            else => boxBlurHorizontalGeneric(src_row, dst_row, src.width, src.channels, radius, window, max_window_sum),
        }
    }
}

fn boxBlurVertical(src: *const ImageU8, dst: *ImageU8, radius: usize) !void {
    const window = radius * 2 + 1;
    const max_window_sum = window * 255;
    const row_stride = src.width * src.channels;

    switch (src.channels) {
        1 => {
            for (0..src.width) |x| boxBlurVerticalC1(src, dst, x, radius, window, max_window_sum, row_stride);
        },
        3 => {
            for (0..src.width) |x| boxBlurVerticalC3(src, dst, x, radius, window, max_window_sum, row_stride);
        },
        4 => {
            for (0..src.width) |x| boxBlurVerticalC4(src, dst, x, radius, window, max_window_sum, row_stride);
        },
        else => {
            for (0..src.width) |x| boxBlurVerticalGeneric(src, dst, x, radius, window, max_window_sum, row_stride);
        }
    }
}

const FixedKernel = struct {
    radius: usize,
    sum: u32,
    weights: []u16,
};

fn convolveHorizontalFixed(src: *const ImageU8, dst: *ImageU8, kernel: FixedKernel) void {
    const row_stride = src.width * src.channels;

    for (0..src.height) |y| {
        const src_row = src.data[y * row_stride ..][0..row_stride];
        const dst_row = dst.data[y * row_stride ..][0..row_stride];
        switch (src.channels) {
            1 => convolveHorizontalFixedC1(src_row, dst_row, src.width, kernel),
            3 => convolveHorizontalFixedC3(src_row, dst_row, src.width, kernel),
            4 => convolveHorizontalFixedC4(src_row, dst_row, src.width, kernel),
            else => convolveHorizontalFixedGeneric(src_row, dst_row, src.width, src.channels, kernel),
        }
    }
}

fn convolveVerticalFixed(src: *const ImageU8, dst: *ImageU8, kernel: FixedKernel) void {
    const row_stride = src.width * src.channels;

    switch (src.channels) {
        1 => {
            for (0..src.width) |x| convolveVerticalFixedC1(src, dst, x, row_stride, kernel);
        },
        3 => {
            for (0..src.width) |x| convolveVerticalFixedC3(src, dst, x, row_stride, kernel);
        },
        4 => {
            for (0..src.width) |x| convolveVerticalFixedC4(src, dst, x, row_stride, kernel);
        },
        else => {
            for (0..src.width) |x| convolveVerticalFixedGeneric(src, dst, x, row_stride, kernel);
        }
    }
}

fn boxBlurHorizontalC1(src_row: []const u8, dst_row: []u8, width: usize, radius: usize, window: usize, max_window_sum: usize) void {
    var sum: usize = 0;
    for (0..window) |offset| sum += src_row[clampOffset(offset, radius, width)];
    dst_row[0] = @intCast((sum + window / 2) / window);
    for (1..width) |x| {
        sum -= src_row[clampOffset(x - 1, radius, width)];
        sum += src_row[clampOffset(x + radius, 0, width)];
        std.debug.assert(sum <= max_window_sum);
        dst_row[x] = @intCast((sum + window / 2) / window);
    }
}

fn boxBlurHorizontalC3(src_row: []const u8, dst_row: []u8, width: usize, radius: usize, window: usize, max_window_sum: usize) void {
    var s0: usize = 0;
    var s1: usize = 0;
    var s2: usize = 0;
    for (0..window) |offset| {
        const base = clampOffset(offset, radius, width) * 3;
        s0 += src_row[base];
        s1 += src_row[base + 1];
        s2 += src_row[base + 2];
    }
    dst_row[0] = @intCast((s0 + window / 2) / window);
    dst_row[1] = @intCast((s1 + window / 2) / window);
    dst_row[2] = @intCast((s2 + window / 2) / window);
    for (1..width) |x| {
        const remove = clampOffset(x - 1, radius, width) * 3;
        const add = clampOffset(x + radius, 0, width) * 3;
        s0 = s0 - src_row[remove] + src_row[add];
        s1 = s1 - src_row[remove + 1] + src_row[add + 1];
        s2 = s2 - src_row[remove + 2] + src_row[add + 2];
        std.debug.assert(s0 <= max_window_sum and s1 <= max_window_sum and s2 <= max_window_sum);
        const base = x * 3;
        dst_row[base] = @intCast((s0 + window / 2) / window);
        dst_row[base + 1] = @intCast((s1 + window / 2) / window);
        dst_row[base + 2] = @intCast((s2 + window / 2) / window);
    }
}

fn boxBlurHorizontalC4(src_row: []const u8, dst_row: []u8, width: usize, radius: usize, window: usize, max_window_sum: usize) void {
    var sums = [4]usize{ 0, 0, 0, 0 };
    for (0..window) |offset| {
        const base = clampOffset(offset, radius, width) * 4;
        inline for (0..4) |channel| sums[channel] += src_row[base + channel];
    }
    inline for (0..4) |channel| dst_row[channel] = @intCast((sums[channel] + window / 2) / window);
    for (1..width) |x| {
        const remove = clampOffset(x - 1, radius, width) * 4;
        const add = clampOffset(x + radius, 0, width) * 4;
        inline for (0..4) |channel| {
            sums[channel] = sums[channel] - src_row[remove + channel] + src_row[add + channel];
            std.debug.assert(sums[channel] <= max_window_sum);
        }
        const base = x * 4;
        inline for (0..4) |channel| dst_row[base + channel] = @intCast((sums[channel] + window / 2) / window);
    }
}

fn boxBlurHorizontalGeneric(src_row: []const u8, dst_row: []u8, width: usize, channels: usize, radius: usize, window: usize, max_window_sum: usize) void {
    for (0..channels) |channel| {
        var sum: usize = 0;
        for (0..window) |offset| sum += src_row[clampOffset(offset, radius, width) * channels + channel];
        dst_row[channel] = @intCast((sum + window / 2) / window);
        for (1..width) |x| {
            sum -= src_row[clampOffset(x - 1, radius, width) * channels + channel];
            sum += src_row[clampOffset(x + radius, 0, width) * channels + channel];
            std.debug.assert(sum <= max_window_sum);
            dst_row[x * channels + channel] = @intCast((sum + window / 2) / window);
        }
    }
}

fn boxBlurVerticalC1(src: *const ImageU8, dst: *ImageU8, x: usize, radius: usize, window: usize, max_window_sum: usize, row_stride: usize) void {
    var sum: usize = 0;
    for (0..window) |offset| sum += src.data[clampOffset(offset, radius, src.height) * row_stride + x];
    dst.data[x] = @intCast((sum + window / 2) / window);
    for (1..src.height) |y| {
        sum -= src.data[clampOffset(y - 1, radius, src.height) * row_stride + x];
        sum += src.data[clampOffset(y + radius, 0, src.height) * row_stride + x];
        std.debug.assert(sum <= max_window_sum);
        dst.data[y * row_stride + x] = @intCast((sum + window / 2) / window);
    }
}

fn boxBlurVerticalC3(src: *const ImageU8, dst: *ImageU8, x: usize, radius: usize, window: usize, max_window_sum: usize, row_stride: usize) void {
    const base_x = x * 3;
    var s0: usize = 0;
    var s1: usize = 0;
    var s2: usize = 0;
    for (0..window) |offset| {
        const base = clampOffset(offset, radius, src.height) * row_stride + base_x;
        s0 += src.data[base];
        s1 += src.data[base + 1];
        s2 += src.data[base + 2];
    }
    dst.data[base_x] = @intCast((s0 + window / 2) / window);
    dst.data[base_x + 1] = @intCast((s1 + window / 2) / window);
    dst.data[base_x + 2] = @intCast((s2 + window / 2) / window);
    for (1..src.height) |y| {
        const remove = clampOffset(y - 1, radius, src.height) * row_stride + base_x;
        const add = clampOffset(y + radius, 0, src.height) * row_stride + base_x;
        s0 = s0 - src.data[remove] + src.data[add];
        s1 = s1 - src.data[remove + 1] + src.data[add + 1];
        s2 = s2 - src.data[remove + 2] + src.data[add + 2];
        std.debug.assert(s0 <= max_window_sum and s1 <= max_window_sum and s2 <= max_window_sum);
        const base = y * row_stride + base_x;
        dst.data[base] = @intCast((s0 + window / 2) / window);
        dst.data[base + 1] = @intCast((s1 + window / 2) / window);
        dst.data[base + 2] = @intCast((s2 + window / 2) / window);
    }
}

fn boxBlurVerticalC4(src: *const ImageU8, dst: *ImageU8, x: usize, radius: usize, window: usize, max_window_sum: usize, row_stride: usize) void {
    const base_x = x * 4;
    var sums = [4]usize{ 0, 0, 0, 0 };
    for (0..window) |offset| {
        const base = clampOffset(offset, radius, src.height) * row_stride + base_x;
        inline for (0..4) |channel| sums[channel] += src.data[base + channel];
    }
    inline for (0..4) |channel| dst.data[base_x + channel] = @intCast((sums[channel] + window / 2) / window);
    for (1..src.height) |y| {
        const remove = clampOffset(y - 1, radius, src.height) * row_stride + base_x;
        const add = clampOffset(y + radius, 0, src.height) * row_stride + base_x;
        inline for (0..4) |channel| {
            sums[channel] = sums[channel] - src.data[remove + channel] + src.data[add + channel];
            std.debug.assert(sums[channel] <= max_window_sum);
        }
        const base = y * row_stride + base_x;
        inline for (0..4) |channel| dst.data[base + channel] = @intCast((sums[channel] + window / 2) / window);
    }
}

fn boxBlurVerticalGeneric(src: *const ImageU8, dst: *ImageU8, x: usize, radius: usize, window: usize, max_window_sum: usize, row_stride: usize) void {
    for (0..src.channels) |channel| {
        const base_x = x * src.channels + channel;
        var sum: usize = 0;
        for (0..window) |offset| sum += src.data[clampOffset(offset, radius, src.height) * row_stride + base_x];
        dst.data[base_x] = @intCast((sum + window / 2) / window);
        for (1..src.height) |y| {
            sum -= src.data[clampOffset(y - 1, radius, src.height) * row_stride + base_x];
            sum += src.data[clampOffset(y + radius, 0, src.height) * row_stride + base_x];
            std.debug.assert(sum <= max_window_sum);
            dst.data[y * row_stride + base_x] = @intCast((sum + window / 2) / window);
        }
    }
}

fn convolveHorizontalFixedC1(src_row: []const u8, dst_row: []u8, width: usize, kernel: FixedKernel) void {
    for (0..width) |x| {
        var sum: u32 = 0;
        for (kernel.weights, 0..) |weight, index| sum += @as(u32, src_row[clampOffset(x + index, kernel.radius, width)]) * weight;
        dst_row[x] = divideRoundToU8(sum, kernel.sum);
    }
}

fn convolveHorizontalFixedC3(src_row: []const u8, dst_row: []u8, width: usize, kernel: FixedKernel) void {
    for (0..width) |x| {
        const base = x * 3;
        var s0: u32 = 0;
        var s1: u32 = 0;
        var s2: u32 = 0;
        for (kernel.weights, 0..) |weight, index| {
            const sample = clampOffset(x + index, kernel.radius, width) * 3;
            s0 += @as(u32, src_row[sample]) * weight;
            s1 += @as(u32, src_row[sample + 1]) * weight;
            s2 += @as(u32, src_row[sample + 2]) * weight;
        }
        dst_row[base] = divideRoundToU8(s0, kernel.sum);
        dst_row[base + 1] = divideRoundToU8(s1, kernel.sum);
        dst_row[base + 2] = divideRoundToU8(s2, kernel.sum);
    }
}

fn convolveHorizontalFixedC4(src_row: []const u8, dst_row: []u8, width: usize, kernel: FixedKernel) void {
    for (0..width) |x| {
        const base = x * 4;
        var sums = [4]u32{ 0, 0, 0, 0 };
        for (kernel.weights, 0..) |weight, index| {
            const sample = clampOffset(x + index, kernel.radius, width) * 4;
            inline for (0..4) |channel| sums[channel] += @as(u32, src_row[sample + channel]) * weight;
        }
        inline for (0..4) |channel| dst_row[base + channel] = divideRoundToU8(sums[channel], kernel.sum);
    }
}

fn convolveHorizontalFixedGeneric(src_row: []const u8, dst_row: []u8, width: usize, channels: usize, kernel: FixedKernel) void {
    for (0..width) |x| {
        const base = x * channels;
        for (0..channels) |channel| {
            var sum: u32 = 0;
            for (kernel.weights, 0..) |weight, index| {
                const sample = clampOffset(x + index, kernel.radius, width) * channels + channel;
                sum += @as(u32, src_row[sample]) * weight;
            }
            dst_row[base + channel] = divideRoundToU8(sum, kernel.sum);
        }
    }
}

fn convolveVerticalFixedC1(src: *const ImageU8, dst: *ImageU8, x: usize, row_stride: usize, kernel: FixedKernel) void {
    for (0..src.height) |y| {
        var sum: u32 = 0;
        for (kernel.weights, 0..) |weight, index| {
            const sy = clampOffset(y + index, kernel.radius, src.height);
            sum += @as(u32, src.data[sy * row_stride + x]) * weight;
        }
        dst.data[y * row_stride + x] = divideRoundToU8(sum, kernel.sum);
    }
}

fn convolveVerticalFixedC3(src: *const ImageU8, dst: *ImageU8, x: usize, row_stride: usize, kernel: FixedKernel) void {
    const base_x = x * 3;
    for (0..src.height) |y| {
        var s0: u32 = 0;
        var s1: u32 = 0;
        var s2: u32 = 0;
        for (kernel.weights, 0..) |weight, index| {
            const base = clampOffset(y + index, kernel.radius, src.height) * row_stride + base_x;
            s0 += @as(u32, src.data[base]) * weight;
            s1 += @as(u32, src.data[base + 1]) * weight;
            s2 += @as(u32, src.data[base + 2]) * weight;
        }
        const dst_base = y * row_stride + base_x;
        dst.data[dst_base] = divideRoundToU8(s0, kernel.sum);
        dst.data[dst_base + 1] = divideRoundToU8(s1, kernel.sum);
        dst.data[dst_base + 2] = divideRoundToU8(s2, kernel.sum);
    }
}

fn convolveVerticalFixedC4(src: *const ImageU8, dst: *ImageU8, x: usize, row_stride: usize, kernel: FixedKernel) void {
    const base_x = x * 4;
    for (0..src.height) |y| {
        var sums = [4]u32{ 0, 0, 0, 0 };
        for (kernel.weights, 0..) |weight, index| {
            const base = clampOffset(y + index, kernel.radius, src.height) * row_stride + base_x;
            inline for (0..4) |channel| sums[channel] += @as(u32, src.data[base + channel]) * weight;
        }
        const dst_base = y * row_stride + base_x;
        inline for (0..4) |channel| dst.data[dst_base + channel] = divideRoundToU8(sums[channel], kernel.sum);
    }
}

fn convolveVerticalFixedGeneric(src: *const ImageU8, dst: *ImageU8, x: usize, row_stride: usize, kernel: FixedKernel) void {
    for (0..src.height) |y| {
        const dst_base = y * row_stride + x * src.channels;
        for (0..src.channels) |channel| {
            var sum: u32 = 0;
            for (kernel.weights, 0..) |weight, index| {
                const base = clampOffset(y + index, kernel.radius, src.height) * row_stride + x * src.channels + channel;
                sum += @as(u32, src.data[base]) * weight;
            }
            dst.data[dst_base + channel] = divideRoundToU8(sum, kernel.sum);
        }
    }
}

fn buildGaussianKernelFixed(allocator: std.mem.Allocator, sigma: f32) !FixedKernel {
    const radius: usize = @max(@as(usize, 1), @as(usize, @intFromFloat(@ceil(sigma * 3.0))));
    const len = radius * 2 + 1;
    const weights = try allocator.alloc(u16, len);
    errdefer allocator.free(weights);
    const fixed_scale: u32 = 1 << 14;

    var float_sum: f64 = 0.0;
    var max_index: usize = radius;
    var max_value: f64 = 0.0;
    for (0..len) |i| {
        const distance = @as(f64, @floatFromInt(@as(isize, @intCast(i)) - @as(isize, @intCast(radius))));
        const value = std.math.exp(-(distance * distance) / (2.0 * @as(f64, sigma) * @as(f64, sigma)));
        if (value > max_value) {
            max_value = value;
            max_index = i;
        }
        weights[i] = @intFromFloat(value * @as(f64, fixed_scale));
        float_sum += value;
    }

    var sum: u32 = 0;
    for (weights, 0..) |*weight, i| {
        const distance = @as(f64, @floatFromInt(@as(isize, @intCast(i)) - @as(isize, @intCast(radius))));
        const value = std.math.exp(-(distance * distance) / (2.0 * @as(f64, sigma) * @as(f64, sigma))) / float_sum;
        weight.* = @intFromFloat(@round(value * @as(f64, fixed_scale)));
        sum += weight.*;
    }

    if (sum != fixed_scale) {
        const corrected = @as(i32, @intCast(weights[max_index])) + @as(i32, @intCast(fixed_scale - sum));
        weights[max_index] = @intCast(@max(1, corrected));
        sum = 0;
        for (weights) |weight| sum += weight;
    }

    return .{
        .radius = radius,
        .sum = sum,
        .weights = weights,
    };
}

fn clampOffset(index_plus_offset: usize, radius: usize, upper: usize) usize {
    const signed = @as(isize, @intCast(index_plus_offset)) - @as(isize, @intCast(radius));
    if (signed < 0) return 0;
    const max_index: isize = @intCast(upper - 1);
    if (signed > max_index) return upper - 1;
    return @intCast(signed);
}

fn clampSignedIndex(value: isize, upper: usize) usize {
    if (value < 0) return 0;
    const upper_index: isize = @intCast(upper - 1);
    if (value > upper_index) return upper - 1;
    return @intCast(value);
}

fn clampToU8(value: f32) u8 {
    if (value <= 0.0) return 0;
    if (value >= 255.0) return 255;
    return @intFromFloat(@round(value));
}

fn divideRoundToU8(sum: u32, divisor: u32) u8 {
    return @intCast(@min(@as(u32, 255), (sum + divisor / 2) / divisor));
}
