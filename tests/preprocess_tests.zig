const std = @import("std");
const imaging = @import("Pixio");

test "prepareImage fit converts format and exact-resizes" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 10, 200 });

    var prepared = try imaging.prepareImage(testing.allocator, &src, .{
        .target_width = 4,
        .target_height = 1,
        .mode = .fit,
        .kernel = .nearest,
        .output_pixel_format = .rgb8,
    });
    defer prepared.deinit();

    try testing.expectEqual(@as(usize, 4), prepared.image.width);
    try testing.expectEqual(@as(usize, 1), prepared.image.height);
    try testing.expectEqual(@as(usize, 3), prepared.image.channels);
    try testing.expectEqual(imaging.PreprocessMode.fit, prepared.info.mode);
    try testing.expectEqualSlices(u8, &[_]u8{
        10, 10, 10,
        10, 10, 10,
        200, 200, 200,
        200, 200, 200,
    }, prepared.image.data);
}

test "prepareImage contain respects bounds and no-upscale" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 3, 2, 3);
    defer src.deinit();
    src.fill(7);

    var prepared = try imaging.prepareImage(testing.allocator, &src, .{
        .target_width = 10,
        .target_height = 10,
        .mode = .contain,
        .allow_upscale = false,
    });
    defer prepared.deinit();

    try testing.expectEqual(src.width, prepared.image.width);
    try testing.expectEqual(src.height, prepared.image.height);
    try testing.expectEqual(@as(usize, 0), prepared.info.offset_x);
    try testing.expectEqual(@as(usize, 0), prepared.info.offset_y);
}

test "prepareImage letterbox pads centered rgba canvas" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 4);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        255, 0, 0, 128,
        0, 255, 0, 64,
    });

    var prepared = try imaging.prepareImage(testing.allocator, &src, .{
        .target_width = 4,
        .target_height = 4,
        .mode = .letterbox,
        .kernel = .nearest,
        .output_pixel_format = .rgba8,
        .pad_value = 12,
        .allow_upscale = false,
    });
    defer prepared.deinit();

    try testing.expectEqual(@as(usize, 4), prepared.image.width);
    try testing.expectEqual(@as(usize, 4), prepared.image.height);
    try testing.expectEqual(@as(usize, 1), prepared.info.resized_height);
    try testing.expectEqual(@as(usize, 1), prepared.info.offset_x);
    try testing.expectEqual(@as(usize, 1), prepared.info.offset_y);

    try testing.expectEqualSlices(u8, &[_]u8{ 12, 12, 12, 255 }, prepared.image.data[0..4]);
}

test "prepareTensor produces normalized chw tensor" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 3);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        0, 10, 20,
        30, 40, 50,
    });

    var prepared = try imaging.prepareTensor(testing.allocator, &src, .{
        .target_width = 2,
        .target_height = 1,
        .mode = .fit,
        .kernel = .nearest,
        .output_pixel_format = .rgb8,
        .normalize = .{
            .scale = 1.0,
            .mean = &[_]f32{ 1.0, 2.0, 3.0 },
            .std = &[_]f32{ 1.0, 2.0, 4.0 },
        },
    });
    defer prepared.deinit();

    try testing.expectEqual(@as(usize, 3), prepared.tensor.channels);
    try testing.expectEqualSlices(f32, &[_]f32{
        -1.0, 29.0,
        4.0, 19.0,
        4.25, 11.75,
    }, prepared.tensor.data);
}

test "prepareImage validates requested shape" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 1, 1, 3);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 1, 2, 3 });

    try testing.expectError(error.InvalidImageDimensions, imaging.prepareImage(testing.allocator, &src, .{
        .target_width = 0,
        .target_height = 1,
    }));
}
