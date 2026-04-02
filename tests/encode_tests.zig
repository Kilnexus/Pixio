const std = @import("std");
const imaging = @import("Pixio");

test "encodePngAlloc round-trips rgb image" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 3);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        255, 0, 0,
        0, 255, 0,
    });

    const png = try imaging.encodePngAlloc(testing.allocator, &src);
    defer testing.allocator.free(png);

    var decoded = try imaging.decodeRgb8(testing.allocator, png);
    defer decoded.deinit();

    try testing.expectEqual(@as(usize, 2), decoded.width);
    try testing.expectEqual(@as(usize, 1), decoded.height);
    try testing.expectEqualSlices(u8, src.data, decoded.data);
}

test "encodePngAlloc round-trips rgba alpha" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 4);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        255, 255, 255, 255,
        0, 0, 0, 128,
    });

    const png = try imaging.encodePngAlloc(testing.allocator, &src);
    defer testing.allocator.free(png);

    var decoded = try imaging.decodeRgba8(testing.allocator, png);
    defer decoded.deinit();

    try testing.expectEqual(@as(usize, 4), decoded.channels);
    try testing.expectEqualSlices(u8, src.data, decoded.data);
}

test "writePngFile writes decodable grayscale png" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 2, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 0, 85, 170, 255 });

    const path = "._pixio_encode_gray.png";
    defer std.fs.cwd().deleteFile(path) catch {};
    try imaging.writePngFile(testing.allocator, path, &src);

    const encoded = try std.fs.cwd().readFileAlloc(testing.allocator, path, 1 << 20);
    defer testing.allocator.free(encoded);

    var decoded = try imaging.decodeRgb8(testing.allocator, encoded);
    defer decoded.deinit();

    try testing.expectEqual(@as(usize, 2), decoded.width);
    try testing.expectEqual(@as(usize, 2), decoded.height);
    try testing.expectEqualSlices(u8, &[_]u8{
        0, 0, 0,
        85, 85, 85,
        170, 170, 170,
        255, 255, 255,
    }, decoded.data);
}

test "encodeJpegAlloc round-trips rgb image approximately" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 8, 8, 3);
    defer src.deinit();

    for (0..src.height) |y| {
        for (0..src.width) |x| {
            const base = src.pixelIndex(x, y, 0);
            src.data[base] = @intCast(x * 32);
            src.data[base + 1] = @intCast(y * 32);
            src.data[base + 2] = @intCast((x + y) * 16);
        }
    }

    const jpeg = try imaging.encodeJpegAlloc(testing.allocator, &src, .{ .quality = 95 });
    defer testing.allocator.free(jpeg);

    var decoded = try imaging.decodeRgb8(testing.allocator, jpeg);
    defer decoded.deinit();

    try testing.expectEqual(src.width, decoded.width);
    try testing.expectEqual(src.height, decoded.height);
    try testing.expect(meanAbsDiff(src.data, decoded.data) <= 8.0);
}

test "encodeJpegAlloc encodes grayscale image" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 8, 8, 1);
    defer src.deinit();
    for (src.data, 0..) |*value, i| value.* = @intCast(i * 4);

    const jpeg = try imaging.encodeJpegAlloc(testing.allocator, &src, .{ .quality = 92 });
    defer testing.allocator.free(jpeg);

    var decoded = try imaging.decodeRgb8(testing.allocator, jpeg);
    defer decoded.deinit();

    try testing.expectEqual(src.width, decoded.width);
    try testing.expectEqual(src.height, decoded.height);
    try testing.expect(meanAbsDiffGray(src.data, decoded.data) <= 6.0);
}

test "writeJpegFile writes decodable rgba-derived jpeg" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 8, 8, 4);
    defer src.deinit();
    for (0..src.height) |y| {
        for (0..src.width) |x| {
            const base = src.pixelIndex(x, y, 0);
            src.data[base] = if (x < 4) 255 else 24;
            src.data[base + 1] = if (y < 4) 255 else 16;
            src.data[base + 2] = 48;
            src.data[base + 3] = if ((x + y) % 2 == 0) 255 else 32;
        }
    }

    const path = "._pixio_encode_rgba.jpg";
    defer std.fs.cwd().deleteFile(path) catch {};
    try imaging.writeJpegFile(testing.allocator, path, &src, .{ .quality = 90 });

    const encoded = try std.fs.cwd().readFileAlloc(testing.allocator, path, 1 << 20);
    defer testing.allocator.free(encoded);

    var decoded = try imaging.decodeRgb8(testing.allocator, encoded);
    defer decoded.deinit();

    try testing.expectEqual(src.width, decoded.width);
    try testing.expectEqual(src.height, decoded.height);
}

fn meanAbsDiff(expected: []const u8, actual: []const u8) f32 {
    var total: f32 = 0.0;
    for (expected, actual) |lhs, rhs| {
        const delta = @as(f32, @floatFromInt(@abs(@as(i16, lhs) - @as(i16, rhs))));
        total += delta;
    }
    return total / @as(f32, @floatFromInt(expected.len));
}

fn meanAbsDiffGray(expected: []const u8, actual_rgb: []const u8) f32 {
    var total: f32 = 0.0;
    for (expected, 0..) |gray, index| {
        const rgb_index = index * 3;
        const r = actual_rgb[rgb_index];
        const g = actual_rgb[rgb_index + 1];
        const b = actual_rgb[rgb_index + 2];
        total += @as(f32, @floatFromInt(@abs(@as(i16, gray) - @as(i16, r))));
        total += @as(f32, @floatFromInt(@abs(@as(i16, gray) - @as(i16, g))));
        total += @as(f32, @floatFromInt(@abs(@as(i16, gray) - @as(i16, b))));
    }
    return total / @as(f32, @floatFromInt(actual_rgb.len));
}
