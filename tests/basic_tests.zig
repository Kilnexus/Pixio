const std = @import("std");
const imaging = @import("Pixio");

test "descriptorForChannels infers canonical pixel metadata" {
    const testing = std.testing;

    const gray = try imaging.descriptorForChannels(1);
    try testing.expectEqual(imaging.PixelFormat.gray8, gray.pixel_format);
    try testing.expectEqual(imaging.AlphaMode.opaque_pixels, gray.alpha_mode);

    const rgba = try imaging.descriptorForChannels(4);
    try testing.expectEqual(imaging.PixelFormat.rgba8, rgba.pixel_format);
    try testing.expectEqual(imaging.AlphaMode.straight, rgba.alpha_mode);

    try testing.expectError(error.InvalidPixelFormat, imaging.descriptorForChannels(2));
}

test "image descriptor validation rejects impossible alpha combinations" {
    const testing = std.testing;

    try testing.expectError(error.InvalidImageDescriptor, (imaging.ImageDescriptor{
        .pixel_format = .rgb8,
        .alpha_mode = .straight,
    }).validate());
}

test "constImageView exposes packed layout and subview" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 3, 2, 3);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18,
    });

    const view = try imaging.constImageView(&src);
    try testing.expectEqual(@as(usize, 9), view.layout.row_stride);
    try testing.expectEqual(imaging.PixelFormat.rgb8, view.layout.descriptor.pixel_format);
    try testing.expectEqualSlices(u8, &[_]u8{ 4, 5, 6 }, view.pixelSlice(1, 0));

    const sub = try view.subview(1, 0, 2, 2);
    try testing.expectEqual(@as(usize, 2), sub.layout.width);
    try testing.expectEqual(@as(usize, 2), sub.layout.height);
    try testing.expectEqualSlices(u8, &[_]u8{ 4, 5, 6, 7, 8, 9 }, sub.row(0));
    try testing.expectEqualSlices(u8, &[_]u8{ 13, 14, 15, 16, 17, 18 }, sub.row(1));
}

test "resizeBilinear preserves shape metadata" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 3, 3);
    defer src.deinit();
    src.fill(10);

    var dst = try imaging.resizeBilinear(testing.allocator, &src, 8, 6);
    defer dst.deinit();

    try testing.expectEqual(@as(usize, 8), dst.width);
    try testing.expectEqual(@as(usize, 6), dst.height);
    try testing.expectEqual(@as(usize, 3), dst.channels);
}

test "resizeNearest picks nearest source samples" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 1, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 10, 20, 30, 40 });

    var dst = try imaging.resizeNearest(testing.allocator, &src, 2, 1);
    defer dst.deinit();

    try testing.expectEqual(@as(usize, 2), dst.width);
    try testing.expectEqualSlices(u8, &[_]u8{ 20, 40 }, dst.data);
}

test "resizeArea averages source coverage for downsampling" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 1, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 0, 100, 200, 255 });

    var dst = try imaging.resizeArea(testing.allocator, &src, 2, 1);
    defer dst.deinit();

    try testing.expectEqual(@as(usize, 2), dst.width);
    try testing.expectEqualSlices(u8, &[_]u8{ 50, 228 }, dst.data);
}

test "resizeArea averages each channel independently" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 2, 3);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        0, 0, 0,
        100, 20, 40,
        200, 40, 80,
        255, 60, 120,
    });

    var dst = try imaging.resizeArea(testing.allocator, &src, 1, 1);
    defer dst.deinit();

    try testing.expectEqualSlices(u8, &[_]u8{ 139, 30, 60 }, dst.data);
}

test "letterboxImage computes centered padding" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 100, 50, 3);
    defer src.deinit();
    src.fill(255);

    var boxed = try imaging.letterboxImage(testing.allocator, &src, 160, 160, 114);
    defer boxed.deinit();

    try testing.expectEqual(@as(usize, 160), boxed.image.width);
    try testing.expectEqual(@as(usize, 160), boxed.image.height);
    try testing.expectEqual(@as(usize, 160), boxed.info.resized_width);
    try testing.expectEqual(@as(usize, 80), boxed.info.resized_height);
    try testing.expectEqual(@as(usize, 0), boxed.info.pad_left);
    try testing.expectEqual(@as(usize, 40), boxed.info.pad_top);
}

