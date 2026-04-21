const std = @import("std");
const jpeg_types = @import("types.zig");

const ComponentPlane = jpeg_types.ComponentPlane;

pub fn idctBlock(coeffs: *const [64]i32, quant: *const [64]u16) [64]u8 {
    var out = [_]u8{0} ** 64;
    const inv_sqrt2: f64 = 0.7071067811865476;

    for (0..8) |y| {
        for (0..8) |x| {
            var sum: f64 = 0.0;
            for (0..8) |v| {
                const cv = if (v == 0) inv_sqrt2 else 1.0;
                const cos_y = std.math.cos((@as(f64, @floatFromInt(2 * y + 1)) * @as(f64, @floatFromInt(v)) * std.math.pi) / 16.0);
                for (0..8) |u| {
                    const cu = if (u == 0) inv_sqrt2 else 1.0;
                    const cos_x = std.math.cos((@as(f64, @floatFromInt(2 * x + 1)) * @as(f64, @floatFromInt(u)) * std.math.pi) / 16.0);
                    const idx = v * 8 + u;
                    const value = @as(f64, @floatFromInt(coeffs[idx])) * @as(f64, @floatFromInt(quant[idx]));
                    sum += cu * cv * value * cos_x * cos_y;
                }
            }
            out[y * 8 + x] = clampToU8(@as(f32, @floatCast(sum / 4.0 + 128.0)));
        }
    }

    return out;
}

pub fn writeBlock(plane: *ComponentPlane, block_x: usize, block_y: usize, samples: *const [64]u8) !void {
    const start_x = block_x * 8;
    const start_y = block_y * 8;
    if (start_x + 8 > plane.plane_width or start_y + 8 > plane.plane_height) return error.InvalidJpegData;
    for (0..8) |y| {
        const dst_row = (start_y + y) * plane.plane_width + start_x;
        const src_row = y * 8;
        @memcpy(plane.samples[dst_row .. dst_row + 8], samples[src_row .. src_row + 8]);
    }
}

pub fn samplePlane(plane: *const ComponentPlane, x: usize, y: usize, frame_width: usize, frame_height: usize) u8 {
    const src_x = sampleCenter(x, plane.actual_width, frame_width);
    const src_y = sampleCenter(y, plane.actual_height, frame_height);

    const x0_unclamped: isize = @intFromFloat(@floor(src_x));
    const y0_unclamped: isize = @intFromFloat(@floor(src_y));
    const tx = src_x - @as(f32, @floatFromInt(x0_unclamped));
    const ty = src_y - @as(f32, @floatFromInt(y0_unclamped));

    const x0 = clampIndex(x0_unclamped, plane.actual_width);
    const y0 = clampIndex(y0_unclamped, plane.actual_height);
    const x1 = clampIndex(x0_unclamped + 1, plane.actual_width);
    const y1 = clampIndex(y0_unclamped + 1, plane.actual_height);

    const p00 = @as(f32, @floatFromInt(plane.samples[y0 * plane.plane_width + x0]));
    const p10 = @as(f32, @floatFromInt(plane.samples[y0 * plane.plane_width + x1]));
    const p01 = @as(f32, @floatFromInt(plane.samples[y1 * plane.plane_width + x0]));
    const p11 = @as(f32, @floatFromInt(plane.samples[y1 * plane.plane_width + x1]));

    const top = lerp(p00, p10, tx);
    const bottom = lerp(p01, p11, tx);
    return clampToU8(lerp(top, bottom, ty));
}

pub fn divCeil(a: usize, b: usize) usize {
    return (a + b - 1) / b;
}

fn clampToU8(value: f32) u8 {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return @intFromFloat(@round(value));
}

fn sampleCenter(dst_index: usize, src_extent: usize, dst_extent: usize) f32 {
    return ((@as(f32, @floatFromInt(dst_index)) + 0.5) * @as(f32, @floatFromInt(src_extent)) / @as(f32, @floatFromInt(dst_extent))) - 0.5;
}

fn clampIndex(value: isize, upper: usize) usize {
    if (value < 0) return 0;
    const upper_index: isize = @intCast(upper - 1);
    if (value > upper_index) return upper - 1;
    return @intCast(value);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

test "samplePlane exact on full-resolution plane" {
    const testing = std.testing;

    var samples = [_]u8{
        10, 20,
        30, 40,
    };
    const plane = ComponentPlane{
        .samples = samples[0..],
        .plane_width = 2,
        .plane_height = 2,
        .actual_width = 2,
        .actual_height = 2,
        .h = 1,
        .v = 1,
    };

    try testing.expectEqual(@as(u8, 10), samplePlane(&plane, 0, 0, 2, 2));
    try testing.expectEqual(@as(u8, 20), samplePlane(&plane, 1, 0, 2, 2));
    try testing.expectEqual(@as(u8, 30), samplePlane(&plane, 0, 1, 2, 2));
    try testing.expectEqual(@as(u8, 40), samplePlane(&plane, 1, 1, 2, 2));
}

test "samplePlane linearly upsamples subsampled plane" {
    const testing = std.testing;

    var samples = [_]u8{
        0, 100,
        150, 200,
    };
    const plane = ComponentPlane{
        .samples = samples[0..],
        .plane_width = 2,
        .plane_height = 2,
        .actual_width = 2,
        .actual_height = 2,
        .h = 1,
        .v = 1,
    };

    try testing.expectEqual(@as(u8, 0), samplePlane(&plane, 0, 0, 4, 4));
    try testing.expectEqual(@as(u8, 59), samplePlane(&plane, 1, 1, 4, 4));
    try testing.expectEqual(@as(u8, 128), samplePlane(&plane, 2, 2, 4, 4));
    try testing.expectEqual(@as(u8, 200), samplePlane(&plane, 3, 3, 4, 4));
}
