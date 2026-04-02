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