test "cropImage extracts sub-rectangle" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 2, 3);
    defer src.deinit();

    @memcpy(src.data, &[_]u8{
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
        13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    });

    var cropped = try imaging.cropImage(testing.allocator, &src, 1, 0, 2, 2);
    defer cropped.deinit();

    try testing.expectEqual(@as(usize, 2), cropped.width);
    try testing.expectEqual(@as(usize, 2), cropped.height);
    try testing.expectEqualSlices(u8, &[_]u8{
        4, 5, 6, 7, 8, 9,
        16, 17, 18, 19, 20, 21,
    }, cropped.data);
}

test "coverImage scales and center crops" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 2, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 0, 10, 20, 30, 40, 50, 60, 70 });

    var covered = try imaging.coverImage(testing.allocator, &src, 2, 2);
    defer covered.deinit();

    try testing.expectEqual(@as(usize, 4), covered.info.resized_width);
    try testing.expectEqual(@as(usize, 2), covered.info.resized_height);
    try testing.expectEqual(@as(usize, 1), covered.info.crop_left);
    try testing.expectEqual(@as(usize, 0), covered.info.crop_top);
    try testing.expectEqualSlices(u8, &[_]u8{ 10, 20, 50, 60 }, covered.image.data);
}

test "padImage adds constant border" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 10, 20 });

    var padded = try imaging.padImage(testing.allocator, &src, 1, 1, 1, 0, 3);
    defer padded.deinit();

    try testing.expectEqual(@as(usize, 4), padded.width);
    try testing.expectEqual(@as(usize, 2), padded.height);
    try testing.expectEqualSlices(u8, &[_]u8{
        3, 3, 3, 3,
        3, 10, 20, 3,
    }, padded.data);
}

test "flipImageHorizontal mirrors rows" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 3, 1, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 1, 2, 3 });

    var flipped = try imaging.flipImageHorizontal(testing.allocator, &src);
    defer flipped.deinit();

    try testing.expectEqualSlices(u8, &[_]u8{ 3, 2, 1 }, flipped.data);
}

test "flipImageVertical mirrors columns" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 2, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 1, 2, 3, 4 });

    var flipped = try imaging.flipImageVertical(testing.allocator, &src);
    defer flipped.deinit();

    try testing.expectEqualSlices(u8, &[_]u8{ 3, 4, 1, 2 }, flipped.data);
}

test "rotateImage90Cw rotates clockwise" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 3, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 1, 2, 3, 4, 5, 6 });

    var rotated = try imaging.rotateImage90Cw(testing.allocator, &src);
    defer rotated.deinit();

    try testing.expectEqual(@as(usize, 3), rotated.width);
    try testing.expectEqual(@as(usize, 2), rotated.height);
    try testing.expectEqualSlices(u8, &[_]u8{ 5, 3, 1, 6, 4, 2 }, rotated.data);
}

test "rotateImage90Ccw rotates counter-clockwise" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 3, 1);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 1, 2, 3, 4, 5, 6 });

    var rotated = try imaging.rotateImage90Ccw(testing.allocator, &src);
    defer rotated.deinit();

    try testing.expectEqual(@as(usize, 3), rotated.width);
    try testing.expectEqual(@as(usize, 2), rotated.height);
    try testing.expectEqualSlices(u8, &[_]u8{ 2, 4, 6, 1, 3, 5 }, rotated.data);
}

test "convertImage converts gray rgb and rgba layouts" {
    const testing = std.testing;

    var gray = try imaging.ImageU8.init(testing.allocator, 2, 1, 1);
    defer gray.deinit();
    @memcpy(gray.data, &[_]u8{ 20, 200 });

    var rgb = try imaging.convertToRgb8(testing.allocator, &gray);
    defer rgb.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 20, 20, 20, 200, 200, 200 }, rgb.data);

    var rgba = try imaging.convertToRgba8(testing.allocator, &rgb);
    defer rgba.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{ 20, 20, 20, 255, 200, 200, 200, 255 }, rgba.data);

    var roundtrip_gray = try imaging.convertToGray8(testing.allocator, &rgba);
    defer roundtrip_gray.deinit();
    try testing.expectEqualSlices(u8, gray.data, roundtrip_gray.data);
}

