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

    const kernel = try buildGaussianKernel(allocator, sigma);
    defer allocator.free(kernel);

    var horizontal = try ImageU8.init(allocator, src.width, src.height, src.channels);
    defer horizontal.deinit();
    var dst = try ImageU8.init(allocator, src.width, src.height, src.channels);
    errdefer dst.deinit();

    try convolveHorizontal(src, &horizontal, kernel);
    try convolveVertical(&horizontal, &dst, kernel);
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

    for (0..src.height) |y| {
        for (0..src.channels) |channel| {
            var sum: usize = 0;

            for (0..window) |offset| {
                const sx = clampOffset(offset, radius, src.width);
                sum += src.get(sx, y, channel);
            }
            dst.set(0, y, channel, @intCast((sum + window / 2) / window));

            for (1..src.width) |x| {
                const remove_x = clampOffset(x - 1, radius, src.width);
                const add_x = clampOffset(x + radius, 0, src.width);
                sum -= src.get(remove_x, y, channel);
                sum += src.get(add_x, y, channel);
                std.debug.assert(sum <= max_window_sum);
                dst.set(x, y, channel, @intCast((sum + window / 2) / window));
            }
        }
    }
}

fn boxBlurVertical(src: *const ImageU8, dst: *ImageU8, radius: usize) !void {
    const window = radius * 2 + 1;
    const max_window_sum = window * 255;

    for (0..src.width) |x| {
        for (0..src.channels) |channel| {
            var sum: usize = 0;

            for (0..window) |offset| {
                const sy = clampOffset(offset, radius, src.height);
                sum += src.get(x, sy, channel);
            }
            dst.set(x, 0, channel, @intCast((sum + window / 2) / window));

            for (1..src.height) |y| {
                const remove_y = clampOffset(y - 1, radius, src.height);
                const add_y = clampOffset(y + radius, 0, src.height);
                sum -= src.get(x, remove_y, channel);
                sum += src.get(x, add_y, channel);
                std.debug.assert(sum <= max_window_sum);
                dst.set(x, y, channel, @intCast((sum + window / 2) / window));
            }
        }
    }
}

fn convolveHorizontal(src: *const ImageU8, dst: *ImageU8, kernel: []const f32) !void {
    const radius = kernel.len / 2;

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            for (0..src.channels) |channel| {
                var sum: f32 = 0.0;
                for (kernel, 0..) |weight, index| {
                    const sx = clampOffset(x + index, radius, src.width);
                    sum += @as(f32, @floatFromInt(src.get(sx, y, channel))) * weight;
                }
                dst.set(x, y, channel, clampToU8(sum));
            }
        }
    }
}

fn convolveVertical(src: *const ImageU8, dst: *ImageU8, kernel: []const f32) !void {
    const radius = kernel.len / 2;

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            for (0..src.channels) |channel| {
                var sum: f32 = 0.0;
                for (kernel, 0..) |weight, index| {
                    const sy = clampOffset(y + index, radius, src.height);
                    sum += @as(f32, @floatFromInt(src.get(x, sy, channel))) * weight;
                }
                dst.set(x, y, channel, clampToU8(sum));
            }
        }
    }
}

fn buildGaussianKernel(allocator: std.mem.Allocator, sigma: f32) ![]f32 {
    const radius: usize = @max(@as(usize, 1), @as(usize, @intFromFloat(@ceil(sigma * 3.0))));
    const len = radius * 2 + 1;
    const kernel = try allocator.alloc(f32, len);
    errdefer allocator.free(kernel);

    var sum: f32 = 0.0;
    for (0..len) |i| {
        const distance = @as(f32, @floatFromInt(@as(isize, @intCast(i)) - @as(isize, @intCast(radius))));
        const value = @exp(-(distance * distance) / (2.0 * sigma * sigma));
        kernel[i] = value;
        sum += value;
    }

    for (kernel) |*value| value.* /= sum;
    return kernel;
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
