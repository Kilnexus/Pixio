const std = @import("std");
const imaging = @import("Pixio");

test "probeInfo reports jpeg exif orientation and oriented dimensions" {
    const testing = std.testing;

    const jpeg = try buildOrientedTestJpeg(testing.allocator, 6);
    defer testing.allocator.free(jpeg);

    const info = try imaging.probeInfo(jpeg);
    try testing.expectEqual(imaging.ImageFormat.jpeg, info.format);
    try testing.expectEqual(@as(usize, 1), info.width);
    try testing.expectEqual(@as(usize, 2), info.height);
    try testing.expectEqual(@as(u8, 6), info.exif_orientation);
}

test "decodeRgb8 auto-applies jpeg exif orientation" {
    const testing = std.testing;

    const jpeg = try buildOrientedTestJpeg(testing.allocator, 6);
    defer testing.allocator.free(jpeg);

    var decoded = try imaging.decodeRgb8(testing.allocator, jpeg);
    defer decoded.deinit();

    try testing.expectEqual(@as(usize, 1), decoded.width);
    try testing.expectEqual(@as(usize, 2), decoded.height);
    try testing.expect(decoded.data[0] < decoded.data[3]);
}

fn buildOrientedTestJpeg(allocator: std.mem.Allocator, orientation: u8) ![]u8 {
    var src = try imaging.ImageU8.init(allocator, 2, 1, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 0, 255 });

    const jpeg = try imaging.encodeJpegAlloc(allocator, &src, .{ .quality = 95 });
    defer allocator.free(jpeg);

    const app1 = buildExifOrientationApp1(orientation);
    const out = try allocator.alloc(u8, jpeg.len + app1.len);
    @memcpy(out[0..2], jpeg[0..2]);
    @memcpy(out[2 .. 2 + app1.len], &app1);
    @memcpy(out[2 + app1.len ..], jpeg[2..]);
    return out;
}

fn buildExifOrientationApp1(orientation: u8) [36]u8 {
    var segment = [_]u8{0} ** 36;
    segment[0] = 0xff;
    segment[1] = 0xe1;
    segment[2] = 0x00;
    segment[3] = 0x22;
    @memcpy(segment[4..10], "Exif\x00\x00");
    @memcpy(segment[10..12], "II");
    segment[12] = 42;
    segment[13] = 0;
    segment[14] = 8;
    segment[15] = 0;
    segment[16] = 0;
    segment[17] = 0;
    segment[18] = 1;
    segment[19] = 0;
    segment[20] = 0x12;
    segment[21] = 0x01;
    segment[22] = 3;
    segment[23] = 0;
    segment[24] = 1;
    segment[25] = 0;
    segment[26] = 0;
    segment[27] = 0;
    segment[28] = orientation;
    segment[29] = 0;
    segment[30] = 0;
    segment[31] = 0;
    segment[32] = 0;
    segment[33] = 0;
    segment[34] = 0;
    segment[35] = 0;
    return segment;
}