test "premultiply and unpremultiply rgba are approximately inverse" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 4);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        255, 128, 0, 128,
        10, 40, 200, 64,
    });

    var premultiplied = try imaging.premultiplyRgba8(testing.allocator, &src);
    defer premultiplied.deinit();
    try testing.expectEqualSlices(u8, &[_]u8{
        128, 64, 0, 128,
        3, 10, 50, 64,
    }, premultiplied.data);

    var restored = try imaging.unpremultiplyRgba8(testing.allocator, &premultiplied);
    defer restored.deinit();

    try testing.expectEqual(@as(usize, 4), restored.channels);
    try testing.expect(pixelMaxAbsDiff(src.data, restored.data) <= 2);
}

test "compositeOver blends rgba foreground over rgb background" {
    const testing = std.testing;

    var foreground = try imaging.ImageU8.init(testing.allocator, 2, 1, 4);
    defer foreground.deinit();
    @memcpy(foreground.data, &[_]u8{
        255, 0, 0, 128,
        0, 255, 0, 64,
    });

    var background = try imaging.ImageU8.init(testing.allocator, 2, 1, 3);
    defer background.deinit();
    @memcpy(background.data, &[_]u8{
        0, 0, 255,
        255, 255, 255,
    });

    var composed = try imaging.compositeOver(testing.allocator, &foreground, &background);
    defer composed.deinit();

    try testing.expectEqual(@as(usize, 3), composed.channels);
    try testing.expectEqualSlices(u8, &[_]u8{
        128, 0, 127,
        191, 255, 191,
    }, composed.data);
}

test "compositeOver preserves rgba output alpha when background has alpha" {
    const testing = std.testing;

    var foreground = try imaging.ImageU8.init(testing.allocator, 1, 1, 4);
    defer foreground.deinit();
    @memcpy(foreground.data, &[_]u8{ 255, 0, 0, 128 });

    var background = try imaging.ImageU8.init(testing.allocator, 1, 1, 4);
    defer background.deinit();
    @memcpy(background.data, &[_]u8{ 0, 0, 255, 128 });

    var composed = try imaging.compositeOver(testing.allocator, &foreground, &background);
    defer composed.deinit();

    try testing.expectEqual(@as(usize, 4), composed.channels);
    try testing.expectEqualSlices(u8, &[_]u8{ 128, 0, 127, 192 }, composed.data);
}

test "imageToTensorChwF32 packs channels-first normalized floats" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 2, 1, 3);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{
        10, 20, 30,
        40, 50, 60,
    });

    var tensor = try imaging.imageToTensorChwF32(testing.allocator, &src, .{
        .scale = 1.0,
        .mean = &[_]f32{ 1.0, 2.0, 3.0 },
        .std = &[_]f32{ 1.0, 2.0, 4.0 },
    });
    defer tensor.deinit();

    try testing.expectEqual(@as(usize, 3), tensor.channels);
    try testing.expectEqual(@as(usize, 1), tensor.height);
    try testing.expectEqual(@as(usize, 2), tensor.width);
    try testing.expectEqualSlices(f32, &[_]f32{
        9.0, 39.0,
        9.0, 24.0,
        6.75, 14.25,
    }, tensor.data);
}

test "imageToTensorChwF32 validates normalization vector lengths" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 1, 1, 3);
    defer src.deinit();
    @memcpy(src.data, &[_]u8{ 1, 2, 3 });

    try testing.expectError(error.InvalidNormalizationSpec, imaging.imageToTensorChwF32(testing.allocator, &src, .{
        .mean = &[_]f32{ 0.0, 1.0 },
    }));
}

