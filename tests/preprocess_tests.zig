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

test "prepareImage cover crops centered content" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 2, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 0, 10, 20, 30, 40, 50, 60, 70 });

    var prepared = try imaging.prepareImage(testing.allocator, &src, .{
        .target_width = 2,
        .target_height = 2,
        .mode = .cover,
        .kernel = .nearest,
        .output_pixel_format = .gray8,
    });
    defer prepared.deinit();

    try testing.expectEqual(imaging.PreprocessMode.cover, prepared.info.mode);
    try testing.expectEqual(@as(usize, 1), prepared.info.offset_x);
    try testing.expectEqual(@as(usize, 0), prepared.info.offset_y);
    try testing.expectEqualSlices(u8, &[_]u8{ 10, 20, 50, 60 }, prepared.image.data);
}

test "remapBoxToSource handles fit and letterbox transforms" {
    const testing = std.testing;

    var fit_box = imaging.BoxF32{ .x1 = 0, .y1 = 0, .x2 = 4, .y2 = 2 };
    imaging.remapPreprocessedBoxToSource(&fit_box, .{
        .mode = .fit,
        .src_width = 2,
        .src_height = 1,
        .request_width = 4,
        .request_height = 2,
        .output_width = 4,
        .output_height = 2,
        .resized_width = 4,
        .resized_height = 2,
        .offset_x = 0,
        .offset_y = 0,
        .scale_x = 2.0,
        .scale_y = 2.0,
    });
    try testing.expectEqual(@as(f32, 0.0), fit_box.x1);
    try testing.expectEqual(@as(f32, 0.0), fit_box.y1);
    try testing.expectEqual(@as(f32, 2.0), fit_box.x2);
    try testing.expectEqual(@as(f32, 1.0), fit_box.y2);

    var letterboxed = imaging.BoxF32{ .x1 = 1, .y1 = 1, .x2 = 3, .y2 = 2 };
    imaging.remapPreprocessedBoxToSource(&letterboxed, .{
        .mode = .letterbox,
        .src_width = 2,
        .src_height = 1,
        .request_width = 4,
        .request_height = 4,
        .output_width = 4,
        .output_height = 4,
        .resized_width = 2,
        .resized_height = 1,
        .offset_x = 1,
        .offset_y = 1,
        .scale_x = 1.0,
        .scale_y = 1.0,
    });
    try testing.expectEqual(@as(f32, 0.0), letterboxed.x1);
    try testing.expectEqual(@as(f32, 0.0), letterboxed.y1);
    try testing.expectEqual(@as(f32, 2.0), letterboxed.x2);
    try testing.expectEqual(@as(f32, 1.0), letterboxed.y2);
}

test "prepareImageBatch and prepareTensorBatch process multiple inputs" {
    const testing = std.testing;

    var a = try imaging.ImageU8.init(testing.allocator, 2, 1, 1);
    defer a.deinit();
    @memcpy(a.data, &[_]u8{ 10, 20 });

    var b = try imaging.ImageU8.init(testing.allocator, 2, 1, 1);
    defer b.deinit();
    @memcpy(b.data, &[_]u8{ 30, 40 });

    const inputs = [_]*const imaging.ImageU8{ &a, &b };

    var batch = try imaging.prepareImageBatch(testing.allocator, &inputs, .{
        .target_width = 4,
        .target_height = 1,
        .mode = .fit,
        .kernel = .nearest,
        .output_pixel_format = .rgb8,
    });
    defer batch.deinit();

    try testing.expectEqual(@as(usize, 2), batch.items.len);
    try testing.expectEqualSlices(u8, &[_]u8{
        10, 10, 10,
        10, 10, 10,
        20, 20, 20,
        20, 20, 20,
    }, batch.items[0].image.data);

    var tensor_batch = try imaging.prepareTensorBatch(testing.allocator, &inputs, .{
        .target_width = 2,
        .target_height = 1,
        .mode = .fit,
        .kernel = .nearest,
        .output_pixel_format = .gray8,
    });
    defer tensor_batch.deinit();

    try testing.expectEqual(@as(usize, 2), tensor_batch.items.len);
    try testing.expectEqual(@as(usize, 1), tensor_batch.items[0].tensor.channels);
    try testing.expectEqualSlices(f32, &[_]f32{
        10.0 / 255.0,
        20.0 / 255.0,
    }, tensor_batch.items[0].tensor.data);
}
