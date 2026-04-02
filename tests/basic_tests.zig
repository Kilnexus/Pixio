const std = @import("std");
const imaging = @import("Pixio");

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

test "resize and letterbox reject invalid dimensions" {
    const testing = std.testing;

    var src = try imaging.ImageU8.init(testing.allocator, 4, 3, 3);
    defer src.deinit();
    src.fill(10);

    try testing.expectError(error.InvalidImageDimensions, imaging.resizeBilinear(testing.allocator, &src, 0, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.letterboxImage(testing.allocator, &src, 0, 160, 114));

    var empty = [_]u8{};
    const invalid_src = imaging.ImageU8{
        .allocator = testing.allocator,
        .width = 0,
        .height = 3,
        .channels = 3,
        .data = empty[0..],
    };

    try testing.expectError(error.InvalidImageDimensions, imaging.resizeBilinear(testing.allocator, &invalid_src, 8, 6));
    try testing.expectError(error.InvalidImageDimensions, imaging.letterboxImage(testing.allocator, &invalid_src, 160, 160, 114));
    try testing.expectError(error.InvalidImageDimensions, imaging.coverImage(testing.allocator, &invalid_src, 160, 160));
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