test "remapCoveredBoxToSource accounts for crop offsets" {
    const testing = std.testing;

    var box = imaging.BoxF32{
        .x1 = 0,
        .y1 = 0,
        .x2 = 2,
        .y2 = 2,
    };

    imaging.remapCoveredBoxToSource(&box, 1, 0, 2.0, 2.0, 4, 2);

    try testing.expectEqual(@as(f32, 0.5), box.x1);
    try testing.expectEqual(@as(f32, 0.0), box.y1);
    try testing.expectEqual(@as(f32, 1.5), box.x2);
    try testing.expectEqual(@as(f32, 1.0), box.y2);
}

test "convert and composite validate input contracts" {
    const testing = std.testing;

    var rgb = try imaging.ImageU8.init(testing.allocator, 1, 1, 3);
    defer rgb.deinit();
    @memcpy(rgb.data, &[_]u8{ 1, 2, 3 });

    try testing.expectError(error.InvalidChannelCount, imaging.premultiplyRgba8(testing.allocator, &rgb));

    var fg = try imaging.ImageU8.init(testing.allocator, 1, 1, 4);
    defer fg.deinit();
    @memcpy(fg.data, &[_]u8{ 1, 2, 3, 4 });

    var bg = try imaging.ImageU8.init(testing.allocator, 2, 1, 3);
    defer bg.deinit();
    @memcpy(bg.data, &[_]u8{ 1, 2, 3, 4, 5, 6 });

    try testing.expectError(error.ShapeMismatch, imaging.compositeOver(testing.allocator, &fg, &bg));
}

test "resize and letterbox reject invalid dimensions" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 3, 3);
    defer src.deinit();
    src.fill(10);

    try testing.expectError(error.InvalidImageDimensions, imaging.resizeNearest(testing.allocator, &src, 0, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.resizeBilinear(testing.allocator, &src, 0, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.resizeArea(testing.allocator, &src, 0, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.letterboxImage(testing.allocator, &src, 0, 160, 114));

    var empty = [_]u8{};
    const invalid_src = imaging.ImageU8{
        .allocator = testing.allocator,
        .width = 0,
        .height = 3,
        .channels = 3,
        .data = empty[0..],
    };

    try testing.expectError(error.InvalidImageDimensions, imaging.resizeNearest(testing.allocator, &invalid_src, 8, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.resizeBilinear(testing.allocator, &invalid_src, 8, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.resizeArea(testing.allocator, &invalid_src, 8, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.letterboxImage(testing.allocator, &invalid_src, 160, 160, 114));
    try testing.expectError(error.InvalidImageDimensions, imaging.coverImage(testing.allocator, &invalid_src, 160, 160));
    try testing.expectError(error.InvalidImageDimensions, imaging.padImage(testing.allocator, &invalid_src, 1, 1, 1, 1, 0));
    try testing.expectError(error.InvalidImageDimensions, imaging.flipImageHorizontal(testing.allocator, &invalid_src));
    try testing.expectError(error.InvalidImageDimensions, imaging.rotateImage90Cw(testing.allocator, &invalid_src));
    try testing.expectError(error.InvalidCropBounds, imaging.cropImage(testing.allocator, &src, 3, 2, 2, 2));
}

test "detectFormat recognizes png and bmp signatures" {
    const testing = std.testing;

    try testing.expectEqual(imaging.ImageFormat.png, imaging.detectFormat("\x89PNG\r\n\x1a\nrest"));
    try testing.expectEqual(imaging.ImageFormat.bmp, imaging.detectFormat("BMrest"));
    try testing.expectEqual(imaging.ImageFormat.jpeg, imaging.detectFormat("\xff\xd8\xff\xe0"));
    try testing.expectEqual(imaging.ImageFormat.gif, imaging.detectFormat("GIF89arest"));
    try testing.expectEqual(imaging.ImageFormat.ico, imaging.detectFormat("\x00\x00\x01\x00rest"));
    try testing.expectEqual(imaging.ImageFormat.webp, imaging.detectFormat("RIFF\x1a\x00\x00\x00WEBP"));
}

fn pixelMaxAbsDiff(lhs: []const u8, rhs: []const u8) u8 {
    var max_diff: u8 = 0;
    for (lhs, rhs) |a, b| {
        const diff: u8 = @intCast(@abs(@as(i16, a) - @as(i16, b)));
        if (diff > max_diff) max_diff = diff;
    }
    return max_diff;
}
